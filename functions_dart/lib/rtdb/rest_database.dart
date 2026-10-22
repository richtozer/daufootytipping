import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dart_functions/errors.dart';
import 'package:firebase_dart/database.dart';
import 'package:http/http.dart' as http;

/// Returned from an [RestDatabaseReference.atomicUpdate] decision to leave the
/// location as it is. Nothing is written.
const Object keepCurrentValue = Object();

/// The outcome of [RestDatabaseReference.atomicUpdate].
class AtomicUpdateResult {
  const AtomicUpdateResult({required this.applied, required this.value});

  /// True when the decision's value was written.
  final bool applied;

  /// The value at the location after the call: the value written when
  /// [applied], otherwise the value that was read.
  final Object? value;
}

/// The Realtime Database as the deployed Dart functions use it: the REST API
/// with an authorised [http.Client]. Conditional writes use the ETag the
/// database returns, which is the compare-and-set the identity protocol is
/// built on (DESIGN-database-rules.md, D3).
class RestDatabase {
  RestDatabase({
    required http.Client client,
    required String databaseUrl,
    Duration requestTimeout = defaultRestRequestTimeout,
  }) : _client = client,
       _databaseUrl = databaseUrl,
       _requestTimeout = requestTimeout;

  final http.Client _client;
  final String _databaseUrl;
  final Duration _requestTimeout;

  /// Every write sent through this handle, until it has finished.
  final WriteLedger writes = WriteLedger();

  RestDatabaseReference ref(String path) => RestDatabaseReference(
    client: _client,
    databaseUrl: _databaseUrl,
    path: path,
    ledger: writes,
    requestTimeout: _requestTimeout,
  );
}

/// How long one REST request is waited for.
const Duration defaultRestRequestTimeout = Duration(seconds: 15);

/// Remembers the writes in flight on a [RestDatabase].
///
/// Giving up on a request (a timeout) stops *waiting* for it; it does not stop
/// it. The request can still reach the database afterwards. A caller that must
/// know nothing of its own is still being written, such as the admission
/// wrapper deciding whether it may clear its in-flight marker, asks [settled].
/// Only writes are tracked: a read that outlives its caller changes nothing.
class WriteLedger {
  int _pending = 0;
  final List<Completer<void>> _waiters = [];

  /// How many writes have been sent and have not yet finished (either way).
  int get pendingCount => _pending;

  /// Notes [request], a write that has been sent, and returns it unchanged.
  Future<T> track<T>(Future<T> request) {
    _pending += 1;
    request.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      _pending -= 1;
      if (_pending == 0) {
        for (final waiter in _waiters) {
          waiter.complete();
        }
        _waiters.clear();
      }
    });
    return request;
  }

  /// Completes true once no write is in flight, or false if some still are
  /// after [timeout].
  Future<bool> settled({required Duration timeout}) async {
    if (_pending == 0) {
      return true;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    try {
      await waiter.future.timeout(timeout);
      return true;
    } on TimeoutException {
      _waiters.remove(waiter);
      return _pending == 0;
    }
  }
}

class RestDatabaseReference {
  RestDatabaseReference({
    required http.Client client,
    required String databaseUrl,
    required String path,
    Random? random,
    WriteLedger? ledger,
    Duration requestTimeout = defaultRestRequestTimeout,
  }) : _client = client,
       _databaseUrl = databaseUrl,
       _path = path,
       _random = random ?? Random(),
       _ledger = ledger,
       _requestTimeout = requestTimeout;

  final http.Client _client;
  final String _databaseUrl;
  final String _path;
  final Random _random;
  final WriteLedger? _ledger;
  final Duration _requestTimeout;
  static const int _maxRetryDelayMillis = 200;

  /// Notes a write with the ledger, if there is one.
  Future<T> _tracked<T>(Future<T> write) =>
      _ledger == null ? write : _ledger.track(write);

  String get path => _path;

  String? get _key {
    final segments = _path.split('/').where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? null : segments.last;
  }

  RestDatabaseReference child(String childPath) => RestDatabaseReference(
    client: _client,
    databaseUrl: _databaseUrl,
    path: '$_path/$childPath',
    random: _random,
    ledger: _ledger,
    requestTimeout: _requestTimeout,
  );

  Future<DataSnapshot> once() async {
    final response = await runRtdbRestRequest(
      _client.get(_uri()),
      operation: 'read',
      path: _path,
      timeout: _requestTimeout,
    );
    _throwForRestError(response, 'read', _path);
    return _RestDataSnapshot(_key, _decodeRestBody(response.body));
  }

  Future<void> set(Object? value) async {
    final response = await runRtdbRestRequest(
      _tracked(
        _client.put(
          _uri(),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(value),
        ),
      ),
      operation: 'set',
      path: _path,
      timeout: _requestTimeout,
    );
    _throwForRestError(response, 'set', _path);
  }

  Future<void> update(Map<Object?, Object?> value) async {
    final response = await runRtdbRestRequest(
      _tracked(
        _client.patch(
          _uri(),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(value),
        ),
      ),
      operation: 'update',
      path: _path,
      timeout: _requestTimeout,
    );
    _throwForRestError(response, 'update', _path);
  }

