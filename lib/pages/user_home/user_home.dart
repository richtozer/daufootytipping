import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.currentTipper, {super.key});

  final Tipper currentTipper;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  @override
  bool get wantKeepAlive => true;

  int _currentIndex = 0; // default to tips page

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    List<Widget> content() {
      return [
        TipsPage(widget.currentTipper), // Pass currentTipper to TipsPage
        Center(
          child: Text('Comp Stats Page ${widget.currentTipper.name}'),
        ),
        Profile(widget
            .currentTipper), // Display profile and settings for the logged on tipper
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
                enabled: widget.currentTipper.active,
                icon: const Icon(Icons.sports_rugby),
                label: 'T  I  P  S  ${widget.currentTipper.tipperRole.name}',
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
      },
    );
  }
}
