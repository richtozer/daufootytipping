import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  final String text;
  final Widget leadingIconAvatar;

  const HeaderWidget(
      {super.key, required this.text, required this.leadingIconAvatar});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(5.0),
                child: leadingIconAvatar,
              ),
              Padding(
                padding: const EdgeInsets.all(5.0),
                child: Text(
                  text,
                  style: const TextStyle(
                      //color: Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