  Future<void> remove() async {
    final response = await runRtdbRestRequest(
      _tracked(_client.delete(_uri())),
      operation: 'remove',
      path: _path,
      timeout: _requestTimeout,
    );
    _throwForRestError(response, 'remove', _path);
  }

  /// Reads the location, asks [decide] what the new value should be, and
  /// writes it only if nobody changed the location in between.
  ///
  /// [decide] returns the new value, `null` to delete, or [keepCurrentValue]
  /// to leave the location alone. It may run more than once, so it must have
  /// no side effects. A conflicting writer makes the write fail with HTTP 412;
  /// the read-decide-write cycle then repeats after a short random pause, until
  /// [timeout] runs out.
  ///
  /// This fails closed: a response without an ETag is an error. Sending
  /// `if-match: *` in its place would overwrite whatever is there, turning a
  /// compare-and-set into an unconditional write.
  Future<AtomicUpdateResult> atomicUpdate(
    FutureOr<Object?> Function(Object? current) decide, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts += 1;
      final readResponse = await runRtdbRestRequest(
        _client.get(_uri(), headers: const {'X-Firebase-ETag': 'true'}),
        operation: 'transaction read',
        path: _path,
        timeout: _remainingTransactionTime(deadline, attempts),
      );
      _throwForRestError(readResponse, 'transaction read', _path);
      final etag = readResponse.headers['etag'];
      if (etag == null || etag.isEmpty) {
        throw InternalError(
          'RTDB REST transaction read for $_path returned no ETag, so a '
          'conditional write is not possible',
        );
      }
      final currentValue = _decodeRestBody(readResponse.body);
      final nextValue = await decide(currentValue);
      if (identical(nextValue, keepCurrentValue)) {
        return AtomicUpdateResult(applied: false, value: currentValue);
      }

      final writeResponse = await runRtdbRestRequest(
        _tracked(
          _client.put(
            _uri(),
            headers: {'content-type': 'application/json', 'if-match': etag},
            body: jsonEncode(nextValue),
          ),
        ),
        operation: 'transaction write',
        path: _path,
        timeout: _remainingTransactionTime(deadline, attempts),
      );
      if (writeResponse.statusCode == 412) {
        await Future<void>.delayed(_retryDelay(attempts));
        continue;
      }
      _throwForRestError(writeResponse, 'transaction write', _path);
      return AtomicUpdateResult(
        applied: true,
        value: _decodeRestBody(writeResponse.body),
      );
    }

    throw AbortedError(
      'RTDB transaction timed out at $_path after $attempts attempts',
    );
  }

  /// The firebase_dart style transaction the scoring locks use. The handler
  /// returns the data to write, or null to leave the location unchanged.
  Future<TransactionResult> runTransaction(
    TransactionHandler transactionHandler, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await atomicUpdate((current) async {
      final updatedData = await transactionHandler(MutableData(_key, current));
      return updatedData == null ? keepCurrentValue : updatedData.value;
    }, timeout: timeout);
    return _RestTransactionResult(
      committed: result.applied,
      dataSnapshot: _RestDataSnapshot(_key, result.value),
    );
  }

  Duration _retryDelay(int attempts) {
    final ceiling = min(_maxRetryDelayMillis, 10 * attempts);
    return Duration(milliseconds: 1 + _random.nextInt(ceiling));
  }

  Duration _remainingTransactionTime(DateTime deadline, int attempts) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw AbortedError(
        'RTDB transaction timed out at $_path after $attempts attempts',
      );
    }
    return remaining < _requestTimeout ? remaining : _requestTimeout;
  }

  Uri _uri() {
    return buildRtdbRestUri(databaseUrl: _databaseUrl, path: _path);
  }
}

Uri buildRtdbRestUri({required String databaseUrl, required String path}) {
  final baseUri = Uri.parse(databaseUrl);
  final databasePathSegments = baseUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final referencePathSegments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  final restPathSegments = referencePathSegments.isEmpty
      ? const ['.json']
      : [
          ...referencePathSegments.take(referencePathSegments.length - 1),
          '${referencePathSegments.last}.json',
        ];

  return baseUri.replace(
    pathSegments: [...databasePathSegments, ...restPathSegments],
  );
}

Future<T> runRtdbRestRequest<T>(
  Future<T> request, {
  required String operation,
  required String path,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await request.timeout(timeout);
  } on TimeoutException {
    throw UnavailableError(
      'RTDB REST $operation timed out after '
      '${timeout.inMilliseconds}ms at $path',
    );
  }
}

class _RestDataSnapshot implements DataSnapshot {
  _RestDataSnapshot(this.key, this.value);

  @override
  final String? key;

  @override
  final Object? value;
}

class _RestTransactionResult implements TransactionResult {
  _RestTransactionResult({required this.committed, required this.dataSnapshot});

  @override
  final bool committed;

  @override
  final DataSnapshot? dataSnapshot;

  @override
  FirebaseDatabaseException? get error => null;
}

Object? _decodeRestBody(String body) {
  if (body.isEmpty) {
    return null;
  }
  return jsonDecode(body);
}

void _throwForRestError(http.Response response, String operation, String path) {
  final statusCode = response.statusCode;
  if (statusCode >= 200 && statusCode < 300) {
    return;
  }
  throw InternalError(
    'RTDB REST $operation failed for $path with HTTP $statusCode: '
    '${response.body}',
  );
}
