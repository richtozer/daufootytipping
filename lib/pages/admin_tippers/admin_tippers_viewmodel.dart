import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';

// define  constant for firestore database locations
const tippersPath = '/Tippers';

class TipperViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;
  Tipper? _currentTipper;

  List<Tipper> get tippers => _tippers;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;
  Tipper? get currentTipper => _currentTipper;

  //List<Tipper> get admins =>
  //    _tippers.where((tipper) => tipper.name.contains('Phil'));
  //List<Team> get teams => _teams;

  //constructor
  TipperViewModel() {
    _listenToTippers();
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    late StreamSubscription<DatabaseEvent> tippersStream;

    tippersStream = _db.child(tippersPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allTippers =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _tippers = allTippers.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic tipperasJSON = entry.value;

          return Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
        }).toList();

        _tippers.sort();

        notifyListeners();

        /* TODO - while the above code works fine, it would not work if we added the
        firebase OrderbyValue() method. 

        https://stackoverflow.com/questions/61333194/flutter-firebase-real-time-database-orderbychild-has-no-impact-on-query-result
      
        The code below does sort of work, but the List[] keeps growing and items get 
        duplicated in the UI. 

      if (event.snapshot.exists) {
        // we need to use a foreach loop here to get data to orderbychild()
        event.snapshot.children.forEach((tipperRecordJSON) {
          String key =
              tipperRecordJSON.key as String; // Retrieve the Firebase key
          dynamic tipperasJSON = tipperRecordJSON.value;

          final tipper =
              Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
          _tippers.add(tipper);
        });
        */
      }
    });
  }

  void linkTipper(User? firebaseUser) async {
    //see if we can find an existing Tipper record using uid
    Tipper? foundTipper = await findTipperByUid(firebaseUser!.uid);

    if (foundTipper != null) {
      //we found an existing Tipper record using uid, so use it
      _currentTipper = foundTipper;
    } else {
      //if we can't find an existing Tipper record using uid, see if we can find an existing Tipper record using email

      Tipper? foundTipper = await findTipperByEmail(firebaseUser.email!);
      if (foundTipper != null) {
        //update the tipper record to use the firebase uid
        Tipper updateTipper = Tipper(
          dbkey: foundTipper.dbkey,
          authuid: firebaseUser.uid,
          email: foundTipper.email,
          name: foundTipper.name,
          active: foundTipper.active,
          tipperRole: foundTipper.tipperRole,
        );

        //update the tipper record in the database
        editTipper(updateTipper);

        //save the current logged on tipper to the model for later use
        _currentTipper = updateTipper;
      } else {
        //otherwise create a new tipper record and link it to the firebase user, set active to false and tipperrole to tipper
        _currentTipper = Tipper(
          name: firebaseUser.email!,
          email: firebaseUser.email!,
          authuid: firebaseUser.uid,
          active: false,
          tipperRole: TipperRole.tipper,
        );
        addTipper(_currentTipper!);
      }
    }
  }

  Future<void> editTipper(Tipper updatedTipper) async {
    try {
      _savingTipper = true;
      notifyListeners();

      //the original Tipper record should be in our list of tippers
      Tipper? originalTipper = _tippers.firstWhereOrNull(
          (existingTipper) => existingTipper.dbkey == updatedTipper.dbkey);

      //only edit the tipper record if it already exists, otherwise ignore
      if (originalTipper != null) {
        // Convert the original and updated tippers to JSON
        Map<String, dynamic> originalJson = originalTipper.toJson();
        Map<String, dynamic> updatedJson = updatedTipper.toJson();

        // Use JsonDiffer to get the differences
        JsonDiffer differ = JsonDiffer.fromJson(originalJson, updatedJson);
        DiffNode diff = differ.diff();

        // Initialize an empty map to hold all updates
        Map<String, dynamic> updates = {};

        // transform the changes from JsonDiffer format to Firebase format
        Map changed = diff.changed;
        changed.keys.toList().forEach((key) {
          if (changed[key] is List && (changed[key] as List).isNotEmpty) {
            // Add the update to the updates map
            updates['$tippersPath/${updatedTipper.dbkey}/$key'] =
                changed[key][1];
          }
        });

        // Apply any updates to Firebase
        _db.update(updates);
      } else {
        log('Tipper: ${updatedTipper.dbkey} does not exist in the database, ignoring edit request');
      }
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Future<void> addTipper(Tipper tipperData) async {
    try {
      _savingTipper = true;
      notifyListeners();

      // A post entry.
      final postData = tipperData.toJson();

      // Get a key for a new Post.
      final newTipperKey = _db.child(tippersPath).push().key;

      // Write the new post's data simultaneously in the posts list and the
      // user's post list.
      final Map<String, Map> updates = {};
      updates['$tippersPath/$newTipperKey'] = postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Future<Tipper?> findTipperByField(String field, String value) async {
    DatabaseReference dbTippers = _db.child(tippersPath);
    DatabaseEvent event =
        await dbTippers.orderByChild(field).equalTo(value).once();

    if (event.snapshot.value != null) {
      Map<dynamic, dynamic> dataSnapshot =
          event.snapshot.value as Map<dynamic, dynamic>;
      for (var entry in dataSnapshot.entries) {
        if (entry.value is Map) {
          return Tipper.fromJson(
              Map<String, dynamic>.from(entry.value as Map), entry.key!);
        }
      }
    }
    return null;
  }

  Future<Tipper?> findTipperByUid(String authuid) async {
    return findTipperByField('authuid', authuid);
  }

  Future<Tipper?> findTipperByEmail(String email) async {
    return findTipperByField('email', email);
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
