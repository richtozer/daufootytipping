import 'dart:ui';
import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  final String text;
  final Widget leadingIconAvatar;

  const HeaderWidget(
      {super.key, required this.text, required this.leadingIconAvatar});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.fitWidth,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 10,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Row(
                children: [
                  leadingIconAvatar,
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      text,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
