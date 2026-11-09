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

  group('UnlinkMyAccount', () {
    test('the request takes nothing and ignores whatever is sent', () {
      expect(UnlinkMyAccountRequest.fromJson(null).toJson(), isEmpty);
      expect(
        UnlinkMyAccountRequest.fromJson({
          'tipperId': 't2',
          'uid': 'u',
        }).toJson(),
        isEmpty,
      );
    });

    test('the result says whether anything was detached', () {
      expect(
        UnlinkMyAccountResult.fromJson({'unlinked': true}).unlinked,
        isTrue,
      );
      expect(UnlinkMyAccountResult.fromJson({'unlinked': false}).toJson(), {
        'unlinked': false,
      });
      expect(
        () => UnlinkMyAccountResult.fromJson({'unlinked': 'yes'}),
        throwsFormatException,
      );
      expect(() => UnlinkMyAccountResult.fromJson(null), throwsFormatException);
    });
  });

  group('AdminUpdateTipper', () {
    test('reads the tipper and each field that is given', () {
      final request = AdminUpdateTipperRequest.fromJson({
        'tipperId': 't1',
        'name': 'Pat',
        'email': 'pat@example.com',
        'role': 'admin',
      });
      expect(request.tipperId, 't1');
      expect(request.name, 'Pat');
      expect(request.email, 'pat@example.com');
      expect(request.role, TipperRole.admin);
      expect(request.toJson(), {
        'tipperId': 't1',
        'name': 'Pat',
        'email': 'pat@example.com',
        'role': 'admin',
      });
    });

    test('a field not given stays out of the request', () {
      final request = AdminUpdateTipperRequest.fromJson({
        'tipperId': 't1',
        'role': 'tipper',
      });
      expect(request.name, isNull);
      expect(request.toJson(), {'tipperId': 't1', 'role': 'tipper'});
    });

    test(
      'rejects a request with nothing to change, no tipper, or a role that does not exist',
      () {
        expect(
          () => AdminUpdateTipperRequest.fromJson({'tipperId': 't1'}),
          throwsFormatException,
        );
        expect(
          () => AdminUpdateTipperRequest.fromJson({'name': 'Pat'}),
          throwsFormatException,
        );
        expect(
          () => AdminUpdateTipperRequest.fromJson({
            'tipperId': 't1',
            'role': 'superuser',
          }),
          throwsFormatException,
        );
        expect(
          () =>
              AdminUpdateTipperRequest.fromJson({'tipperId': 't1', 'name': 7}),
          throwsFormatException,
        );
      },
    );

    test('the result lists what changed', () {
      final result = AdminUpdateTipperResult.fromJson({
        'tipperId': 't1',
        'changed': ['name', 'role'],
      });
      expect(result.changed, ['name', 'role']);
      expect(result.toJson(), {
        'tipperId': 't1',
        'changed': ['name', 'role'],
      });
      expect(
        () => AdminUpdateTipperResult.fromJson({
          'tipperId': 't1',
          'changed': 'name',
        }),
        throwsFormatException,
      );
    });
  });

  group('AdminMergeTippers', () {
    test('the options default to off, so nothing is merged by accident', () {
      final request = AdminMergeTippersRequest.fromJson({
        'originalId': 't1',
        'targetId': 't2',
      });
      expect(request.mergeTips, isFalse);
      expect(request.mergeLogon, isFalse);
      expect(request.dryRun, isFalse);
    });

    test('reads every option', () {
      final request = AdminMergeTippersRequest.fromJson({
        'originalId': 't1',
        'targetId': 't2',
        'mergeTips': true,
        'mergeLogon': true,
        'dryRun': true,
      });
      expect(request.toJson(), {
        'originalId': 't1',
        'targetId': 't2',
        'mergeTips': true,
        'mergeLogon': true,
        'dryRun': true,
      });
    });

    test('rejects a missing tipper or an option that is not true or false', () {
      expect(
        () => AdminMergeTippersRequest.fromJson({'originalId': 't1'}),
        throwsFormatException,
      );
      expect(
        () => AdminMergeTippersRequest.fromJson({
          'originalId': 't1',
          'targetId': 't2',
          'mergeTips': 'yes',
        }),
        throwsFormatException,
      );
    });

    test('the result carries the counts and what moved', () {
      final result = AdminMergeTippersResult.fromJson({
        'targetId': 't2',
        'tipsMoved': 12,
        'tipsReplaced': 2,
        'loginMoved': true,
        'accountMoved': false,
        'dryRun': false,
      });
      expect(result.tipsMoved, 12);
      expect(result.tipsReplaced, 2);
      expect(result.toJson()['accountMoved'], false);
      expect(
        () => AdminMergeTippersResult.fromJson({
          'targetId': 't2',
          'tipsMoved': '12',
        }),
        throwsFormatException,
      );
    });
  });
}
