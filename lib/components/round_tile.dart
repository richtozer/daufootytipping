import 'package:flutter/material.dart';

class RoundTile extends StatelessWidget {
  const RoundTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text('Your NRL tips'),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Home v Away',
            softWrap: true,
          ),
          Text(
            'Home team by 13+',
            softWrap: true,
          ),
          Text(
            'Home team 1-12',
            softWrap: true,
          ),
          Text(
            'Draw',
            softWrap: true,
          ),
          Text(
            'Away team 1-12',
            softWrap: true,
          ),
          Text(
            'Away team by 13+',
            softWrap: true,
          ),
        ]),
      ],
    );
  }
}
