import 'dart:async';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database locations
const daucompsPath = '/DAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  List<DAUComp> get daucomps => _daucomps;

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  //constructor
  DAUCompsViewModel() {
    _listenToDAUComps();
  }

  // monitor changes to DAUComp records in DB and notify listeners of any changes
  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allDAUComps =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _daucomps = allDAUComps.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic daucompasJSON = entry.value;

          return DAUComp.fromJson(
              Map<String, dynamic>.from(daucompasJSON), key);
        }).toList();

        _daucomps.sort();

        notifyListeners();
      }
    });
  }

  Future<void> editDAUComp(DAUComp daucomp) async {
    try {
      _savingDAUComp = true;
      notifyListeners();

      // update the record in firebase
      final Map<String, Map> updates = {};
      updates['$daucompsPath/${daucomp.dbkey}'] = daucomp.toJson();
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  Future<void> addDAUComp(DAUComp newdaucomp) async {
    try {
      _savingDAUComp = true;
      notifyListeners();

      // A post entry.
      final postData = newdaucomp.toJson();

      // Get a key for a new Post.
      final newdaucompKey = _db.child(daucompsPath).push().key;

      // Write the new post's data simultaneously in the posts list and the
      // user's post list.
      final Map<String, Map> updates = {};
      updates['$daucompsPath/$newdaucompKey'] = postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
