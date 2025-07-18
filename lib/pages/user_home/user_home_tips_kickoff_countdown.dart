import 'dart:async';
import 'package:flutter/material.dart';

class KickoffCountdown extends StatefulWidget {
  final DateTime kickoffDate;

  const KickoffCountdown({super.key, required this.kickoffDate});

  @override
  KickoffCountdownState createState() => KickoffCountdownState();
}

class KickoffCountdownState extends State<KickoffCountdown> {
  late Timer _timer;
  String countdownText = '';

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    final now = DateTime.now();
    final difference = widget.kickoffDate.difference(now);

    setState(() {
      if (difference.inDays > 0) {
        countdownText = 'Kickoff: ${difference.inDays} days';
      } else if (difference.inHours > 0) {
        countdownText = 'Kickoff: ${difference.inHours} hours';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      countdownText,
      softWrap: false,
      style: TextStyle(
        color: countdownText.contains('days') ? Colors.white70 : Colors.orange,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
