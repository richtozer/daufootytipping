import 'dart:async';

import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three reads, held in memory, with scripted failures.
class _Reads implements IdentityReads {
  final Map<String, String> index = <String, String>{};
  final Map<String, Map<String, dynamic>> privateRecords =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> publicRecords =
      <String, Map<String, dynamic>>{};

  /// How many times the next reads of each kind throw before they work; -1 is forever.
  final Map<String, int> failures = <String, int>{};

  /// Reads of this kind never complete.
  final Set<String> hang = <String>{};

  final Map<String, int> counts = <String, int>{};

  Future<T> _read<T>(String kind, T Function() value) async {
    counts[kind] = (counts[kind] ?? 0) + 1;
    if (hang.contains(kind)) {
      return Completer<T>().future;
    }
    final remaining = failures[kind] ?? 0;
    if (remaining != 0) {
      if (remaining > 0) {
        failures[kind] = remaining - 1;
      }
      throw StateError('permission-denied reading $kind');
    }
    return value();
  }

  @override
  Future<String?> authIndexEntry(String uid) =>
      _read('index', () => index[uid]);

  @override
  Future<Map<String, dynamic>?> privateRecord(String tipperId) =>
      _read('private', () => privateRecords[tipperId]);

  @override
  Future<Map<String, dynamic>?> publicRecord(String tipperId) =>
      _read('public', () => publicRecords[tipperId]);
}

class _Invoker implements IdentityCallableInvoker {
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  Object? answer;
  Object? failWith;

  @override
  Future<Object?> call(
    String endpoint,
    Map<String, Object?> data, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    expect(endpoint, linkOrCreateTipperEndpoint);
    requests.add(data);
    if (failWith != null) {
      throw failWith!;
    }
    return answer;
  }
}

List<Map<String, Object?>> _info(String reason) => <Map<String, Object?>>[
  <String, Object?>{'reason': reason, 'domain': identityErrorDomain},
];

IdentityFailure _refusal(
  String reason, {
  String code = 'failed-precondition',
  String message = 'Server says no',
}) => IdentityFailure.fromFunctionsError(
  code: code,
  message: message,
  details: _info(reason),
);

final DAUComp _comp = DAUComp(
  dbkey: 'c1',
  name: '2027',
  aflFixtureJsonURL: Uri.parse('https://example.test/afl'),
  nrlFixtureJsonURL: Uri.parse('https://example.test/nrl'),
  daurounds: const [],
);

const LinkAccount _alice = LinkAccount(
  uid: 'uidA',
  isAnonymous: false,
  photoUrl: 'g.png',
);

