import 'dart:convert';

import 'package:dart_functions/identity/backfill_plan.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:test/test.dart';

import '../support/apply_writes.dart';

const String _adminUid = 'adminUid0000000000000000001';
const String _otherUid = 'otherUid0000000000000000002';
const String _thirdUid = 'thirdUid0000000000000000003';

Map<String, Object?> _tipper({
  String? name,
  String? authuid,
  String? logon,
  String? email,
  bool? isAnonymous,
  String role = 'tipper',
  List<String>? comps,
}) => {
  'name': ?name,
  'authuid': ?authuid,
  'logon': ?logon,
  'email': ?email,
  'isAnonymous': ?isAnonymous,
  'tipperRole': role,
  'acctCreatedUTC': '2025-02-01 03:04:05.000Z',
  'compsParticipatedIn': ?comps,
};

Map<String, AuthUser> _users(List<String> uids) => {
  for (final uid in uids) uid: AuthUser(uid: uid, email: '$uid@example.com'),
};

BackfillInput _input(
  Map<String, Object?> tippers, {
  List<String> accounts = const [_adminUid, _otherUid, _thirdUid],
  Set<String> allowlist = const {_adminUid},
  Map<String, String> approvedLinks = const {},
  Map<String, Object?> extra = const {},
}) => BackfillInput(
  database: {'AllTippers': tippers, ...extra},
  authUsers: _users(accounts),
  adminAllowlist: allowlist,
  approvedLinks: approvedLinks,
);

/// A database with one allowlisted administrator, so tests of other things are
/// not blocked by the admin check.
Map<String, Object?> _withAdmin(Map<String, Object?> others) => {
  'admin': _tipper(
    name: 'The Admin',
    authuid: _adminUid,
    logon: 'admin@example.com',
    role: 'admin',
  ),
  ...others,
};

List<String> _subjects(BackfillPlan plan, FindingKind kind) => [
  for (final finding in plan.findings)
    if (finding.kind == kind) ...finding.subjects,
];

BackfillInput _inputAfter(BackfillInput input, BackfillPlan plan) =>
    BackfillInput(
      database: applyWrites(input.database, plan.writes),
      authUsers: input.authUsers,
      adminAllowlist: input.adminAllowlist,
      approvedLinks: input.approvedLinks,
    );

