Useful links:

Integrate Firebase Realtime with Google sheets
https://gist.github.com/CodingDoug/44ad12f4836e79ca9fa11ba5af6955f7

Firestore provider model is based on the examples in this good Youtube tutorial:

https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw

==========================================

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




