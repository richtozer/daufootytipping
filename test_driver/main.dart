import 'package:daufootytipping/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

/// Starts the app with the Flutter Driver extension enabled, so tools can find
/// and tap widgets by `Key`, text or semantics label.
///
/// For debug runs only, never a release build:
/// `flutter run -t test_driver/main.dart`.
Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
