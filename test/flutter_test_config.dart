import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Set to `true` to run the golden tests without comparing pixels.
const String skipGoldenComparisonVariable = 'SKIP_GOLDEN_COMPARISON';

/// Runs before every test file under `test/`.
///
/// The golden images are rendered on the maintainer's Mac. Text rasterises a
/// little differently on every other machine, so on a CI runner each golden
/// differs by a fraction of a percent and fails. With
/// [skipGoldenComparisonVariable] set, a golden test still builds and lays out
/// its screen, and still fails on an exception or an overflow, but its image is
/// not compared. Pixels are checked by `flutter test` on the Mac.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.environment[skipGoldenComparisonVariable] == 'true') {
    goldenFileComparator = _AcceptEveryImage();
  }
  await testMain();
}

class _AcceptEveryImage extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
