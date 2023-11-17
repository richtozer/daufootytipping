import 'package:daufootytipping/classes/database_services.dart';
import 'package:daufootytipping/classes/footytipping_model.dart';
import 'package:daufootytipping/classes/dau.dart';
import 'package:daufootytipping/pages/admin_tippers.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  //createRecord();

  runApp(const MyApp());
}

Future<void> createRecord() async {
  DAUComp dc =
      DAUComp('999', '2030', Uri(path: 'test://'), Uri(path: 'test2://'));
  DatabaseService ds = DatabaseService();
  ds.addDAUComp(dc);

  Tipper tp = Tipper(
      authuid: DateTime.now().millisecondsSinceEpoch.toString(),
      email: 'testing@test.com',
      name: 'first last',
      active: true,
      tipperRole: TipperRole.tipper);

  ds.addTipper(tp);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
        create: (context) => FootyTippingModel(),
        builder: (context, provider) {
          return MaterialApp(
            title: 'State Example',
            theme: ThemeData(
              primarySwatch: Colors.blue,
            ),
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.light,
            home: const TippersAdminPage(),
          );
        });
  }
}
