import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';

import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  static const String route = '/';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0; // default to tips page

  @override
  void initState() {
    super.initState();
  }

  final admin = false;

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> content() {
      return [
        const TipsList(),
        const Center(
          child: Text("Comp Stats Page"),
        ),
        const Profile(),
      ];
    }

    List<Widget> destinationContent = content();

    return Consumer<TippersViewModel>(
        builder: (context, tipperViewModel, child) {
      return Scaffold(
          body: Center(
            child: (destinationContent[_currentIndex]),
          ),
          bottomNavigationBar: NavigationBar(
            onDestinationSelected: (int index) {
              onTabTapped(index);
            },
            selectedIndex: _currentIndex,
            destinations: [
              NavigationDestination(
                enabled: tipperViewModel.currentTipperIndex == -1
                    ? false
                    : tipperViewModel
                        .tippers[tipperViewModel.currentTipperIndex].active,
                icon: const Icon(Icons.sports_rugby),
                label: 'T  I  P  S',
              ),
              NavigationDestination(
                enabled: tipperViewModel.currentTipperIndex == -1
                    ? false
                    : tipperViewModel
                        .tippers[tipperViewModel.currentTipperIndex].active,
                icon: const Icon(Icons.auto_graph),
                label: 'S  T  A  T  S',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person),
                label: 'P  R  O  F  I  L  E',
              ),
            ],
          ));
    });
  }
}
