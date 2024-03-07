import 'dart:developer';
import 'dart:ui';

import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';
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

  List<Widget> content() {
    return [
      TipsPage(),
      StatsPage(widget.currentDAUCompKey),
      Profile(), // Display profile and settings for the logged on tipper
    ];
  }

  bool godMode = di<TippersViewModel>().inGodMode;
  String godModeTipper = di<TippersViewModel>().selectedTipper!.name;

  @override
  Widget build(BuildContext context) {
    log('screen width: ${MediaQuery.of(context).size.width}');
    List<Widget> destinationContent = content();

    Widget scaffold = Stack(children: [
      Column(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
            ),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
            ),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
            ),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
            ),
          ),
        ],
      ),
      Scaffold(
        //backgroundColor: const Color.fromRGBO(152, 164, 141, 1),
        backgroundColor: Colors.transparent,
        body: Center(
          child: (destinationContent[_currentIndex]),
        ),
        bottomNavigationBar: NavigationBar(
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          indicatorColor: const Color.fromRGBO(152, 164, 141, 1),
          onDestinationSelected: (int index) {
            onTabTapped(index);
          },
          selectedIndex: _currentIndex,
          height: 60,
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
      )
    ]);

    return godMode
        ? Banner(
            message: godModeTipper,
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
