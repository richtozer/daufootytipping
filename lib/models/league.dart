export 'package:dau_shared/models/league.dart';

import 'package:flutter/material.dart';
import 'package:dau_shared/models/league.dart';

extension LeagueColour on League {
  Color get colour {
    switch (this) {
      case League.nrl:
        return const Color(0xff04cf5d);
      case League.afl:
        return const Color(0xffe21e31);
    }
  }

  /// The row shading tables use to mark what matters for this league: a
  /// ladder's top band, a win, a correct tip. AFL tables shade in AFL red,
  /// NRL tables in green.
  Color rowShading({required bool isDarkMode}) {
    switch (this) {
      case League.nrl:
        return isDarkMode
            ? Colors.lightGreen.shade900
            : Colors.lightGreen.shade200;
      case League.afl:
        return isDarkMode ? const Color(0xFF5C1A1A) : Colors.red.shade100;
    }
  }
}
