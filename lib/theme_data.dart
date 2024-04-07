import 'package:flutter/material.dart';

final ThemeData myTheme = ThemeData(
  primaryColor: const Color(0xFF335522),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF335522)),
);

//NRL AFL gradients
var nrlAflColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffe21e31)],
  stops: [0.25, 0.75],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

var nrlColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffffffff)],
  stops: [0.05, 0.2],
  begin: Alignment.bottomRight,
  end: Alignment.topLeft,
);
