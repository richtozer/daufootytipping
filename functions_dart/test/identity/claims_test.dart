import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

/// Something that behaves like [replaceIf]. The contract below is run against
/// the real one and against deliberately loosened copies, to prove the checks
/// would notice a regression.
typedef Replacer =
    Future<ReplaceIfResult> Function(
      RestDatabaseReference ref, {
      required String value,
      String? auditedPlaceholder,
    });

/// The mutant the design is worried about: replaces whatever is there.
Future<ReplaceIfResult> _replaceAnything(
  RestDatabaseReference ref, {
  required String value,
  String? auditedPlaceholder,
}) async {
  Object? previous;
  await ref.atomicUpdate((current) {
    previous = current;
    return value;
  });
  return ReplaceIfResult(holdsValue: true, previous: previous);
}

/// A subtler mutant: replaces any string that merely looks like a placeholder
/// (an email address) instead of only the exact audited one.
Future<ReplaceIfResult> _replaceAnyEmail(
  RestDatabaseReference ref, {
  required String value,
  String? auditedPlaceholder,
}) async {
  Object? previous;
  final result = await ref.atomicUpdate((current) {
    previous = current;
    final looksLikePlaceholder = current is String && current.contains('@');
    return current == null || looksLikePlaceholder ? value : keepCurrentValue;
  });
  return ReplaceIfResult(
    holdsValue: result.applied || result.value == value,
    previous: previous,
  );
}

/// Runs every rule of the placeholder contract and returns the ones broken.
Future<List<String>> _replaceIfViolations(
  RestDatabase database,
  Replacer replace,
) async {
  final broken = <String>[];
  final slot = database.ref('/Contract/authuid');
  Future<void> reset(Object? value) async {
    if (value == null) {
      await slot.remove();
    } else {
      await slot.set(value);
    }
  }

  const placeholder = 'old.sheet@example.com';

  await reset(placeholder);
  var outcome = await replace(
    slot,
    value: 'uidA',
    auditedPlaceholder: placeholder,
  );
  if (!outcome.holdsValue ||
      outcome.previous != placeholder ||
      (await slot.once()).value != 'uidA') {
    broken.add('does not replace the exact audited placeholder');
  }

  await reset('someone.else@example.com');
  outcome = await replace(slot, value: 'uidA', auditedPlaceholder: placeholder);
  if (outcome.holdsValue ||
      (await slot.once()).value != 'someone.else@example.com') {
    broken.add('replaced a value that is not the audited placeholder');
  }

  await reset('uidB');
  outcome = await replace(slot, value: 'uidA', auditedPlaceholder: placeholder);
  if (outcome.holdsValue || (await slot.once()).value != 'uidB') {
    broken.add('replaced a real uid');
  }

  await reset(placeholder);
  outcome = await replace(slot, value: 'uidA');
  if (outcome.holdsValue || (await slot.once()).value != placeholder) {
    broken.add('replaced a placeholder when none was audited');
  }

  await reset(null);
  outcome = await replace(slot, value: 'uidA');
  if (!outcome.holdsValue || outcome.previous != null) {
    broken.add('did not fill an empty location');
  }

  await reset('uidA');
  outcome = await replace(slot, value: 'uidA', auditedPlaceholder: placeholder);
  if (!outcome.holdsValue) {
    broken.add('was not idempotent for the same value');
  }
  return broken;
}

