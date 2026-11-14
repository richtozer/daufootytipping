import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockReference extends Mock implements DatabaseReference {}

class _MockSnapshot extends Mock implements DataSnapshot {}

class _MockEvent extends Mock implements DatabaseEvent {}

DataSnapshot _snapshot(String key, Object? value) {
  final snapshot = _MockSnapshot();
  when(() => snapshot.key).thenReturn(key);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}

DatabaseEvent _event(DataSnapshot snapshot) {
  final event = _MockEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

/// A reference that answers as the iOS SDK did while the app listened on the
/// parent: `get()` gave back the whole parent collection, keyed by the parent,
/// while a listener on the path itself saw the right record.
DatabaseReference _listenedChild({
  required String parentKey,
  required Map<String, Object?> collection,
  required String childKey,
}) {
  final reference = _MockReference();
  when(reference.get).thenAnswer((_) async => _snapshot(parentKey, collection));
  when(
    reference.once,
  ).thenAnswer((_) async => _event(_snapshot(childKey, collection[childKey])));
  return reference;
}

void main() {
  const daisy = <String, Object?>{'authuid': 'uid-daisy', 'name': 'Daisy'};
  const buddy = <String, Object?>{'authuid': 'uid-buddy', 'name': 'Buddy'};
  const collection = <String, Object?>{
    'demo-daisy': daisy,
    'demo-buddy': buddy,
  };

  test('reads the private record itself under a listened collection', () async {
    final reads = DatabaseIdentityReads(
      refFor: (_) => _listenedChild(
        parentKey: 'TipperPrivate',
        collection: collection,
        childKey: 'demo-daisy',
      ),
    );

    expect(await reads.privateRecord('demo-daisy'), daisy);
  });

  test('reads the public record itself under a listened collection', () async {
    final reads = DatabaseIdentityReads(
      refFor: (_) => _listenedChild(
        parentKey: 'Tippers',
        collection: collection,
        childKey: 'demo-daisy',
      ),
    );

    expect(await reads.publicRecord('demo-daisy'), daisy);
  });

  test('refuses a snapshot of another path rather than reading it', () async {
    final reference = _MockReference();
    when(reference.get)
        .thenAnswer((_) async => _snapshot('TipperPrivate', collection));
    when(
      reference.once,
    ).thenAnswer((_) async => _event(_snapshot('TipperPrivate', collection)));
    final reads = DatabaseIdentityReads(refFor: (_) => reference);

    await expectLater(reads.privateRecord('demo-daisy'), throwsStateError);
  });
}
