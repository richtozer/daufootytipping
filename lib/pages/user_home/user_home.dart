import 'package:daufootytipping/pages/admin_home/admin_home.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  static const String route = '/';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

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

  final List<Widget> aboutBoxChildren = <Widget>[
    const SizedBox(height: 24),
    RichText(
      text: const TextSpan(
        children: <TextSpan>[
          TextSpan(
              text: "Flutter is Google's UI toolkit for building beautiful, "
                  'natively compiled applications for mobile, web, and desktop '
                  'from a single codebase. Learn more about Flutter at '),
          TextSpan(text: 'https://flutter.dev'),
          TextSpan(text: '.'),
        ],
      ),
    ),
  ];

  Widget diag() {
    return ElevatedButton(
      child: const Text('About this application'),
      onPressed: () {
        showAboutDialog(
          context: context,
          applicationIcon: const FlutterLogo(),
          applicationName: 'DAU Footy Tipping',
          applicationVersion: 'January 2024',
          applicationLegalese: '\u{a9} 2024 The DAU Footy Tipping Authors',
          children: aboutBoxChildren,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> content() {
      return [
        CustomScrollView(
          slivers: <Widget>[
            SliverFixedExtentList(
              itemExtent: 50.0,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  return Container(
                    alignment: Alignment.center,
                    color: Colors.green[100 * (index % 9)],
                    child: Text('Game $index'),
                  );
                },
              ),
            ),
          ],
        ),
        const Center(
          child: Text("Comp Stats Page"),
        ),
        CustomScrollView(slivers: <Widget>[
          SliverToBoxAdapter(
              child: SizedBox(
                  height: 600,
                  child: ProfileScreen(
                    actions: [
                      DisplayNameChangedAction((context, oldName, newName) {
                        // TODO do something with the new name
                        throw UnimplementedError();
                      }),
                    ],
                  ))),
          SliverToBoxAdapter(child: Center(child: diag())),
          admin
              ? const SliverToBoxAdapter(child: Center(child: AdminHomePage()))
              : const SliverToBoxAdapter(
                  child: Center(child: SizedBox.shrink())),
        ])
      ];
    }

    List<Widget> children = content();

    return Scaffold(
        body: Center(
          child: (children[_currentIndex]),
        ),
        bottomNavigationBar: NavigationBar(
          onDestinationSelected: (int index) {
            onTabTapped(index);
          },
          selectedIndex: _currentIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.sports_rugby),
              label: 'T I P S',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_graph),
              label: 'S T A T S',
            ),
            NavigationDestination(
              icon: Icon(Icons.person),
              label: 'P R O F I L E',
            ),
          ],
        ));
  }
}
