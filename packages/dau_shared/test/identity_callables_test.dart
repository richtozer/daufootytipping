import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('LinkOrCreateTipperRequest', () {
    test('an absent or empty request has no alias', () {
      expect(LinkOrCreateTipperRequest.fromJson(null).alias, isNull);
      expect(
        LinkOrCreateTipperRequest.fromJson(<String, Object?>{}).alias,
        isNull,
      );
    });

    test('reads the alias and ignores extra keys', () {
      final request = LinkOrCreateTipperRequest.fromJson({
        'alias': 'Pat',
        'newer': 1,
      });
      expect(request.alias, 'Pat');
      expect(request.toJson(), {'alias': 'Pat'});
    });

    test('rejects the wrong shapes', () {
      expect(
        () => LinkOrCreateTipperRequest.fromJson('Pat'),
        throwsFormatException,
      );
      expect(
        () => LinkOrCreateTipperRequest.fromJson({'alias': 7}),
        throwsFormatException,
      );
    });
  });

  group('results round trip', () {
    test('link or create', () {
      for (final outcome in LinkOutcome.values) {
        final result = LinkOrCreateTipperResult(
          tipperId: 't1',
          outcome: outcome,
        );
        final copy = LinkOrCreateTipperResult.fromJson(result.toJson());
        expect(copy.tipperId, 't1');
        expect(copy.outcome, outcome);
      }
      expect(LinkOutcome.created.wire, 'created');
    });

    test('an unknown outcome or a missing id is refused', () {
      expect(
        () => LinkOrCreateTipperResult.fromJson({
          'tipperId': 't',
          'outcome': 'merged',
        }),
        throwsFormatException,
      );
      expect(
        () => LinkOrCreateTipperResult.fromJson({'outcome': 'linked'}),
        throwsFormatException,
      );
      expect(
        () => LinkOrCreateTipperResult.fromJson(null),
        throwsFormatException,
      );
    });

    test('alias update', () {
      final copy = UpdateTipperAliasResult.fromJson(
        const UpdateTipperAliasResult(tipperId: 't', alias: 'New').toJson(),
      );
      expect((copy.tipperId, copy.alias), ('t', 'New'));
    });

    test('tokens', () {
      expect(
        RegisterDeviceTokenResult.fromJson(
          const RegisterDeviceTokenResult(tipperId: 't').toJson(),
        ).tipperId,
        't',
      );
      expect(
        UnregisterDeviceTokenResult.fromJson(
          const UnregisterDeviceTokenResult(removed: false).toJson(),
        ).removed,
        false,
      );
      expect(
        () => UnregisterDeviceTokenResult.fromJson({'removed': 'yes'}),
        throwsFormatException,
      );
    });
  });

  group('requests that need text', () {
    test('an alias update needs an alias', () {
      expect(UpdateTipperAliasRequest.fromJson({'alias': 'Pat'}).alias, 'Pat');
      for (final bad in [
        null,
        <String, Object?>{},
        {'alias': ''},
        {'alias': 3},
        'Pat',
      ]) {
        expect(
          () => UpdateTipperAliasRequest.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('a device token needs text and has a length cap', () {
      expect(
        DeviceTokenRequest.fromJson({'token': 'abc:def'}).token,
        'abc:def',
      );
      expect(
        () => DeviceTokenRequest.fromJson({'token': ''}),
        throwsFormatException,
      );
      expect(
        () => DeviceTokenRequest.fromJson({
          'token': 'x' * (maxDeviceTokenLength + 1),
        }),
        throwsFormatException,
      );
      expect(
        DeviceTokenRequest.fromJson({
          'token': 'x' * maxDeviceTokenLength,
        }).token.length,
        maxDeviceTokenLength,
      );
    });
  });
}
