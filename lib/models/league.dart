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
