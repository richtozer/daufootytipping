import 'package:dart_functions/identity/restore_public.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

/// A private record as the callables write it.
Map<String, Object?> privateOf(
  String uid, {
  String role = 'tipper',
  String email = 'x@example.test',
}) => <String, Object?>{
  'authuid': uid,
  'tipperRole': role,
  'email': email,
  'logon': email,
  'isAnonymous': false,
  'acctCreatedUTC': '2026-03-01 04:05:06.000Z',
  'acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
};

void main() {
  group('planPublicIdentityRestore', () {
    test('brings every purged field back, and only those', () {
      final plan = planPublicIdentityRestore(
        tippers: <String, Object?>{
          't1': <String, Object?>{'name': 'Alice', 'photoURL': 'a.png'},
        },
        tipperPrivate: <String, Object?>{'t1': privateOf('uidA')},
      );
      expect(plan.isBlocked, false);
      expect(plan.recordsToRestore, 1);
      expect(plan.patch, <String, Object?>{
        'AllTippers/t1/authuid': 'uidA',
        'AllTippers/t1/tipperRole': 'tipper',
        'AllTippers/t1/email': 'x@example.test',
        'AllTippers/t1/logon': 'x@example.test',
        'AllTippers/t1/isAnonymous': false,
        'AllTippers/t1/acctCreatedUTC': '2026-03-01 04:05:06.000Z',
        'AllTippers/t1/acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
      });
      expect(plan.fieldsToRestore, 7);
    });

    test('never overwrites a field the public record already has', () {
      final plan = planPublicIdentityRestore(
        tippers: <String, Object?>{
          't1': <String, Object?>{
            'name': 'Alice',
            'authuid': 'uidA',
            'tipperRole': 'tipper',
            'email': 'newer@example.test',
            'isAnonymous': false,
          },
        },
        tipperPrivate: <String, Object?>{'t1': privateOf('uidA')},
      );
      expect(plan.patch.keys, [
        'AllTippers/t1/logon',
        'AllTippers/t1/acctCreatedUTC',
        'AllTippers/t1/acctLoggedOnUTC',
      ]);
      expect(
        plan.differing,
        1,
        reason: 'the email differs and the public one stays',
      );
    });

    test(
      'a record that is already whole plans nothing, and so does running it twice',
      () {
        final tippers = <String, Object?>{
          't1': <String, Object?>{'name': 'Alice'},
          't2': <String, Object?>{'name': 'Bob'},
        };
        final private = <String, Object?>{
          't1': privateOf('uidA'),
          't2': privateOf('uidB', role: 'admin'),
        };
        final first = planPublicIdentityRestore(
          tippers: tippers,
          tipperPrivate: private,
        );
        expect(first.recordsToRestore, 2);
        // Apply it to the data, as the database would.
        for (final entry in first.patch.entries) {
          final parts = entry.key.split('/');
          (tippers[parts[1]]! as Map<String, Object?>)[parts[2]] = entry.value;
        }
        final second = planPublicIdentityRestore(
          tippers: tippers,
          tipperPrivate: private,
        );
        expect(second.isEmpty, true);
        expect(second.isBlocked, false);
        expect(second.recordsToRestore, 0);
      },
    );

    test(
      'an unlinked tipper gets the legacy "no account" value, an empty authuid',
      () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            't1': <String, Object?>{'name': 'Alice'},
          },
          tipperPrivate: <String, Object?>{
            't1': <String, Object?>{
              'tipperRole': 'tipper',
              'logon': 'a@example.test',
            },
          },
        );
        expect(plan.isBlocked, false);
        expect(plan.patch['AllTippers/t1/authuid'], '');
        expect(plan.patch['AllTippers/t1/tipperRole'], 'tipper');
      },
    );

    test(
      'a public record that already says authuid is not given an empty one',
      () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            't1': <String, Object?>{
              'name': 'A',
              'authuid': 'uidA',
              'tipperRole': 'tipper',
            },
          },
          tipperPrivate: <String, Object?>{
            't1': <String, Object?>{'tipperRole': 'tipper'},
          },
        );
        expect(plan.isEmpty, true);
      },
    );

    test(
      'the legacy fields are not brought back, and are not in the patch',
      () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            't1': <String, Object?>{'name': 'Alice'},
          },
          tipperPrivate: <String, Object?>{
            't1': <String, Object?>{
              ...privateOf('uidA'),
              'active': true,
              'tipperID': 'old',
            },
          },
        );
        for (final legacy in tipperLegacyFieldNames) {
          expect(plan.patch.keys.where((k) => k.endsWith('/$legacy')), isEmpty);
        }
      },
    );

    group('blocks, writing nothing, when a tipper cannot be restored', () {
      test(
        'a private record with no public one (the tipper would be missing)',
        () {
          final plan = planPublicIdentityRestore(
            tippers: <String, Object?>{
              't1': <String, Object?>{'name': 'Alice'},
            },
            tipperPrivate: <String, Object?>{
              't1': privateOf('uidA'),
              'tGone': privateOf('uidG'),
            },
          );
          expect(plan.isBlocked, true);
          expect(plan.blocking.single.tipperId, 'tGone');
          expect(plan.blocking.single.problem, contains('no public one'));
        },
      );

      test('a record with no tipperRole anywhere', () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            't1': <String, Object?>{'name': 'Alice'},
          },
          tipperPrivate: <String, Object?>{
            't1': <String, Object?>{
              'authuid': 'uidA',
              'email': 'a@example.test',
            },
          },
        );
        expect(plan.isBlocked, true);
        expect(plan.blocking.single.problem, contains('tipperRole'));
      });

      test('the findings name only the opaque id', () {
        final plan = planPublicIdentityRestore(
          tippers: const <String, Object?>{},
          tipperPrivate: <String, Object?>{
            't1': privateOf('uidA', email: 'secret@example.test'),
          },
        );
        expect('${plan.blocking.single}', isNot(contains('secret')));
        expect('${plan.blocking.single}', isNot(contains('uidA')));
      });
    });

    test('counts the purge\'s placeholder names and leaves them alone', () {
      final plan = planPublicIdentityRestore(
        tippers: <String, Object?>{
          'tNoName0123456': <String, Object?>{
            'name': placeholderTipperName('tNoName0123456'),
          },
          't2': <String, Object?>{'name': 'Bob'},
        },
        tipperPrivate: <String, Object?>{
          'tNoName0123456': privateOf('uidN'),
          't2': privateOf('uidB'),
        },
      );
      expect(plan.placeholderNames, 1);
      expect(plan.patch.keys.where((k) => k.endsWith('/name')), isEmpty);
    });

    group('a public record with no private copy', () {
      test('that lacks what the legacy shape requires blocks the restore', () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            't1': <String, Object?>{'name': 'Alice'},
            't2': <String, Object?>{'name': 'Bob'},
          },
          tipperPrivate: <String, Object?>{'t2': privateOf('uidB')},
        );
        expect(plan.isBlocked, true);
        expect(plan.blocking.single.tipperId, 't1');
        expect(
          plan.blocking.single.problem,
          contains('authuid and tipperRole'),
        );
        expect(plan.blocking.single.problem, contains('no private one'));
      });

      test('names only what is missing', () {
        final plan = planPublicIdentityRestore(
          tippers: <String, Object?>{
            'tNoRole': <String, Object?>{'name': 'A', 'authuid': 'uid'},
            'tNoUid': <String, Object?>{'name': 'B', 'tipperRole': 'tipper'},
          },
          tipperPrivate: const <String, Object?>{},
        );
        final problems = {for (final f in plan.blocking) f.tipperId: f.problem};
        expect(problems['tNoRole'], contains('tipperRole'));
        expect(problems['tNoRole'], isNot(contains('authuid')));
        expect(problems['tNoUid'], contains('authuid'));
        expect(problems['tNoUid'], isNot(contains('tipperRole')));
      });

      test(
        'that already has both is fine: it was never purged, and nothing is written for it',
        () {
          final plan = planPublicIdentityRestore(
            tippers: <String, Object?>{
              't1': <String, Object?>{
                'name': 'A',
                'authuid': '',
                'tipperRole': 'tipper',
              },
            },
            tipperPrivate: const <String, Object?>{},
          );
          expect(plan.isBlocked, false);
          expect(plan.isEmpty, true);
        },
      );

      test(
        'a private entry that is not a record counts as no private copy',
        () {
          final plan = planPublicIdentityRestore(
            tippers: <String, Object?>{
              't1': <String, Object?>{'name': 'A'},
            },
            tipperPrivate: <String, Object?>{'t1': 'junk'},
          );
          expect(plan.isBlocked, true);
          expect(plan.blocking.single.tipperId, 't1');
        },
      );
    });

    test('is not confused by an empty or missing database, or by junk', () {
      for (final nothing in <Object?>[
        null,
        <String, Object?>{},
        'x',
        3,
        <Object?>[],
      ]) {
        final plan = planPublicIdentityRestore(
          tippers: nothing,
          tipperPrivate: nothing,
        );
        expect(plan.isEmpty, true);
        expect(plan.isBlocked, false);
      }
      final plan = planPublicIdentityRestore(
        tippers: <String, Object?>{
          't1': <String, Object?>{
            'name': 'A',
            'authuid': 'u',
            'tipperRole': 'tipper',
          },
        },
        tipperPrivate: <String, Object?>{'t1': 'not a record', 't2': null},
      );
      expect(plan.isEmpty, true);
      expect(plan.isBlocked, false);
    });

    test('plans in a fixed order, whatever order the database returns', () {
      final tippers = <String, Object?>{
        'tB': <String, Object?>{'name': 'B'},
        'tA': <String, Object?>{'name': 'A'},
      };
      final forward = planPublicIdentityRestore(
        tippers: tippers,
        tipperPrivate: <String, Object?>{
          'tA': privateOf('a'),
          'tB': privateOf('b'),
        },
      );
      final reverse = planPublicIdentityRestore(
        tippers: tippers,
        tipperPrivate: <String, Object?>{
          'tB': privateOf('b'),
          'tA': privateOf('a'),
        },
      );
      expect(forward.patch.keys.toList(), reverse.patch.keys.toList());
      expect(forward.patch.keys.first, startsWith('AllTippers/tA/'));
    });
  });
}
