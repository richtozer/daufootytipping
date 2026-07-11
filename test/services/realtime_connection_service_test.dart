import 'dart:async';

import 'package:daufootytipping/services/realtime_connection_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  test('starts optimistic until connection state is known', () {
    final connectedRef = MockDatabaseReference();
    final controller = StreamController<DatabaseEvent>();
    when(() => connectedRef.onValue).thenAnswer((_) => controller.stream);

    final service = RealtimeConnectionService(connectedRef: connectedRef);

    expect(service.connectionKnown, isFalse);
    expect(service.isConnected, isTrue);
    expect(service.isOffline, isFalse);

    service.dispose();
    controller.close();
  });

  test('updates offline and online state from info connected events', () async {
    final connectedRef = MockDatabaseReference();
    final controller = StreamController<DatabaseEvent>();
    when(() => connectedRef.onValue).thenAnswer((_) => controller.stream);

    final service = RealtimeConnectionService(connectedRef: connectedRef);
    var notifications = 0;
    service.addListener(() {
      notifications++;
    });

    controller.add(_event(false));
    await Future<void>.delayed(Duration.zero);

    expect(service.connectionKnown, isTrue);
    expect(service.isConnected, isFalse);
    expect(service.isOffline, isTrue);
    expect(notifications, 1);

    controller.add(_event(true));
    await Future<void>.delayed(Duration.zero);

    expect(service.isConnected, isTrue);
    expect(service.isOffline, isFalse);
    expect(notifications, 2);

    service.dispose();
    await controller.close();
  });

  test('offline tip notice is consumed once and resets on reconnect', () async {
    final connectedRef = MockDatabaseReference();
    final controller = StreamController<DatabaseEvent>();
    when(() => connectedRef.onValue).thenAnswer((_) => controller.stream);

    final service = RealtimeConnectionService(connectedRef: connectedRef);

    expect(service.consumeOfflineTipNotice(), isFalse);

    controller.add(_event(false));
    await Future<void>.delayed(Duration.zero);

    expect(service.consumeOfflineTipNotice(), isTrue);
    expect(service.consumeOfflineTipNotice(), isFalse);

    controller.add(_event(true));
    await Future<void>.delayed(Duration.zero);
    expect(service.consumeOfflineTipNotice(), isFalse);

    controller.add(_event(false));
    await Future<void>.delayed(Duration.zero);
    expect(service.consumeOfflineTipNotice(), isTrue);

    service.dispose();
    await controller.close();
  });

  test('server write acknowledgement marks connected and restarts listener', () async {
    final connectedRef = MockDatabaseReference();
    final firstController = StreamController<DatabaseEvent>();
    final secondController = StreamController<DatabaseEvent>();
    var listenCount = 0;
    when(() => connectedRef.onValue).thenAnswer((_) {
      listenCount++;
      return listenCount == 1
          ? firstController.stream
          : secondController.stream;
    });

    final service = RealtimeConnectionService(connectedRef: connectedRef);

    firstController.add(_event(false));
    await Future<void>.delayed(Duration.zero);

    expect(service.isOffline, isTrue);

    service.markServerWriteAcknowledged();

    expect(service.isOffline, isFalse);
    expect(service.isConnected, isTrue);
    expect(listenCount, 2);

    firstController.add(_event(false));
    await Future<void>.delayed(Duration.zero);
    expect(service.isOffline, isFalse);

    secondController.add(_event(false));
    await Future<void>.delayed(Duration.zero);
    expect(service.isOffline, isTrue);

    service.dispose();
    await firstController.close();
    await secondController.close();
  });
}

MockDatabaseEvent _event(Object? value) {
  final event = MockDatabaseEvent();
  final snapshot = _snapshot(value);
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _snapshot(Object? value) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
