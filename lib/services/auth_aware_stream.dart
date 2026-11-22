import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';

/// Whether a Firebase user (anonymous included) is signed in, now and on every
/// change of the ID token: sign-in, sign-out and the hourly refresh. The first
/// event is the current state.
Stream<bool> firebaseSignedInStream() =>
    FirebaseAuth.instance.idTokenChanges().map((User? user) => user != null);

/// A stream of events from a database listener that is opened **only while a user
/// is signed in** (DESIGN-database-rules-phase4.md, D10).
///
/// A Realtime Database listener attached before a session exists is cancelled by an
/// auth-required rule and is never re-attached by the SDK, so the data it was for
/// simply never arrives. This opens the listener on the first signed-in event,
/// closes it on sign-out, and opens it again on the next signed-in event.
///
/// If the underlying listener fails (for instance a permission error), the failure
/// is passed to [onSourceError], not to the subscriber, the listener is closed, and
/// it is opened again on the next signed-in event (the next token refresh at the
/// latest). It is never retried on a timer: a refusal by the rules would only repeat.
///
/// The returned stream is single-subscription; cancelling it closes the underlying
/// listener and stops watching the session.
Stream<T> authAwareStream<T>({
  required Stream<bool> Function() signedIn,
  required Stream<T> Function() open,
  void Function(Object error, StackTrace stackTrace)? onSourceError,
}) {
  late final StreamController<T> controller;
  StreamSubscription<bool>? authSubscription;
  StreamSubscription<T>? source;

  Future<void> closeSource() async {
    final current = source;
    source = null;
    await current?.cancel();
  }

  void openSource() {
    try {
      late final StreamSubscription<T> subscription;
      subscription = open().listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) {
          if (identical(source, subscription)) {
            source = null;
          }
          unawaited(subscription.cancel());
          _report(onSourceError, error, stackTrace);
        },
        onDone: () {
          if (identical(source, subscription)) {
            source = null;
          }
        },
      );
      source = subscription;
    } on Object catch (error, stackTrace) {
      source = null;
      _report(onSourceError, error, stackTrace);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      authSubscription = signedIn().listen((bool isSignedIn) {
        if (!isSignedIn) {
          unawaited(closeSource());
        } else if (source == null) {
          openSource();
        }
      });
    },
    onCancel: () async {
      await authSubscription?.cancel();
      authSubscription = null;
      await closeSource();
    },
  );
  return controller.stream;
}

void _report(
  void Function(Object error, StackTrace stackTrace)? onSourceError,
  Object error,
  StackTrace stackTrace,
) {
  if (onSourceError != null) {
    onSourceError(error, stackTrace);
  } else {
    log(
      'A database listener failed and will be reopened on the next sign-in event: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
