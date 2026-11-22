import 'dart:async';

import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake upstream listener source: counts how often it is opened and closed, and
/// lets the test push events and errors into whichever listener is open.
class _Source {
  int opened = 0;
  int cancelled = 0;
  StreamController<int>? current;
  bool failToOpen = false;

  Stream<int> open() {
    if (failToOpen) {
      throw StateError('cannot open');
    }
    opened += 1;
    final controller = StreamController<int>(
      onCancel: () {
        cancelled += 1;
      },
    );
    current = controller;
    return controller.stream;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<bool> auth;
  late _Source source;
  late List<Object> reported;
  late List<int> received;
  late List<Object> receivedErrors;
  StreamSubscription<int>? subscription;

  Stream<int> make() => authAwareStream<int>(
    signedIn: () => auth.stream,
    open: source.open,
    onSourceError: (Object error, StackTrace _) => reported.add(error),
  );

  void listen(Stream<int> stream) {
    subscription = stream.listen(received.add, onError: receivedErrors.add);
  }

  setUp(() {
    auth = StreamController<bool>();
    source = _Source();
    reported = <Object>[];
    received = <int>[];
    receivedErrors = <Object>[];
  });

  tearDown(() async {
    await subscription?.cancel();
    await auth.close();
  });

  test(
    'nothing is opened before a user is signed in, however long it waits',
    () async {
      listen(make());
      await settle();
      expect(source.opened, 0);
      auth.add(false);
      await settle();
      expect(source.opened, 0);
    },
  );

  test(
    'it opens when a user signs in, and forwards what the listener delivers',
    () async {
      listen(make());
      auth.add(false);
      auth.add(true);
      await settle();
      expect(source.opened, 1);
      source.current!.add(1);
      source.current!.add(2);
      await settle();
      expect(received, [1, 2]);
    },
  );

  test('a user already signed in when it starts opens it at once', () async {
    listen(make());
    auth.add(true);
    await settle();
    expect(source.opened, 1);
  });

  test('a token refresh while it is healthy does not open it again', () async {
    listen(make());
    auth.add(true);
    await settle();
    auth.add(true);
    auth.add(true);
    await settle();
    expect(source.opened, 1);
    expect(source.cancelled, 0);
  });

  test('signing out closes it, and signing in again opens it again', () async {
    listen(make());
    auth.add(true);
    await settle();
    auth.add(false);
    await settle();
    expect(source.cancelled, 1);
    source.current!.add(
      99,
    ); // a late event from the closed listener is not delivered
    await settle();
    expect(received, isEmpty);
    auth.add(true);
    await settle();
    expect(source.opened, 2);
    source.current!.add(7);
    await settle();
    expect(received, [7]);
  });

  test('a failure of the listener is reported, not delivered, and it reopens on the next sign-in event', () async {
    listen(make());
    auth.add(true);
    await settle();
    source.current!.addError(StateError('permission-denied'));
    await settle();
    expect(reported, hasLength(1));
    expect(
      receivedErrors,
      isEmpty,
      reason: 'the subscriber never sees the error',
    );
    expect(source.cancelled, 1, reason: 'the failed listener is closed');
    expect(source.opened, 1, reason: 'and not reopened on a timer');

    auth.add(true); // the next token refresh
    await settle();
    expect(source.opened, 2);
    source.current!.add(5);
    await settle();
    expect(received, [5]);
  });

  test('a listener that cannot even be opened is reported and tried again on the next sign-in event', () async {
    listen(make());
    source.failToOpen = true;
    auth.add(true);
    await settle();
    expect(reported, hasLength(1));
    expect(source.opened, 0);
    source.failToOpen = false;
    auth.add(true);
    await settle();
    expect(source.opened, 1);
  });

  test('a listener that finishes can be opened again', () async {
    listen(make());
    auth.add(true);
    await settle();
    await source.current!.close();
    await settle();
    auth.add(true);
    await settle();
    expect(source.opened, 2);
  });

  test(
    'cancelling the stream closes the listener and stops watching the session',
    () async {
      listen(make());
      auth.add(true);
      await settle();
      await subscription!.cancel();
      subscription = null;
      expect(source.cancelled, 1);
      expect(auth.hasListener, false);
      auth.add(true);
      await settle();
      expect(
        source.opened,
        1,
        reason: 'a sign-in after cancelling opens nothing',
      );
    },
  );

  test('cancelling before anyone signed in leaves nothing behind', () async {
    listen(make());
    await settle();
    await subscription!.cancel();
    subscription = null;
    expect(auth.hasListener, false);
    expect(source.opened, 0);
  });

  test('without a callback a failure is logged and survived', () async {
    final stream = authAwareStream<int>(
      signedIn: () => auth.stream,
      open: source.open,
    );
    subscription = stream.listen(received.add);
    auth.add(true);
    await settle();
    source.current!.addError(StateError('boom'));
    await settle();
    auth.add(true);
    await settle();
    expect(source.opened, 2);
  });
}
