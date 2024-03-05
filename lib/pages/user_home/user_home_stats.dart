import 'package:daufootytipping/pages/user_home/user_home_stats_leaderboard.dart';
import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  final String currentCompDbKey;

  const StatsPage(this.currentCompDbKey, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/teams/daulogo.jpg',
                    fit: BoxFit.fitWidth,
                  ),
                ),
                ListTile(
                  title: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                          style: TextStyle(fontWeight: FontWeight.bold),
                          'DAU Footy Tipping Stats')),
                  trailing: const Icon(
                    (Icons.auto_awesome),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.onetwothree),
                    trailing: const Icon(Icons.arrow_forward),
                    title: const Text('Comp Leaderboard'),
                    onTap: () {
                      // Navigate to the comp leaderboard
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const StatLeaderboard()),
                      );
                    },
                  ),
                  const ListTile(
                    leading: Icon(Icons.person_3),
                    trailing: Icon(Icons.snooze_rounded),
                    title: Text('Round winners (coming soon)'),
                    // onTap: () {
                    //   // Navigate to the round winners
                    //   Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (context) => StatRoundWinners()),
                    //   );
                    // },
                  ),
                  const ListTile(
                    leading: Icon(Icons.pie_chart),
                    trailing: Icon(Icons.snooze_rounded),
                    title: Text('More stats (coming soon)'),
                    // onTap: () {
                    //   // Navigate to the round winners
                    //   Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (context) => StatRoundWinners()),
                    //   );
                    // },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  //@override
  Widget build2(BuildContext context) {
    // home page for all stats
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
      ),
      body: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Stats'),
          StatLeaderboard(),
        ],
      ),
    );
  }
}
