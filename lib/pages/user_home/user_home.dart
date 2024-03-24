import 'dart:developer';
import 'dart:ui';

import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.currentDAUCompKey, {super.key});

  final String currentDAUCompKey;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // are they participating in the current comp, if not, they can't see the tips or stats

  int _currentIndex = 0;
  bool activeInComp = false;

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

  @override
  Widget build(BuildContext context) {
    activeInComp = di<TippersViewModel>()
        .selectedTipper!
        .activeInComp(widget.currentDAUCompKey);
    log('screen width: ${MediaQuery.of(context).size.width}');

    if (activeInComp == false) {
      _currentIndex = 2; // default to profile page for non-participants
    }
    List<Widget> destinationContent = content();

    Widget scaffold = Stack(children: [
      Column(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              fit: BoxFit.fill,
            ),
          ),
        ],
      ),
      Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: (destinationContent[_currentIndex]),
        ),
        bottomNavigationBar: NavigationBar(
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          onDestinationSelected: (int index) {
            onTabTapped(index);
          },
          selectedIndex: _currentIndex,
          height: 60,
          destinations: [
            NavigationDestination(
              enabled: di<TippersViewModel>()
                  .selectedTipper!
                  .activeInComp(widget.currentDAUCompKey),
              icon: const Icon(Icons.sports_rugby),
              label: 'T  I  P  S',
            ),
            NavigationDestination(
              enabled: di<TippersViewModel>()
                  .selectedTipper!
                  .activeInComp(widget.currentDAUCompKey),
              icon: Icon(Icons.auto_graph),
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

    return ChangeNotifierProvider<TippersViewModel>.value(
        value: di<TippersViewModel>(),
        child: Consumer<TippersViewModel>(
            builder: (context, tippersViewModelConsumer, child) {
          if (tippersViewModelConsumer.inGodMode) {
            return Banner(
              message: tippersViewModelConsumer.selectedTipper!.name,
              location: BannerLocation.bottomStart,
              color: Colors.red,
              child: Banner(
                message: 'God mode',
                location: BannerLocation.bottomEnd,
                color: Colors.red,
                child: scaffold,
              ),
            );
          } else {
            return scaffold;
          }
        }));
  }
}
