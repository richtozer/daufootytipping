import 'dart:ui';

enum League { nrl, afl }

extension LeagueLogo on League {
  String get logo {
    switch (this) {
      case League.nrl:
        return 'assets/teams/nrl.svg';
      case League.afl:
        return 'assets/teams/afl.svg';
    }
  }
}

extension LeagueMargin on League {
  int get margin {
    switch (this) {
      case League.nrl:
        return 13;
      case League.afl:
        return 31;
    }
  }
}

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
