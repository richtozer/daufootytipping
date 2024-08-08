Key source code locations:

- /lib/src - Mobile app
- /functions/src - Serverless firebase functions

The main flow of data is:
data updated in view mode e.g fixture, score -> write changes to firebase realtime database -> view model event handler fires -> updates view model state

Link to icon generator:

https://icon.kitchen/i/H4sIAAAAAAAAAz2QTW%2FDIAyG%2F4t3zSHpxzrl2sOuk9bbNE0QG4JGQgSkVVXlv9emaTmAeW2%2FPPgGZ%2BVnStDeAFX8P%2FU0ELRG%2BUQVGHu6TnyFzrtJxQwiHdeYOxLxAUhGzV6SrgsjC2kKMae%2FOFt9haUCbY%2FBh8iZt12nzL7m0iwP4eslrdDSq%2Bq9PuCH5iptv3v1IHCx81SklclGhY7GFerZasoq2pdCdKMV0BwmaJu6guhsz8wS6pBzGB6xJ1PUAvv5NObGTnwbMaZNQ9uGjYu0EamucXeQz6jRMlvbbPcLOwwBZy8j%2FeEExuBQRhMS7xfS8LvcAYr7GUB1AQAA

https://icon.kitchen/i/H4sIAAAAAAAAAz2QTU%2FDMAyG%2F4u57tD1A6be0JC4IjFOCCHnsxFpUyUpaJr637Gzbjkk8eP49Rtf4Bf9ohP0F1AYf06DHjX0Bn3SOzD2dJ4pBOndjDEDo%2BN2p4qk6QClDS6ek06GiUCaQ8zpOy5WnGHdgbDH4EOkzEMr0XQVPc3cSN07CVSWG708f1CyRPeax%2BpJHQRj%2Bz7g1Y%2BL0uuCNoc2onJ62izeSk1Zhb2hUm6ybDuHGfpqB9HZgT6w70gn5BzG691rU2hx%2FnrTpTrJsnvWbZquq2vSLahmdBCyaZEQTpas9W23ksAY1OJ5vJ%2FEVQxO8ZhCov1PC%2Fha%2FwEwOupmgQEAAA%3D%3D

Useful links:

Integrate Firebase Realtime with Google sheets
https://gist.github.com/CodingDoug/44ad12f4836e79ca9fa11ba5af6955f7

Firestore provider model is based on the examples in this good Youtube tutorial:

https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw

==========================================

https://docs.flutter.dev/data-and-backend/state-mgmt/simple

! Provider CheatSheet

// Step 1: Create Model class
class Counter extends ChangeNotifier {
  int count = 0;

  void increase() {
    count++;
    notifyListeners();
  }
}

// Step 2: Wrap root widget in MultiProvider, Also initialise Counter() here
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => Counter()),
  ],
  child: MaterialApp(),
)

// Step 3: Read value
final count = Provider.of<Counter>(context).count;

// Step 4: Write value
Provider.of<Counter>(context, listen: false).increase();




