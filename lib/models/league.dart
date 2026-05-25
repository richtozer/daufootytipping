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
}
