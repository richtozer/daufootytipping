import 'dart:io';
import 'package:flutter/services.dart';

/// Use the SDK's Roboto rather than the deliberately wide Ahem test font.
Future<void> loadTipsFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final file = File('$root/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf');
    loader.addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
  }
  await loader.load();
}
