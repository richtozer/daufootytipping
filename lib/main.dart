import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers_add/admin_tippers_add.dart';
import 'package:daufootytipping/pages/admin_tippers_edit/admin_tippers_edit.dart';
import 'package:daufootytipping/pages/auth/user_auth.dart';
import 'package:daufootytipping/pages/auth/user_auth_model.dart';
import 'package:daufootytipping/pages/home/user_home.dart';
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
  const String initialRoute = TippersAdminPage.route;

  runApp(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthViewModel>(
          create: (BuildContext context) => AuthViewModel(),
        ),
        ChangeNotifierProvider<TippersViewModel>(
          create: (BuildContext context) => TippersViewModel(),
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
      ),
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
                    //TippersAdminPage(viewModel),
                    const TippersAdminPage(),
              ),
            );

          case TipperAdminEditPage.route:
            final Tipper tipper = settings.arguments as Tipper;
            return MaterialPageRoute(
              builder: (_) => Consumer<TippersViewModel>(
                builder: (_, TippersViewModel viewModel, __) =>
                    TipperAdminEditPage(viewModel, tipper),
              ),
            );

          case TipperAdminAddPage.route:
            return MaterialPageRoute(
              builder: (_) => Consumer<TippersViewModel>(
                builder: (_, TippersViewModel viewModel, __) =>
                    const TipperAdminAddPage(),
              ),
            );
        }
        return null;
      },
    );
  }
}
