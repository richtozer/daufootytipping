import 'package:daufootytipping/models/tipper.dart';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.currentTipper, this.currentDAUComp, {super.key});

  final Tipper currentTipper;
  final String currentDAUComp;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0; // default to tips page

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // super.build(context);

    List<Widget> content() {
      return [
        TipsPage(widget.currentTipper,
            widget.currentDAUComp), // Pass currentTipper to TipsPage
        Center(
          child: Text('Comp Stats Page ${widget.currentTipper.name}'),
        ),
        Profile(widget
            .currentTipper), // Display profile and settings for the logged on tipper
      ];
    }

    List<Widget> destinationContent = content();

    return Scaffold(
      //appBar: AppBar(title: const Text('DAU Footy Tipping')),
      backgroundColor: const Color(0xFFE5E5E5),
      body: Center(
        child: (destinationContent[_currentIndex]),
      ),
      bottomNavigationBar: NavigationBar(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0.0),
        ),
        indicatorColor: const Color(0xFF789697),
        onDestinationSelected: (int index) {
          onTabTapped(index);
        },
        selectedIndex: _currentIndex,
        destinations: [
          NavigationDestination(
            enabled: widget.currentTipper.active,
            icon: const Icon(Icons.sports_rugby),
            label: 'T  I  P  S',
          ),
          NavigationDestination(
            enabled: widget.currentTipper.active,
            icon: const Icon(Icons.auto_graph),
            label: 'S  T  A  T  S',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person),
            label: 'P  R  O  F  I  L  E',
          ),
        ],
      ),
    );
  }
}
