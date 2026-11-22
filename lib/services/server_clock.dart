import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';

/// The server's clock, as far as this device can tell: the device's own clock moved
/// by the offset the database reports (`.info/serverTimeOffset`).
///
/// The database rules decide whether a tip is in time by the server's clock, so
/// the app must not decide by a phone whose clock is a minute fast or slow. Until
/// the database has reported an offset (and if it never does) the device's clock is
/// used as it is.
class ServerClock {
  ServerClock(Stream<Duration> offsets) {
    _subscription = offsets.listen(
      (Duration offset) => _offset = offset,
      onError: (Object error, StackTrace stackTrace) {
        log(
          'ServerClock: could not read the server time offset: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  Duration _offset = Duration.zero;
  StreamSubscription<Duration>? _subscription;

  /// How far the server's clock is ahead of this device's (negative if behind).
  Duration get offset => _offset;

  /// The time now, by the server's clock.
  DateTime now() => DateTime.now().add(_offset);

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// The server's clock offset from this device, each time the database reports it.
Stream<Duration> serverTimeOffsets([FirebaseDatabase? database]) {
  return (database ?? configuredRealtimeDatabase)
      .ref('.info/serverTimeOffset')
      .onValue
      .map((DatabaseEvent event) {
        final Object? value = event.snapshot.value;
        return value is num
            ? Duration(milliseconds: value.round())
            : Duration.zero;
      });
}
