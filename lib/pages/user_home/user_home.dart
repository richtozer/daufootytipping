import 'dart:ui';
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
  int _currentIndex = 0;

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  List<Widget> content() {
    return [
      const TipsTab(),
      const StatsTab(),
      Profile(),
    ];
  }

  int _selectDefaultTabIndex(
      DAUCompsViewModel dauCompsViewModel, TippersViewModel tippersViewModel) {
    // if their tipper record was just created, then default to the profile tab so they can set their name
    if (tippersViewModel.authenticatedTipper!.name == null) {
      return 2;
    }
    return _currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> destinationContent = content();

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: di<DAUCompsViewModel>(),
      child: ChangeNotifierProvider<TippersViewModel>.value(
        value: di<TippersViewModel>(),
        child: Consumer<DAUCompsViewModel>(
            builder: (context, dauCompsViewModelConsumer, child) {
          return Consumer<TippersViewModel>(
              builder: (context, tippersViewModelConsumer, child) {
            _currentIndex = _selectDefaultTabIndex(
                dauCompsViewModelConsumer, tippersViewModelConsumer);

            Widget scaffold = Stack(children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Image.asset(
                  'assets/teams/grass with scoreboard.png',
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  fit: BoxFit.fill,
                ),
              ),
              Scaffold(
                backgroundColor:
                    MediaQuery.of(context).platformBrightness != Brightness.dark
                        ? Colors.white54
                        : Colors.black54,
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
                      icon: const Icon(Icons.sports_rugby_outlined),
                      label: 'T  I  P  S',
                    ),
                    NavigationDestination(
                      enabled: true,
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

            if (tippersViewModelConsumer.inGodMode) {
              return Banner(
                message:
                    tippersViewModelConsumer.selectedTipper!.name ?? 'Unknown',
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
                  color: Colors.orange,
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
