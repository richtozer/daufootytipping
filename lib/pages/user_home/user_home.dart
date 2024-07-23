import 'dart:ui';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';

import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
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
      const TipsTab(),
      const StatsTab(),
      Profile(), // Display profile and settings for the logged on tipper
    ];
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> destinationContent = content();

    Widget scaffold = Stack(children: [
      Column(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            //imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
            child: Image.asset(
              'assets/teams/daulogo-grass.jpg',
              //'assets/teams/grass with scoreboard.png',
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
                  .activeInComp(di<DAUCompsViewModel>().activeDAUComp),
              icon: activeInComp == false
                  ? const Icon(Icons.sports_rugby)
                  : const Icon(Icons.sports_rugby_outlined),
              label: 'T  I  P  S',
            ),
            NavigationDestination(
              enabled: di<TippersViewModel>()
                  .selectedTipper!
                  .activeInComp(di<DAUCompsViewModel>().activeDAUComp),
              icon: activeInComp == false
                  ? const Icon(Icons.auto_graph)
                  : const Icon(Icons.auto_graph_outlined),
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

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: di<DAUCompsViewModel>(),
      child: ChangeNotifierProvider<TippersViewModel>.value(
        value: di<TippersViewModel>(),
        child: Consumer<DAUCompsViewModel>(
            builder: (context, dauCompsViewModelConsumer, child) {
          return Consumer<TippersViewModel>(
              builder: (context, tippersViewModelConsumer, child) {
            activeInComp = tippersViewModelConsumer.selectedTipper!
                .activeInComp(dauCompsViewModelConsumer.activeDAUComp);

            if (dauCompsViewModelConsumer.activeDAUComp == null) {
              _currentIndex = 2; // default to profile page if no comp is active
            }

            if (activeInComp == false) {
              _currentIndex =
                  2; // default to profile page for non-participants for this year
            }
            if (tippersViewModelConsumer.inGodMode) {
              // display a god mode banner
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
            } else if (!dauCompsViewModelConsumer.isSelectedCompActiveComp()) {
              //display a previous comp banner
              // using regex extract a 4 digit year from the comp name,
              // if none is found use the full comp name
              String compYear = dauCompsViewModelConsumer.selectedDAUComp!.name;
              RegExp regExp = RegExp(r'\d{4}');
              Match? match = regExp.firstMatch(compYear);
              if (match != null) {
                compYear = match.group(0)!;
              }

              return Banner(
                  message: compYear,
                  textStyle: const TextStyle(color: Colors.black),
                  location: BannerLocation.bottomStart,
                  color: League.nrl.colour,
                  child: scaffold);
            } else {
              return scaffold;
            }
          });
        }),
      ),
    );
  }
}
