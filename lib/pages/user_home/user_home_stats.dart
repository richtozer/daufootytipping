import 'package:daufootytipping/pages/user_home/stat_leaderboard.dart';
import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  final String currentCompDbKey;

  const StatsPage(this.currentCompDbKey, {super.key});

  @override
  Widget build(BuildContext context) {
    return StatLeaderboard();
  }
}
