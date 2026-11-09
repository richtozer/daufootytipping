import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDatabaseReference extends Mock implements DatabaseReference {}

class _FakeSnapshot extends Fake implements DataSnapshot {
  _FakeSnapshot(this.value);

  @override
  final Object? value;

  @override
  bool get exists => value != null;
}

class _FakeEvent extends Fake implements DatabaseEvent {
  _FakeEvent(Object? value) : snapshot = _FakeSnapshot(value);

  @override
  final DataSnapshot snapshot;
}

/// A database that records which paths were listened to and lets a test push
/// the private records.
class _FakeDatabase {
  _FakeDatabase() {
    when(() => root.child(any())).thenAnswer((invocation) {
      final path = invocation.positionalArguments.first as String;
      requestedPaths.add(path);
      final ref = _MockDatabaseReference();
      when(() => ref.onValue).thenAnswer((_) => privateRecords.stream);
      return ref;
    });
  }

  final root = _MockDatabaseReference();
  final requestedPaths = <String>[];
  final privateRecords = StreamController<DatabaseEvent>.broadcast();

  Future<void> emitPrivate(Object? value) async {
    privateRecords.add(_FakeEvent(value));
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeDatabase database;
  late TippersViewModel viewModel;

  Tipper publicTipper(String key, String name) => Tipper(
    dbkey: key,
    compsPaidFor: const [],
    authuid: '',
    email: null,
    name: name,
    tipperRole: TipperRole.tipper,
  );

  Tipper signedIn(TipperRole role) => Tipper(
    dbkey: 'admin-1',
    compsPaidFor: const [],
    authuid: 'uid-admin',
    email: 'admin@example.test',
    logon: 'admin@example.test',
    name: 'Admin',
    tipperRole: role,
  );

  Map<String, Object?> privateRecord({
    String? role,
    String? email,
    String? logon,
    String? loggedOn,
  }) => <String, Object?>{
    'authuid': 'uid-x',
    'tipperRole': ?role,
    'email': ?email,
    'logon': ?logon,
    'acctLoggedOnUTC': ?loggedOn,
  };

  setUp(() {
    database = _FakeDatabase();
    viewModel = TippersViewModel(
      false,
      skipInit: true,
      database: database.root,
      signedIn: () => Stream<bool>.value(true),
    );
    addTearDown(() {
      viewModel.dispose();
      database.privateRecords.close();
    });
  });

  Future<void> signInAs(TipperRole role) async {
    viewModel.applyTippersSnapshotForTest([
      publicTipper('t-alice', 'Alice'),
      publicTipper('t-bob', 'Bob'),
      publicTipper('t-cara', 'Cara'),
    ]);
    viewModel.setLinkedTippersForTest(signedIn(role));
    viewModel.syncAdminPrivateListenerForTest();
    // The listener opens once the sign-in event has been delivered.
    await Future<void>.delayed(Duration.zero);
  }

  group('an administrator reads every private record', () {
    test(
      'and the list carries each tipper\'s login, email, role and last login',
      () async {
        await signInAs(TipperRole.admin);
        await database.emitPrivate(<String, Object?>{
          't-alice': privateRecord(
            role: 'admin',
            email: 'alice@example.test',
            logon: 'alice-login@example.test',
            loggedOn: '2026-08-01 10:00:00.000Z',
          ),
          't-bob': privateRecord(email: 'bob@example.test'),
        });

        final alice = viewModel.tippers.firstWhere((t) => t.dbkey == 't-alice');
        expect(alice.tipperRole, TipperRole.admin);
        expect(alice.email, 'alice@example.test');
        expect(alice.logon, 'alice-login@example.test');
        expect(alice.acctLoggedOnUTC, DateTime.utc(2026, 8, 1, 10));
        expect(alice.name, 'Alice');
        final bob = viewModel.tippers.firstWhere((t) => t.dbkey == 't-bob');
        expect(bob.email, 'bob@example.test');
        expect(bob.tipperRole, TipperRole.tipper);
      },
    );

    test(
      'a tipper with no private record is left as the public list has it',
      () async {
        await signInAs(TipperRole.admin);
        await database.emitPrivate(<String, Object?>{
          't-alice': privateRecord(email: 'alice@example.test'),
        });

        final cara = viewModel.tippers.firstWhere((t) => t.dbkey == 't-cara');
        expect(cara.email, isNull);
        expect(cara.name, 'Cara');
      },
    );

    test('the most recent login comes first', () async {
      await signInAs(TipperRole.admin);
      await database.emitPrivate(<String, Object?>{
        't-alice': privateRecord(loggedOn: '2026-01-01 00:00:00.000Z'),
        't-bob': privateRecord(loggedOn: '2026-09-01 00:00:00.000Z'),
        't-cara': privateRecord(loggedOn: '2026-05-01 00:00:00.000Z'),
      });

      expect(viewModel.tippers.map((t) => t.dbkey), [
        't-bob',
        't-cara',
        't-alice',
      ]);
    });

    test(
      'an unreadable record is skipped and the others still arrive',
      () async {
        await signInAs(TipperRole.admin);
        await database.emitPrivate(<String, Object?>{
          't-alice': privateRecord(role: 'not-a-role'),
          't-bob': privateRecord(email: 'bob@example.test'),
        });

        final alice = viewModel.tippers.firstWhere((t) => t.dbkey == 't-alice');
        expect(alice.email, isNull);
        final bob = viewModel.tippers.firstWhere((t) => t.dbkey == 't-bob');
        expect(bob.email, 'bob@example.test');
      },
    );

    test('listens only at the private records node, once', () async {
      await signInAs(TipperRole.admin);
      viewModel.syncAdminPrivateListenerForTest();
      await database.emitPrivate(null);

      expect(database.requestedPaths, [p.tipperPrivatePath]);
    });
  });

  group('anyone else', () {
    test('never reads the private records', () async {
      await signInAs(TipperRole.tipper);
      await database.emitPrivate(<String, Object?>{
        't-alice': privateRecord(email: 'alice@example.test'),
      });

      expect(database.requestedPaths, isEmpty);
      final alice = viewModel.tippers.firstWhere((t) => t.dbkey == 't-alice');
      expect(alice.email, isNull);
    });

    test('a guest never reads them, whatever role it carries', () async {
      viewModel.applyTippersSnapshotForTest([publicTipper('t-alice', 'Alice')]);
      viewModel.setLinkedTippersForTest(
        Tipper(
          dbkey: 'guest',
          compsPaidFor: const [],
          authuid: 'uid-guest',
          email: null,
          name: 'Guest',
          tipperRole: TipperRole.admin,
          isAnonymous: true,
        ),
      );
      viewModel.syncAdminPrivateListenerForTest();
      await Future<void>.delayed(Duration.zero);

      expect(database.requestedPaths, isEmpty);
    });

    test('what an administrator read is dropped once the signed-in tipper is not one', () async {
      await signInAs(TipperRole.admin);
      await database.emitPrivate(<String, Object?>{
        't-alice': privateRecord(email: 'alice@example.test'),
      });
      expect(
        viewModel.tippers.firstWhere((t) => t.dbkey == 't-alice').email,
        'alice@example.test',
      );

      viewModel.setLinkedTippersForTest(signedIn(TipperRole.tipper));
      viewModel.syncAdminPrivateListenerForTest();

      expect(
        viewModel.tippers.firstWhere((t) => t.dbkey == 't-alice').email,
        isNull,
      );
      await Future<void>.delayed(Duration.zero);
      expect(database.privateRecords.hasListener, isFalse);
    });
  });
}
