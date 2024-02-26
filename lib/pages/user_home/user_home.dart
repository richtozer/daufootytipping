import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:watch_it/watch_it.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.currentDAUCompKey, {super.key});

  final String currentDAUCompKey;

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
    List<Widget> content() {
      return [
        TipsPage(), // Pass currentTipper to TipsPage
        StatsPage(widget.currentDAUCompKey),
        Profile(), // Display profile and settings for the logged on tipper
      ];
    }

    List<Widget> destinationContent = content();

    bool godMode = di<TippersViewModel>().inGodMode;
    String godModeTipper = di<TippersViewModel>().selectedTipper!.name;

    Widget scaffold = Scaffold(
      //appBar: AppBar(title: const Text('DAU Footy Tipping')),
      backgroundColor: const Color(0xFFE5E5E5),
      body: Center(
        child: (destinationContent[_currentIndex]),
      ),
      bottomNavigationBar: NavigationBar(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        indicatorColor: const Color(0xFF789697),
        onDestinationSelected: (int index) {
          onTabTapped(index);
        },
        selectedIndex: _currentIndex,
        destinations: [
          NavigationDestination(
            enabled: di<TippersViewModel>().selectedTipper!.active,
            icon: const Icon(Icons.sports_rugby),
            label: 'T  I  P  S',
          ),
          NavigationDestination(
            enabled: di<TippersViewModel>().selectedTipper!.active,
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

    return godMode
        ? Banner(
            message: '$godModeTipper',
            location: BannerLocation.bottomStart,
            color: Colors.red,
            child: Banner(
              message: 'God mode',
              location: BannerLocation.bottomEnd,
              color: Colors.red,
              child: scaffold,
            ),
          )
        : scaffold;
  }
}