void main() {
  group('identity claims against the emulator', skip: emulatorSkipReason, () {
    late RestDatabase database;

    setUp(() async {
      database = openEmulatorDatabase();
      await clearEmulatorDatabase(database);
    });

    group('claim and release', () {
      test('of 25 racing owners exactly one claims the slot', () async {
        final slot = database.ref('/AuthIndex/uid-1');
        final outcomes = await Future.wait(
          List.generate(25, (index) => claim(slot, 'tipper-$index')),
        );

        expect(
          outcomes.where((outcome) => outcome == ClaimOutcome.claimed),
          hasLength(1),
        );
        expect(
          outcomes.where((outcome) => outcome == ClaimOutcome.heldByOther),
          hasLength(24),
        );
        expect((await slot.once()).value, startsWith('tipper-'));
      });

      test(
        'the same owner can retry and a different owner is refused',
        () async {
          final slot = database.ref('/AliasIndex/bigfan');
          expect(await claim(slot, 'tipper-1'), ClaimOutcome.claimed);
          expect(await claim(slot, 'tipper-1'), ClaimOutcome.alreadyOwned);
          expect(await claim(slot, 'tipper-2'), ClaimOutcome.heldByOther);
          expect((await slot.once()).value, 'tipper-1');
        },
      );

      test('a claim never overwrites a non-string value', () async {
        final slot = database.ref('/AliasIndex/odd');
        await slot.set({'unexpected': true});
        expect(await claim(slot, 'tipper-1'), ClaimOutcome.heldByOther);
        expect((await slot.once()).value, {'unexpected': true});
      });

      test('only the owner can release', () async {
        final slot = database.ref('/LogonIndex/hash');
        await claim(slot, 'tipper-1');

        expect(await release(slot, 'tipper-2'), isFalse);
        expect((await slot.once()).value, 'tipper-1');
        expect(await release(slot, 'tipper-1'), isTrue);
        expect((await slot.once()).value, isNull);
        expect(await release(slot, 'tipper-1'), isFalse);
      });

      test('an empty owner is a programming error, not a claim', () async {
        final slot = database.ref('/AuthIndex/uid-2');
        await expectLater(claim(slot, ''), throwsArgumentError);
        await expectLater(release(slot, ''), throwsArgumentError);
        expect((await slot.once()).value, isNull);
      });
    });

    group('replaceIf', () {
      test('keeps the whole placeholder contract', () async {
        expect(await _replaceIfViolations(database, replaceIf), isEmpty);
      });

      test('the contract catches a replacer that replaces anything', () async {
        final broken = await _replaceIfViolations(database, _replaceAnything);
        expect(broken, contains('replaced a real uid'));
        expect(
          broken,
          contains('replaced a value that is not the audited placeholder'),
        );
      });

      test(
        'the contract catches a replacer that trusts anything email-shaped',
        () async {
          final broken = await _replaceIfViolations(database, _replaceAnyEmail);
          expect(
            broken,
            contains('replaced a value that is not the audited placeholder'),
          );
        },
      );

      test(
        'of 3 uids racing for one audited placeholder exactly one wins',
        () async {
          const placeholder = 'old.sheet@example.com';
          final slot = database.ref('/AllTippers/t1/authuid');
          await slot.set(placeholder);

          final results = await Future.wait(
            ['uidA', 'uidB', 'uidC'].map(
              (uid) =>
                  replaceIf(slot, value: uid, auditedPlaceholder: placeholder),
            ),
          );

          expect(results.where((result) => result.holdsValue), hasLength(1));
          expect(['uidA', 'uidB', 'uidC'], contains((await slot.once()).value));
        },
      );

      test('previous lets a caller restore the placeholder', () async {
        const placeholder = 'old.sheet@example.com';
        final slot = database.ref('/AllTippers/t1/authuid');
        await slot.set(placeholder);

        final result = await replaceIf(
          slot,
          value: 'uidA',
          auditedPlaceholder: placeholder,
        );
        expect(result.previous, placeholder);

        await slot.set(result.previous);
        expect((await slot.once()).value, placeholder);
      });

      test('an empty placeholder or value is a programming error', () async {
        final slot = database.ref('/AllTippers/t1/authuid');
        await expectLater(
          replaceIf(slot, value: 'uidA', auditedPlaceholder: ''),
          throwsArgumentError,
        );
        await expectLater(replaceIf(slot, value: ''), throwsArgumentError);
      });
    });
  });
}
