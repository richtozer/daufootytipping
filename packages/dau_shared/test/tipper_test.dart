import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('Tipper.fromJson reads a purged public record', () {
    test('a record with only the public fields is a tipper', () {
      final tipper = Tipper.fromJson(<String, dynamic>{
        'name': 'Alice',
        'photoURL': 'a.png',
        'compsParticipatedIn': <String>['c1'],
      }, 't1');
      expect(tipper.name, 'Alice');
      expect(tipper.photoURL, 'a.png');
      expect(tipper.dbkey, 't1');
      expect(tipper.authuid, '', reason: 'not known from the public record');
      expect(tipper.tipperRole, TipperRole.tipper);
      expect(tipper.isAnonymous, false);
      expect(tipper.email, isNull);
      expect(tipper.logon, isNull);
      expect(tipper.acctCreatedUTC, isNull);
      expect(tipper.acctLoggedOnUTC, isNull);
    });

    test('a record in the legacy shape still reads as before', () {
      final tipper = Tipper.fromJson(<String, dynamic>{
        'name': 'Alice',
        'authuid': 'uidA',
        'tipperRole': 'admin',
        'email': 'a@example.test',
        'logon': 'a@example.test',
        'isAnonymous': true,
        'acctCreatedUTC': '2026-03-01 04:05:06.000Z',
        'acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
      }, 't1');
      expect(tipper.authuid, 'uidA');
      expect(tipper.tipperRole, TipperRole.admin);
      expect(tipper.email, 'a@example.test');
      expect(tipper.isAnonymous, true);
      expect(tipper.acctCreatedUTC, DateTime.utc(2026, 3, 1, 4, 5, 6));
    });

    test('a list of purged records reads, however many', () async {
      final tippers = await Tipper.fromJsonList(<String, dynamic>{
        't1': <String, dynamic>{'name': 'A'},
        't2': <String, dynamic>{'name': 'B', 'photoURL': 'b.png'},
      }, (_) async => <DAUComp>[]);
      expect(tippers.map((t) => t!.name), ['A', 'B']);
    });
  });

  group('Tipper.fromRecords builds the signed-in user\'s own tipper', () {
    test('the private record is laid over the public one', () {
      final tipper = Tipper.fromRecords(
        key: 't1',
        authuid: 'uidA',
        publicRecord: <String, dynamic>{'name': 'Alice', 'photoURL': 'a.png'},
        privateRecord: <String, dynamic>{
          'authuid': 'uidA',
          'tipperRole': 'admin',
          'email': 'a@example.test',
          'logon': 'login@example.test',
          'isAnonymous': false,
          'acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
        },
      );
      expect(tipper.dbkey, 't1');
      expect(tipper.name, 'Alice');
      expect(tipper.tipperRole, TipperRole.admin);
      expect(tipper.logon, 'login@example.test');
      expect(tipper.authuid, 'uidA');
      expect(tipper.acctLoggedOnUTC, DateTime.utc(2026, 3, 2, 4, 5, 6));
    });

    test('the private role wins over a stale public one', () {
      final tipper = Tipper.fromRecords(
        key: 't1',
        authuid: 'uidA',
        publicRecord: <String, dynamic>{'name': 'A', 'tipperRole': 'admin'},
        privateRecord: <String, dynamic>{'tipperRole': 'tipper'},
      );
      expect(tipper.tipperRole, TipperRole.tipper);
    });

    test(
      'the account id is the one the caller verified, whatever the records say',
      () {
        final tipper = Tipper.fromRecords(
          key: 't1',
          authuid: 'uidVerified',
          publicRecord: <String, dynamic>{'name': 'A', 'authuid': 'uidStale'},
          privateRecord: <String, dynamic>{'authuid': 'uidOther'},
        );
        expect(tipper.authuid, 'uidVerified');
      },
    );

    test(
      'without a private record it is the public one with the verified account id',
      () {
        final tipper = Tipper.fromRecords(
          key: 't1',
          authuid: 'uidA',
          publicRecord: <String, dynamic>{'name': 'A'},
        );
        expect(tipper.name, 'A');
        expect(tipper.authuid, 'uidA');
        expect(tipper.tipperRole, TipperRole.tipper);
      },
    );
  });

  group('withPrivateRecord', () {
    Tipper publicOnly() => Tipper(
      dbkey: 't1',
      compsPaidFor: const [],
      photoURL: 'a.png',
      authuid: '',
      email: null,
      name: 'Alice',
      tipperRole: TipperRole.tipper,
    );

    test(
      'lays the identity fields of the private record over the public ones',
      () {
        final merged = publicOnly().withPrivateRecord(<String, dynamic>{
          'authuid': 'uidA',
          'tipperRole': 'admin',
          'email': 'a@example.test',
          'logon': 'login@example.test',
          'isAnonymous': true,
          'acctCreatedUTC': '2025-01-02 03:04:05.000Z',
          'acctLoggedOnUTC': '2026-02-03 04:05:06.000Z',
        });

        expect(merged.authuid, 'uidA');
        expect(merged.tipperRole, TipperRole.admin);
        expect(merged.email, 'a@example.test');
        expect(merged.logon, 'login@example.test');
        expect(merged.isAnonymous, isTrue);
        expect(merged.acctCreatedUTC, DateTime.utc(2025, 1, 2, 3, 4, 5));
        expect(merged.acctLoggedOnUTC, DateTime.utc(2026, 2, 3, 4, 5, 6));
      },
    );

    test('keeps the public name, photo, paid competitions and key', () {
      final merged = publicOnly().withPrivateRecord(<String, dynamic>{
        'authuid': 'uidA',
        'tipperRole': 'admin',
      });

      expect(merged.dbkey, 't1');
      expect(merged.name, 'Alice');
      expect(merged.photoURL, 'a.png');
    });

    test('a private record without a role is an ordinary tipper', () {
      final merged = publicOnly().withPrivateRecord(<String, dynamic>{
        'authuid': 'uidA',
      });

      expect(merged.tipperRole, TipperRole.tipper);
    });
  });

  group('withIdentityOf', () {
    test(
      'takes the identity of the signed-in tipper and the public fields of the list\'s copy',
      () {
        final fromList = Tipper.fromJson(<String, dynamic>{
          'name': 'Alice (renamed)',
          'photoURL': 'new.png',
        }, 't1');
        final own = Tipper.fromRecords(
          key: 't1',
          authuid: 'uidA',
          publicRecord: <String, dynamic>{'name': 'Alice'},
          privateRecord: <String, dynamic>{
            'tipperRole': 'admin',
            'email': 'a@example.test',
            'logon': 'login@example.test',
            'isAnonymous': false,
            'acctCreatedUTC': '2026-03-01 04:05:06.000Z',
            'acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
          },
        );
        final merged = fromList.withIdentityOf(own);
        expect(merged.name, 'Alice (renamed)');
        expect(merged.photoURL, 'new.png');
        expect(merged.dbkey, 't1');
        expect(merged.authuid, 'uidA');
        expect(merged.tipperRole, TipperRole.admin);
        expect(merged.email, 'a@example.test');
        expect(merged.logon, 'login@example.test');
        expect(merged.acctLoggedOnUTC, DateTime.utc(2026, 3, 2, 4, 5, 6));
        expect(merged == own, true);
      },
    );
  });

  group('equality', () {
    Tipper tipper(String? key, String authuid) => Tipper(
      dbkey: key,
      authuid: authuid,
      email: null,
      name: 'x',
      tipperRole: TipperRole.tipper,
      compsPaidFor: const <DAUComp>[],
    );

    test(
      'the same record is the same tipper, whether or not this copy knows the account id',
      () {
        final own = tipper('t1', 'uidA');
        final fromTheList = tipper('t1', '');
        expect(own == fromTheList, true);
        expect(own.hashCode, fromTheList.hashCode);
        expect(<Tipper>{own, fromTheList}, hasLength(1));
      },
    );

    test('different records are different tippers', () {
      expect(tipper('t1', 'uidA') == tipper('t2', 'uidA'), false);
    });

    test('a guest, with no record, is identified by its account id', () {
      expect(tipper(null, 'guest1') == tipper(null, 'guest1'), true);
      expect(tipper(null, 'guest1').hashCode, tipper(null, 'guest1').hashCode);
      expect(tipper(null, 'guest1') == tipper(null, 'guest2'), false);
    });

    test('a guest is never a saved tipper', () {
      expect(tipper(null, 'uidA') == tipper('t1', 'uidA'), false);
      expect(tipper('t1', 'uidA') == tipper(null, 'uidA'), false);
    });
  });
}
