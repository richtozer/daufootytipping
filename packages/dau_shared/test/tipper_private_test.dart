import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('TipperPrivate', () {
    test('round trips a full record', () {
      final original = TipperPrivate(
        authuid: 'uid-1',
        tipperRole: TipperRole.admin,
        email: 'a@example.com',
        logon: 'login@example.com',
        isAnonymous: false,
        acctCreatedUTC: DateTime.utc(2026, 3, 5, 8),
        acctLoggedOnUTC: DateTime.utc(2026, 10, 19, 1, 2, 3),
      );

      final copy = TipperPrivate.fromJson(original.toJson());

      expect(copy.authuid, 'uid-1');
      expect(copy.tipperRole, TipperRole.admin);
      expect(copy.email, 'a@example.com');
      expect(copy.logon, 'login@example.com');
      expect(copy.acctCreatedUTC, DateTime.utc(2026, 3, 5, 8));
      expect(copy.acctLoggedOnUTC, DateTime.utc(2026, 10, 19, 1, 2, 3));
    });

    test('only writes keys that are in the private field list', () {
      final json = TipperPrivate(
        authuid: 'uid-1',
        email: 'a@example.com',
        logon: 'b@example.com',
        acctCreatedUTC: DateTime.utc(2026),
        acctLoggedOnUTC: DateTime.utc(2026),
      ).toJson();

      expect(tipperPrivateFieldNames, containsAll(json.keys));
      expect(tipperPrivateFieldNames.toSet(), json.keys.toSet());
    });

    test('leaves absent values out', () {
      final json = const TipperPrivate().toJson();

      expect(json.keys.toSet(), {'tipperRole', 'isAnonymous'});
      expect(json['tipperRole'], 'tipper');
    });

    test('a missing, unknown or mistyped role is an ordinary tipper', () {
      for (final role in <Object?>[null, 'Admin', 'owner', 3, true]) {
        final record = TipperPrivate.fromJson({'tipperRole': role});
        expect(record.tipperRole, TipperRole.tipper, reason: '$role');
      }
    });

    test('reads a legacy record as it is stored today', () {
      final record = TipperPrivate.fromJson({
        'authuid': 'uid-1',
        'tipperRole': 'tipper',
        'email': 'a@example.com',
        'acctCreatedUTC': '2026-03-05 08:00:00.000Z',
        'isAnonymous': false,
      });

      expect(record.acctCreatedUTC, DateTime.utc(2026, 3, 5, 8));
      expect(record.logon, isNull);
    });

    test('an unparseable time or empty text is treated as absent', () {
      final record = TipperPrivate.fromJson({
        'authuid': '',
        'acctLoggedOnUTC': 'yesterday',
      });

      expect(record.authuid, isNull);
      expect(record.acctLoggedOnUTC, isNull);
    });
  });

  group('field partition', () {
    test('public and private field lists do not overlap', () {
      expect(
        tipperPublicFieldNames.toSet().intersection(
          tipperPrivateFieldNames.toSet(),
        ),
        isEmpty,
      );
    });

    test('together they cover every key a Tipper record is written with', () {
      final written = Tipper(
        name: 'n',
        authuid: 'uid',
        email: 'e',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      ).toJson().keys.toSet();

      expect({...tipperPublicFieldNames, ...tipperPrivateFieldNames}, written);
    });
  });

  group('purge rules', () {
    test(
      'the legacy fields are in neither the public nor the private list',
      () {
        for (final field in tipperLegacyFieldNames) {
          expect(tipperPublicFieldNames, isNot(contains(field)));
          expect(tipperPrivateFieldNames, isNot(contains(field)));
        }
      },
    );

    test(
      'a placeholder name is readable, never empty, and differs per tipper',
      () {
        expect(
          placeholderTipperName('-OKSr7pvsw7wu_w7ZwQq'),
          'Unnamed tipper w7ZwQq',
        );
        expect(
          placeholderTipperName('-OKSr7pvsw7wu_w7ZwQq'),
          isNot(placeholderTipperName('-OKSr7pvsw7wu_w7AAAAA')),
        );
        expect(placeholderTipperName('abc'), 'Unnamed tipper abc');
      },
    );
  });
}
