import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  Widget aboutDialog() {
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

  Flexible adminFunctions() {
    return Flexible(
      child: Column(children: [
        ElevatedButton(
          child: const Text('Admin Tippers'),
          onPressed: () {
            Navigator.of(context).pushNamed(TippersAdminPage.route);
          },
        ),
        ElevatedButton(
          child: const Text('Admin Teams'),
          onPressed: () {
            Navigator.of(context).pushNamed(TeamsListPage.route);
          },
        ),
        ElevatedButton(
          child: const Text('Admin DAU Comps'),
          onPressed: () {
            Navigator.of(context).pushNamed(DAUCompsListPage.route);
          },
        )
      ]),
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
          SliverToBoxAdapter(child: Center(child: aboutDialog())),
          Consumer<TipperViewModel>(
              // fix this is not refreshing UI in realtime, either change to Provider.of or fix - posible fix is to use a builder:
              builder: (_, TipperViewModel viewModel, __) {
            if (viewModel.currentTipper != null &&
                viewModel.currentTipper?.tipperRole == TipperRole.admin) {
              return SliverToBoxAdapter(child: Center(child: adminFunctions()));
            } else {
              // we cannot identify their role at this time, do not display admin functionality
              return const SliverToBoxAdapter(
                  child: Center(child: Text("No Admin Access")));
            }
          })
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
