import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_add.dart';
import 'package:daufootytipping/pages/admin_home/admin_home.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_model.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //const String initialRoute = UserAuthPage.route;
  const String initialRoute = AdminHomePage.route;

  runApp(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel(),
        ),
        ChangeNotifierProvider<TippersViewModel>(
          create: (_) => TippersViewModel(),
        ),
        ChangeNotifierProvider<DAUCompsViewModel>(
          create: (_) => DAUCompsViewModel(),
        ),
        ChangeNotifierProvider<TeamsViewModel>(
          create: (_) => TeamsViewModel(),
        ),
      ],
      child: const MyApp(initialRoute),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp(this.initialRoute, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAU Footy Tipping',
      theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          fontFamily: 'Raleway'),
      initialRoute: initialRoute,
      onGenerateRoute: (RouteSettings settings) {
        switch (settings.name) {
          case HomePage.route:
            return MaterialPageRoute(
              builder: (_) => Consumer<AuthViewModel>(
                builder: (_, AuthViewModel viewModel, __) =>
                    //HomePage(viewModel),
                    const HomePage(),
              ),
            );
          case UserAuthPage.route:
            return MaterialPageRoute(
              builder: (_) => Consumer<AuthViewModel>(
                builder: (_, AuthViewModel viewModel, __) =>
                    UserAuthPage(viewModel),
              ),
            );

          case TippersAdminPage.route:
            return MaterialPageRoute(
              builder: (_) => Consumer<TippersViewModel>(
                builder: (_, TippersViewModel viewModel, __) =>
                    const TippersAdminPage(),
              ),
            );

          case TipperAdminEditPage.route:
            final Tipper? tipper = settings.arguments
                as Tipper?; // for adding new Tipper records, arguments will have a nul DAUComp
            return MaterialPageRoute(
              builder: (_) => Consumer<TippersViewModel>(
                builder: (_, TippersViewModel viewModel, __) =>
                    TipperAdminEditPage(tipper),
              ),
            );

          case DAUCompsAdminEditPage.route:
            final DAUComp? daucomp = settings.arguments
                as DAUComp?; // for adding new DAUComp records, arguments will have a nul DAUComp
            return MaterialPageRoute(
              builder: (_) => Consumer2<DAUCompsViewModel, TeamsViewModel>(
                builder: (_, DAUCompsViewModel viewModel,
                        TeamsViewModel viewModel2, __) =>
                    DAUCompsAdminEditPage(daucomp),
              ),
            );

          case DAUCompsListPage.route:
            return MaterialPageRoute(
              builder: (_) => Consumer<DAUCompsViewModel>(
                builder: (_, DAUCompsViewModel viewModel, __) =>
                    const DAUCompsListPage(),
              ),
            );

          case AdminHomePage.route:
            return MaterialPageRoute(
              builder: (_) => const AdminHomePage(),
            );

          case TeamsListPage.route:
            return MaterialPageRoute(
              builder: (_) => const TeamsListPage(),
            );

          case TeamEditPage.route:
            final Team? team = settings.arguments as Team?;
            return MaterialPageRoute(
              builder: (_) => TeamEditPage(team),
            );
        }
        return null;
      },
    );
  }
}
