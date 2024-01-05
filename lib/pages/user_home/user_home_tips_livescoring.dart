import 'package:flutter/material.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.scoreboard),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('home team score: 0'),
              Text(
                'away team score: 0',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
