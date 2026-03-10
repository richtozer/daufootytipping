import 'dart:async';
import 'dart:convert';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  late MockDatabaseReference mockDb;
  late StreamController<DatabaseEvent> controller;
  late MockDatabaseReference mockTeamsRef;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockDb = MockDatabaseReference();
    mockTeamsRef = MockDatabaseReference();
    controller = StreamController<DatabaseEvent>.broadcast();
    when(() => mockDb.child(p.teamsPathRoot)).thenReturn(mockTeamsRef);
    when(() => mockTeamsRef.onValue).thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  test('initial load completes from cached teams', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_teams_v1': jsonEncode(<String, Object?>{
        'broncos': <String, Object?>{
          'name': 'Broncos',
          'league': 'nrl',
          'logoURI': null,
        },
        'swans': <String, Object?>{
          'name': 'Swans',
          'league': 'afl',
          'logoURI': null,
        },
      }),
    });

    final viewModel = TeamsViewModel(db: mockDb);

    await viewModel.initialLoadComplete;

    expect(viewModel.teams, hasLength(2));
    expect(viewModel.findTeam('broncos')?.name, 'Broncos');
    expect(viewModel.groupedTeams['nrl'], isNotEmpty);
    expect(viewModel.groupedTeams['afl'], isNotEmpty);

    viewModel.dispose();
  });

  test('remote snapshot replaces cached teams', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_teams_v1': jsonEncode(<String, Object?>{
        'broncos': <String, Object?>{
          'name': 'Broncos',
          'league': 'nrl',
          'logoURI': null,
        },
      }),
    });

    final viewModel = TeamsViewModel(db: mockDb);
    await viewModel.initialLoadComplete;

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: <String, Object?>{
            'storm': <String, Object?>{
              'name': 'Storm',
              'league': 'nrl',
              'logoURI': null,
            },
          },
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.teams, hasLength(1));
    expect(viewModel.findTeam('storm')?.name, 'Storm');
    expect(viewModel.findTeam('broncos'), isNull);

    viewModel.dispose();
  });
}

MockDatabaseEvent _databaseEvent(DataSnapshot snapshot) {
  final event = MockDatabaseEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _rootSnapshot({
  required bool exists,
  required Object? value,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
