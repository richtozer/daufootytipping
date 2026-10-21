import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/backend_tippers.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/tipper_view.dart';

/// A dry run of the purge on a copy of production data (DESIGN-database-rules-phase4.md, M3b).
///
/// Copy a `firebase database:get /` export to `test/data/production-export.json` (that folder is
/// git-ignored) and run `npm run test:dart` in rules_test. Without the file this test is skipped.
/// The tippers go through the real REST handle into the emulator in three shapes, and the backend
/// must see the same tippers in all of them.
///
/// The purge is modelled as the plan decides it: the private and legacy fields are removed, and a
/// tipper whose record has none of the public fields gets a placeholder name (the database keeps no
/// empty node, so without one the tipper would vanish). The only difference the backend may then see
/// is that placeholder name.
final File _export = File('../test/data/production-export.json');

String? _skipReason() {
  if (emulatorSkipReason != null) {
    return emulatorSkipReason;
  }
  return _export.existsSync()
      ? null
      : 'copy a production export to test/data/production-export.json';
}

Map<String, Object?> _fields(
  Map<Object?, Object?> record,
  List<String> names,
) => {
  for (final name in names)
    if (record.containsKey(name)) name: record[name],
};

/// Which tippers differ and in which fields. Production values are personal data, so a failure
/// names the tipper key and the field, never what it held.
List<String> _differences(
  Map<String, Map<String, Object?>> expected,
  Map<String, Map<String, Object?>> actual,
) {
  final problems = <String>[];
  for (final key in {...expected.keys, ...actual.keys}) {
    final want = expected[key];
    final got = actual[key];
    if (want == null || got == null) {
      problems.add('$key: ${want == null ? 'unexpected' : 'missing'}');
      continue;
    }
    final fields = [
      for (final field in want.keys)
        if ('${want[field]}' != '${got[field]}') field,
    ];
    if (fields.isNotEmpty) {
      problems.add('$key: $fields');
    }
  }
  return problems;
}

void main() {
  group('purge dry run on production data', () {
    late final database = openEmulatorDatabase();
    setUp(() => clearEmulatorDatabase(database));

    Future<Map<String, Map<String, Object?>>> loadAll() async => {
      for (final tipper in await loadBackendTippers(database))
        tipper.dbkey!: tipperView(tipper),
    };

    test(
      'the backend sees the same tippers before, during and after',
      () async {
        final root =
            jsonDecode(_export.readAsStringSync()) as Map<String, dynamic>;
        final records = <String, Map<Object?, Object?>>{
          for (final entry
              in (root['AllTippers'] as Map<String, dynamic>).entries)
            entry.key: Map<Object?, Object?>.from(entry.value as Map),
        };
        expect(records, isNotEmpty);

        await database.ref(tippersPath).set(records);
        final legacy = await loadAll();
        expect(legacy.length, records.length);

        await database.ref(tipperPrivatePath).set({
          for (final entry in records.entries)
            entry.key: _fields(entry.value, tipperPrivateFieldNames),
        });
        expect(
          _differences(legacy, await loadAll()),
          isEmpty,
          reason: 'public and private records together',
        );

        final placeholders = [
          for (final entry in records.entries)
            if (_fields(entry.value, tipperPublicFieldNames).isEmpty) entry.key,
        ];
        final purged = {
          for (final entry in records.entries)
            entry.key: placeholders.contains(entry.key)
                ? {'name': placeholderTipperName(entry.key)}
                : _fields(entry.value, tipperPublicFieldNames),
        };
        await database.ref(tippersPath).set(purged);
        expect(_differences(legacy, await loadAll()).toSet(), {
          for (final key in placeholders) '$key: [name]',
        }, reason: 'public records purged: only a placeholder name may differ');

        final anonymous = legacy.values.where(
          (view) => view['isAnonymous'] == true,
        );
        final paid = legacy.values.where(
          (view) => (view['compsPaidFor']! as List).isNotEmpty,
        );
        // ignore: avoid_print
        print(
          'dry run: ${legacy.length} tippers; the backend saw the same in all '
          'three shapes except ${placeholders.length} given a placeholder name '
          '(${paid.length} with paid comps, ${anonymous.length} anonymous)',
        );
      },
      skip: _skipReason(),
    );
  });
}