void main() {
  group('a linked tipper', () {
    final input = _input(
      _withAdmin({
        'pat': _tipper(
          name: 'Pat',
          authuid: _otherUid,
          logon: 'pat@example.com',
          email: 'pat.contact@example.com',
          comps: ['comp-1'],
        ),
      }),
    );
    final plan = planIdentityBackfill(input);

    test('gets a private record that copies the stored fields as they are', () {
      expect(plan.writes['TipperPrivate/pat'], {
        'authuid': _otherUid,
        'tipperRole': 'tipper',
        'email': 'pat.contact@example.com',
        'logon': 'pat@example.com',
        'acctCreatedUTC': '2025-02-01 03:04:05.000Z',
      });
    });

    test('is indexed by account, alias and login email', () {
      expect(plan.writes['AuthIndex/$_otherUid'], 'pat');
      expect(plan.writes['AliasIndex/pat'], 'pat');
      expect(
        plan.writes['LogonIndex/${logonIndexKey('pat@example.com')}'],
        'pat',
      );
    });

    test('changes nothing in the public record and records no placeholder', () {
      expect(
        plan.writes.keys.where((key) => key.startsWith('AllTippers')),
        isEmpty,
      );
      expect(
        plan.writes.keys.where((key) => key.startsWith('Placeholders')),
        isEmpty,
      );
      expect(plan.hasBlockingFindings, false);
    });
  });

  group('a record that is not an account', () {
    test(
      'a placeholder is audited exactly as stored and not indexed by uid',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'old': _tipper(name: 'Old', authuid: 'old.player@example.com'),
            }),
          ),
        );
        expect(plan.writes['Placeholders/old'], 'old.player@example.com');
        expect(
          plan.writes.keys.where((key) => key.startsWith('AuthIndex')).length,
          1,
          reason: 'only the administrator',
        );
        expect(
          (plan.writes['TipperPrivate/old']! as Map)['authuid'],
          'old.player@example.com',
        );
        expect(plan.counts['placeholders'], 1);
      },
    );

    test(
      'a record with no authuid is reported and still gets a private copy',
      () {
        final plan = planIdentityBackfill(
          _input(_withAdmin({'none': _tipper(name: 'None')})),
        );
        expect(_subjects(plan, FindingKind.noAuthuid), ['none']);
        expect(
          (plan.writes['TipperPrivate/none']! as Map).containsKey('authuid'),
          false,
        );
      },
    );

    test('an anonymous record is copied but never indexed', () {
      final plan = planIdentityBackfill(
        _input(
          _withAdmin({
            'anon': _tipper(
              name: 'Guest',
              authuid: _otherUid,
              logon: 'guest@example.com',
              isAnonymous: true,
            ),
          }),
        ),
      );
      expect(plan.writes.containsKey('TipperPrivate/anon'), true);
      expect(plan.writes.containsKey('AuthIndex/$_otherUid'), false);
      expect(plan.writes.containsKey('AliasIndex/guest'), false);
      expect(
        plan.writes.containsKey(
          'LogonIndex/${logonIndexKey('guest@example.com')}',
        ),
        false,
      );
    });
  });

  group('owner-approved links', () {
    test(
      'link a placeholder to the account, in the public and private record',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'pat': _tipper(name: 'Pat', authuid: 'pat@example.com'),
            }),
            approvedLinks: {'pat': _otherUid},
          ),
        );
        expect(plan.writes['AllTippers/pat/authuid'], _otherUid);
        expect(
          (plan.writes['TipperPrivate/pat']! as Map)['authuid'],
          _otherUid,
        );
        expect(plan.writes['AuthIndex/$_otherUid'], 'pat');
        expect(plan.writes.containsKey('Placeholders/pat'), false);
        expect(plan.counts['approvedLinks'], 1);
      },
    );

    test('are rejected for an account that does not exist', () {
      final plan = planIdentityBackfill(
        _input(
          _withAdmin({'pat': _tipper(name: 'Pat', authuid: 'pat@example.com')}),
          approvedLinks: {'pat': 'ghostUid'},
        ),
      );
      expect(_subjects(plan, FindingKind.approvedLinkRejected), ['pat']);
      expect(plan.hasBlockingFindings, true);
      expect(plan.writes.containsKey('AllTippers/pat/authuid'), false);
    });

    test(
      'are rejected when the record already holds a different real account',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({'pat': _tipper(name: 'Pat', authuid: _otherUid)}),
            approvedLinks: {'pat': _thirdUid},
          ),
        );
        expect(_subjects(plan, FindingKind.approvedLinkRejected), ['pat']);
        expect(plan.writes.containsKey('AllTippers/pat/authuid'), false);
      },
    );

    test('name a record that must exist', () {
      final plan = planIdentityBackfill(
        _input(_withAdmin({}), approvedLinks: {'nobody': _otherUid}),
      );
      expect(_subjects(plan, FindingKind.approvedLinkUnknownTipper), [
        'nobody',
      ]);
      expect(plan.hasBlockingFindings, true);
    });

    test('that are already in place write nothing public', () {
      final plan = planIdentityBackfill(
        _input(
          _withAdmin({'pat': _tipper(name: 'Pat', authuid: _otherUid)}),
          approvedLinks: {'pat': _otherUid},
        ),
      );
      expect(plan.writes.containsKey('AllTippers/pat/authuid'), false);
      expect(plan.counts['approvedLinks'], 0);
    });
  });

  group('conflicts are reported, never guessed', () {
    test(
      'two records holding one account are both left out of the account index',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'a': _tipper(name: 'A', authuid: _otherUid),
              'b': _tipper(name: 'B', authuid: _otherUid),
            }),
          ),
        );
        expect(_subjects(plan, FindingKind.duplicateAccountUid), ['a,b']);
        expect(plan.writes.containsKey('AuthIndex/$_otherUid'), false);
        expect(plan.writes.containsKey('TipperPrivate/a'), true);
        expect(plan.writes.containsKey('TipperPrivate/b'), true);
      },
    );

    test(
      'a shared alias is claimed by the account with the most tips, the rest listed',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'quiet': _tipper(name: 'Reisy', authuid: _otherUid),
              'busy': _tipper(name: 'R e i s y 🏈', authuid: _thirdUid),
              'placeholder': _tipper(name: 'reisy', authuid: 'old@example.com'),
            }),
            extra: {
              'AppConfig': {'currentDAUComp': 'comp-1'},
              'AllTips': {
                'comp-1': {
                  'busy': {'g1': 1, 'g2': 2, 'g3': 3},
                  'quiet': {'g1': 1},
                },
              },
            },
          ),
        );
        expect(plan.writes['AliasIndex/reisy'], 'busy');
        expect(_subjects(plan, FindingKind.aliasShared), [
          'busy,quiet,placeholder',
        ]);
      },
    );

    test('with equal standing the lowest id wins, whatever the order', () {
      final first = planIdentityBackfill(
        _input(
          _withAdmin({
            'b': _tipper(name: 'Sam', authuid: _otherUid),
            'a': _tipper(name: 'Sam', authuid: _thirdUid),
          }),
        ),
      );
      final second = planIdentityBackfill(
        _input(
          _withAdmin({
            'a': _tipper(name: 'Sam', authuid: _thirdUid),
            'b': _tipper(name: 'Sam', authuid: _otherUid),
          }),
        ),
      );
      expect(first.writes['AliasIndex/sam'], 'a');
      expect(second.writes['AliasIndex/sam'], 'a');
    });

    test(
      'an alias that cannot be an alias is reported, a record with no name is not',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'symbols': _tipper(name: '🏈🏈', authuid: _otherUid),
              'long': _tipper(name: 'x' * 65, authuid: _thirdUid),
              'unnamed': _tipper(authuid: 'unnamed@example.com'),
            }),
          ),
        );
        expect(_subjects(plan, FindingKind.aliasUnusable), ['long', 'symbols']);
        expect(
          plan.writes.keys.where((key) => key.startsWith('AliasIndex')).length,
          1,
          reason: 'only the administrator',
        );
      },
    );

    test(
      'a login email shared by several records is claimed by none of them',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'a': _tipper(
                name: 'A',
                authuid: _otherUid,
                logon: 'Same@Example.com',
              ),
              'b': _tipper(
                name: 'B',
                authuid: 'b@example.com',
                logon: ' same@example.com ',
              ),
              'c': _tipper(
                name: 'C',
                authuid: _thirdUid,
                logon: 'unique@example.com',
              ),
            }),
          ),
        );
        expect(_subjects(plan, FindingKind.logonShared), ['a,b']);
        expect(
          plan.writes.containsKey(
            'LogonIndex/${logonIndexKey('same@example.com')}',
          ),
          false,
        );
        expect(
          plan.writes['LogonIndex/${logonIndexKey('unique@example.com')}'],
          'c',
        );
      },
    );
  });

  group('administrators must match the allowlist both ways', () {
    test('a matching administrator is fine', () {
      expect(
        planIdentityBackfill(_input(_withAdmin({}))).hasBlockingFindings,
        false,
      );
    });

    test(
      'an admin role on an account that is not allowlisted blocks the patch',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'liv': _tipper(name: 'Liv', authuid: _otherUid, role: 'admin'),
            }),
          ),
        );
        expect(_subjects(plan, FindingKind.adminNotOnAllowlist), ['liv']);
        expect(plan.hasBlockingFindings, true);
      },
    );

    test(
      'an admin role on a placeholder or on a shared account blocks the patch',
      () {
        final placeholder = planIdentityBackfill(
          _input(
            _withAdmin({
              'x': _tipper(name: 'X', authuid: 'x@example.com', role: 'admin'),
            }),
          ),
        );
        expect(_subjects(placeholder, FindingKind.adminNotOnAllowlist), ['x']);

        final shared = planIdentityBackfill(
          _input({
            'one': _tipper(name: 'One', authuid: _adminUid, role: 'admin'),
            'two': _tipper(name: 'Two', authuid: _adminUid),
          }),
        );
        expect(_subjects(shared, FindingKind.adminNotOnAllowlist), ['one']);
      },
    );

    test('an allowlisted account with no admin record blocks the patch', () {
      final plan = planIdentityBackfill(
        _input({'pat': _tipper(name: 'Pat', authuid: _otherUid)}),
      );
      expect(_subjects(plan, FindingKind.allowlistedUidWithoutAdminRecord), [
        _adminUid,
      ]);
      expect(plan.hasBlockingFindings, true);
    });

    test(
      'an allowlisted account whose record is only a tipper blocks the patch',
      () {
        final plan = planIdentityBackfill(
          _input({'pat': _tipper(name: 'Pat', authuid: _adminUid)}),
        );
        expect(_subjects(plan, FindingKind.allowlistedUidWithoutAdminRecord), [
          _adminUid,
        ]);
      },
    );
  });

  group('running it again', () {
    final input = _input(
      _withAdmin({
        'pat': _tipper(
          name: 'Pat',
          authuid: _otherUid,
          logon: 'pat@example.com',
        ),
        'old': _tipper(name: 'Old', authuid: 'old@example.com'),
      }),
    );
    final first = planIdentityBackfill(input);

    test(
      'after the patch is applied, finds nothing to do and nothing wrong',
      () {
        final second = planIdentityBackfill(_inputAfter(input, first));
        expect(second.writes, isEmpty);
        expect(second.isClean, true);
        expect(second.counts['alreadyPresent'], first.writes.length);
      },
    );

    test(
      'a renamed tipper gets the new alias, and the old claim is reported stale',
      () {
        final applied = _inputAfter(input, first);
        final tippers = Map<String, Object?>.from(
          applied.database['AllTippers']! as Map,
        );
        tippers['pat'] = {
          ...tippers['pat']! as Map<String, Object?>,
          'name': 'Patricia',
        };
        final drifted = BackfillInput(
          database: {...applied.database, 'AllTippers': tippers},
          authUsers: applied.authUsers,
          adminAllowlist: applied.adminAllowlist,
        );
        final plan = planIdentityBackfill(drifted);
        expect(plan.writes['AliasIndex/patricia'], 'pat');
        expect(_subjects(plan, FindingKind.unexpectedEntry), [
          'AliasIndex/pat',
        ]);
      },
    );

    test(
      'a private record that no longer matches is reported and not overwritten',
      () {
        final applied = _inputAfter(input, first);
        final tippers = Map<String, Object?>.from(
          applied.database['AllTippers']! as Map,
        );
        tippers['pat'] = {
          ...tippers['pat']! as Map<String, Object?>,
          'email': 'changed@example.com',
        };
        final plan = planIdentityBackfill(
          BackfillInput(
            database: {...applied.database, 'AllTippers': tippers},
            authUsers: applied.authUsers,
            adminAllowlist: applied.adminAllowlist,
          ),
        );
        expect(_subjects(plan, FindingKind.existingDiffers), [
          'TipperPrivate/pat',
        ]);
        expect(plan.writes.containsKey('TipperPrivate/pat'), false);
        expect(plan.hasBlockingFindings, true);
      },
    );

    test(
      'a claim that points at another tipper is reported and not overwritten',
      () {
        final applied = _inputAfter(input, first);
        final database = Map<String, Object?>.from(applied.database);
        database['AuthIndex'] = {
          ...database['AuthIndex']! as Map<String, Object?>,
          _otherUid: 'someoneElse',
        };
        final plan = planIdentityBackfill(
          BackfillInput(
            database: database,
            authUsers: applied.authUsers,
            adminAllowlist: applied.adminAllowlist,
          ),
        );
        expect(_subjects(plan, FindingKind.existingDiffers), [
          'AuthIndex/$_otherUid',
        ]);
        expect(plan.writes.containsKey('AuthIndex/$_otherUid'), false);
      },
    );

    test('the entries of a deleted tipper are reported', () {
      final applied = _inputAfter(input, first);
      final tippers = Map<String, Object?>.from(
        applied.database['AllTippers']! as Map,
      )..remove('old');
      final plan = planIdentityBackfill(
        BackfillInput(
          database: {...applied.database, 'AllTippers': tippers},
          authUsers: applied.authUsers,
          adminAllowlist: applied.adminAllowlist,
        ),
      );
      expect(_subjects(plan, FindingKind.unexpectedEntry), [
        'AliasIndex/old',
        'Placeholders/old',
        'TipperPrivate/old',
      ]);
    });

    test('a new tipper is backfilled by the next run', () {
      final applied = _inputAfter(input, first);
      final tippers = Map<String, Object?>.from(
        applied.database['AllTippers']! as Map,
      );
      tippers['fresh'] = _tipper(
        name: 'Fresh',
        authuid: _thirdUid,
        logon: 'fresh@example.com',
      );
      final plan = planIdentityBackfill(
        BackfillInput(
          database: {...applied.database, 'AllTippers': tippers},
          authUsers: applied.authUsers,
          adminAllowlist: applied.adminAllowlist,
        ),
      );
      expect(
        plan.writes.keys,
        containsAll([
          'TipperPrivate/fresh',
          'AuthIndex/$_thirdUid',
          'AliasIndex/fresh',
        ]),
      );
      expect(plan.hasBlockingFindings, false);
    });
  });

  group('the patch', () {
    test(
      'only touches the identity roots, plus the authuid of an approved link',
      () {
        final plan = planIdentityBackfill(
          _input(
            _withAdmin({
              'pat': _tipper(
                name: 'Pat',
                authuid: 'pat@example.com',
                logon: 'pat@example.com',
              ),
              'sam': _tipper(name: 'Sam', authuid: _otherUid),
            }),
            approvedLinks: {'pat': _thirdUid},
          ),
        );
        const roots = {
          'TipperPrivate',
          'AuthIndex',
          'AliasIndex',
          'LogonIndex',
          'Placeholders',
        };
        for (final key in plan.writes.keys) {
          final root = key.split('/').first;
          expect(
            roots.contains(root) ||
                RegExp(r'^AllTippers/[^/]+/authuid$').hasMatch(key),
            true,
            reason: key,
          );
        }
        expect(plan.writes.keys.where((key) => key.startsWith('AllTippers')), [
          'AllTippers/pat/authuid',
        ]);
      },
    );

    test('is byte-identical however the data is ordered', () {
      final tippers = {
        'c': _tipper(name: 'C', authuid: _thirdUid, logon: 'c@example.com'),
        'b': _tipper(name: 'B', authuid: _otherUid, logon: 'b@example.com'),
        'admin': _tipper(name: 'Admin', authuid: _adminUid, role: 'admin'),
      };
      final reversed = {
        for (final key in tippers.keys.toList().reversed) key: tippers[key],
      };
      expect(
        jsonEncode(planIdentityBackfill(_input(tippers)).writes),
        jsonEncode(planIdentityBackfill(_input(reversed)).writes),
      );
    });

    test('every key it writes is a valid database key', () {
      final plan = planIdentityBackfill(
        _input(
          _withAdmin({
            'odd': _tipper(
              name: 'Zoë Ünïcode ΑΣ',
              authuid: _otherUid,
              logon: 'a.b+c@example.com',
            ),
          }),
        ),
      );
      for (final key in plan.writes.keys) {
        for (final segment in key.split('/')) {
          expect(segment.contains(RegExp(r'[.$#\[\]]')), false, reason: key);
        }
      }
    });
  });
}