void main() {
  late _Reads reads;
  late _Invoker invoker;
  late List<Duration> delays;
  late LinkedTipperResolver resolver;

  setUp(() {
    reads = _Reads();
    invoker = _Invoker();
    delays = <Duration>[];
    resolver = LinkedTipperResolver(
      reads: reads,
      identity: IdentityService(invoker),
      resolveComps: (List keys) async =>
          keys.contains('c1') ? <DAUComp>[_comp] : <DAUComp>[],
      readTimeout: const Duration(milliseconds: 50),
      delay: (Duration d) async => delays.add(d),
    );
  });

  void aliceIsLinked() {
    reads.index['uidA'] = 't1';
    reads.privateRecords['t1'] = <String, dynamic>{
      'authuid': 'uidA',
      'tipperRole': 'admin',
      'logon': 'a@example.test',
      'email': 'a@example.test',
    };
    // The public copy still carries a stale role from before the purge, and a stale
    // account id; the private record is the truth.
    reads.publicRecords['t1'] = <String, dynamic>{
      'name': 'Alice',
      'photoURL': 'a.png',
      'tipperRole': 'tipper',
      'authuid': 'staleUid',
      'compsParticipatedIn': <String>['c1'],
    };
  }

  group('a guest', () {
    test('needs no server and no read, and is never saved', () async {
      final resolution = await resolver.resolve(
        const LinkAccount(uid: 'guestUid123', isAnonymous: true),
      );
      expect(resolution.status, LinkStatus.guest);
      expect(resolution.tipper!.isAnonymous, true);
      expect(resolution.tipper!.dbkey, isNull);
      expect(resolution.tipper!.name, 'guest');
      expect(resolution.tipper!.authuid, 'guestUid123');
      expect(reads.counts, isEmpty);
      expect(invoker.requests, isEmpty);
    });
  });

  group('an account that is already linked', () {
    test(
      'is recognised from its own records, without asking the server',
      () async {
        aliceIsLinked();
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.linked);
        expect(resolution.outcome, isNull);
        expect(invoker.requests, isEmpty);
        final tipper = resolution.tipper!;
        expect(tipper.dbkey, 't1');
        expect(tipper.name, 'Alice');
        expect(tipper.authuid, 'uidA');
        expect(
          tipper.tipperRole,
          TipperRole.admin,
          reason: 'from the private record',
        );
        expect(tipper.logon, 'a@example.test');
        expect(tipper.compsPaidFor, [_comp]);
      },
    );

    test('an index entry that its record does not back is not trusted: the server decides', () async {
      aliceIsLinked();
      reads.privateRecords['t1'] = <String, dynamic>{
        'authuid': 'someoneElse',
        'tipperRole': 'admin',
      };
      invoker.failWith = _refusal(
        identityReasonClaimed,
        message: 'This tipper belongs to another account.',
      );
      final resolution = await resolver.resolve(_alice);
      expect(invoker.requests, hasLength(1));
      expect(resolution.status, LinkStatus.refused);
      expect(resolution.reason, identityReasonClaimed);
      expect(resolution.message, 'This tipper belongs to another account.');
      expect(resolution.tipper, isNull);
    });

    test('an index entry whose private record is missing is also referred to the server', () async {
      aliceIsLinked();
      reads.privateRecords.remove('t1');
      invoker.answer = <String, Object?>{
        'tipperId': 't1',
        'outcome': 'existing',
      };
      final resolution = await resolver.resolve(_alice);
      expect(invoker.requests, hasLength(1));
      expect(
        resolution.status,
        LinkStatus.unavailable,
        reason: 'the record the server vouches for cannot be read yet',
      );
    });
  });

  group('an account that is not linked yet', () {
    test('is linked by the server, then read', () async {
      reads.publicRecords['t9'] = <String, dynamic>{'name': 'Old Timer'};
      reads.privateRecords['t9'] = <String, dynamic>{
        'authuid': 'uidA',
        'tipperRole': 'tipper',
      };
      invoker.answer = <String, Object?>{'tipperId': 't9', 'outcome': 'linked'};
      final resolution = await resolver.resolve(_alice);
      expect(invoker.requests, [
        <String, Object?>{},
      ], reason: 'asked without an alias');
      expect(resolution.status, LinkStatus.linked);
      expect(resolution.outcome, LinkOutcome.linked);
      expect(resolution.tipper!.dbkey, 't9');
      expect(resolution.tipper!.name, 'Old Timer');
    });

    test('with no match and no alias, the server\'s invalid_alias means: ask for one', () async {
      invoker.failWith = _refusal(
        identityReasonInvalidAlias,
        code: 'invalid-argument',
      );
      final resolution = await resolver.resolve(_alice);
      expect(resolution.status, LinkStatus.needsAlias);
    });

    test('with an alias, a record is created', () async {
      reads.publicRecords['t10'] = <String, dynamic>{'name': 'The Oracle'};
      reads.privateRecords['t10'] = <String, dynamic>{
        'authuid': 'uidA',
        'tipperRole': 'tipper',
      };
      invoker.answer = <String, Object?>{
        'tipperId': 't10',
        'outcome': 'created',
      };
      final resolution = await resolver.resolve(_alice, alias: 'The Oracle');
      expect(invoker.requests, [
        <String, Object?>{'alias': 'The Oracle'},
      ]);
      expect(resolution.status, LinkStatus.linked);
      expect(resolution.outcome, LinkOutcome.created);
    });

    test('an alias that is taken, or not acceptable, is a refusal to show beside the alias', () async {
      for (final reason in <String>[
        identityReasonAliasTaken,
        identityReasonInvalidAlias,
      ]) {
        invoker.failWith = _refusal(
          reason,
          code: 'invalid-argument',
          message: 'Pick another.',
        );
        final resolution = await resolver.resolve(_alice, alias: 'x');
        expect(resolution.status, LinkStatus.refused, reason: reason);
        expect(resolution.reason, reason);
        expect(resolution.message, 'Pick another.');
      }
    });

    test('each refusal reaches the user in the server\'s own words', () async {
      for (final reason in <String>[
        identityReasonClaimed,
        identityReasonAmbiguous,
        identityReasonNeedsAudit,
        identityReasonUnverifiedEmail,
        identityReasonCreationDisabled,
      ]) {
        invoker.failWith = _refusal(reason, message: 'Words for $reason');
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.refused, reason: reason);
        expect(resolution.message, 'Words for $reason');
      }
    });

    test('busy, unavailable, switched off and no connection are "not now", not a verdict', () async {
      final failures = <IdentityFailure>[
        _refusal(identityReasonBusy, code: 'aborted'),
        _refusal(identityReasonUnavailable, code: 'unavailable'),
        _refusal(identityReasonNotAvailable),
        IdentityFailure.network(TimeoutException('slow')),
      ];
      for (final failure in failures) {
        invoker.failWith = failure;
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.unavailable, reason: '$failure');
        expect(resolution.tipper, isNull);
      }
    });

    test(
      'a session the server does not accept asks the user to sign in again',
      () async {
        invoker.failWith = IdentityFailure.fromFunctionsError(
          code: 'unauthenticated',
          message: 'x',
        );
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.refused);
        expect(resolution.message, contains('sign in again'));
      },
    );

    test('an answer the client cannot read is a refusal with a generic message, not a crash', () async {
      invoker.answer = <String, Object?>{'nonsense': true};
      final resolution = await resolver.resolve(_alice);
      expect(resolution.status, LinkStatus.refused);
      expect(resolution.message, contains('Something went wrong'));
    });

    test('a record the server says exists but that cannot be read yet is "not now"', () async {
      invoker.answer = <String, Object?>{
        'tipperId': 't11',
        'outcome': 'created',
      };
      final resolution = await resolver.resolve(_alice, alias: 'New');
      expect(resolution.status, LinkStatus.unavailable);
    });
  });

  test('competitions that never load do not hold up signing in: the tipper arrives without the paid ones', () async {
    aliceIsLinked();
    final slow = LinkedTipperResolver(
      reads: reads,
      identity: IdentityService(invoker),
      resolveComps: (List keys) => Completer<List<DAUComp>>().future,
      compsTimeout: const Duration(milliseconds: 20),
      delay: (Duration d) async {},
    );
    final resolution = await slow.resolve(_alice);
    expect(resolution.status, LinkStatus.linked);
    expect(resolution.tipper!.compsPaidFor, isEmpty);
    expect(resolution.tipper!.tipperRole, TipperRole.admin);
  });

  group('a failed read is never "missing"', () {
    test(
      'a read that fails twice and then works is retried with a back-off',
      () async {
        aliceIsLinked();
        reads.failures['index'] = 2;
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.linked);
        expect(reads.counts['index'], 3);
        expect(delays, [
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
        ]);
        expect(invoker.requests, isEmpty);
      },
    );

    test('a read that always fails is "not now", and the server is never asked to link', () async {
      aliceIsLinked();
      reads.failures['index'] = -1;
      final resolution = await resolver.resolve(_alice);
      expect(resolution.status, LinkStatus.unavailable);
      expect(reads.counts['index'], 4, reason: 'one try and three retries');
      expect(
        invoker.requests,
        isEmpty,
        reason: 'unable to look is not the same as not found',
      );
    });

    test('the same for the private record, and for the public one', () async {
      for (final kind in <String>['private', 'public']) {
        aliceIsLinked();
        reads.failures[kind] = -1;
        invoker.requests.clear();
        final resolution = await resolver.resolve(_alice);
        expect(resolution.status, LinkStatus.unavailable, reason: kind);
        expect(invoker.requests, isEmpty, reason: kind);
        reads.failures.clear();
      }
    });

    test('a read that never answers is given up on', () async {
      aliceIsLinked();
      reads.hang.add('index');
      final resolution = await resolver.resolve(_alice);
      expect(resolution.status, LinkStatus.unavailable);
      expect(invoker.requests, isEmpty);
    });

    test('a successful read of nothing is the only thing that sends the account to be linked', () async {
      // No entry at all: the read works and finds nothing.
      invoker.failWith = _refusal(
        identityReasonInvalidAlias,
        code: 'invalid-argument',
      );
      final resolution = await resolver.resolve(_alice);
      expect(reads.counts['index'], 1);
      expect(invoker.requests, hasLength(1));
      expect(resolution.status, LinkStatus.needsAlias);
    });
  });
}
