import 'package:daufootytipping/components/round_tile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final useremail = FirebaseAuth.instance.currentUser?.email;

  // sign user out
  void signUserOut() {
    FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        bottomNavigationBar: BottomAppBar(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.sports_rugby, size: 30),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome, size: 30),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.settings, size: 30),
                onPressed: () {
                  signUserOut();
                },
              ),
            ],
          ),
        ),
        body: Center(
            child: Column(children: [
          Text('LOGGED IN AS: $useremail'),
          const RoundTile(),
        ])));
  }
}
