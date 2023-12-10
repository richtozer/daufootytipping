import 'package:daufootytipping/locator.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Do not to start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized(); //TODO remove hardcoding

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const String currentDAUComp = '-Nk88l-ww9pYF1j_jUq7'; //TODO remove hardcoding
  setupLocator(currentDAUComp);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAU Footy Tipping',
      theme: ThemeData(
        primaryColor: Colors.green[800],
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const UserAuthPage(),
    );
  }
}
