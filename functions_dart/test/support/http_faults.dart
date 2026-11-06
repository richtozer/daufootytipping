import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Fails the requests the test selects, to prove a caller fails closed.
class FailRequests extends http.BaseClient {
  FailRequests(this._inner, this._fail);

  final http.Client _inner;
  final bool Function(http.BaseRequest request) _fail;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_fail(request)) {
      throw http.ClientException('injected failure', request.url);
    }
    return _inner.send(request);
  }
}

/// Delivers the requests the test selects and then loses the response: the
/// database applies the write and the caller is told only that the connection
/// failed. The case where "failed" and "not applied" are not the same thing.
class LoseResponses extends http.BaseClient {
  LoseResponses(this._inner, this._lose);

  final http.Client _inner;
  final bool Function(http.BaseRequest request) _lose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (_lose(request)) {
      await response.stream.drain<void>();
      throw http.ClientException('connection reset', request.url);
    }
    return response;
  }
}

/// Holds the requests the test selects until it calls [open], then forwards
/// them: a request that outlives the caller that gave up on it.
class HoldRequests extends http.BaseClient {
  HoldRequests(this._inner, this._hold);

  final http.Client _inner;
  final bool Function(http.BaseRequest request) _hold;
  final Completer<void> _open = Completer<void>();

  void open() => _open.complete();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_hold(request)) {
      await _open.future;
    }
    return _inner.send(request);
  }
}

/// Polls [check] until it is true, failing the test if it is not within [within].
Future<void> eventually(
  Future<bool> Function() check, {
  Duration within = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(within);
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $within');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Remembers every request that goes through it, so a test can say how a change
/// was written (one atomic update, or several writes).
class RecordRequests extends http.BaseClient {
  RecordRequests(this._inner);

  final http.Client _inner;
  final List<({String method, String path, String body})> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final body = request is http.Request ? request.body : '';
    requests.add((method: request.method, path: request.url.path, body: body));
    return _inner.send(request);
  }
}
