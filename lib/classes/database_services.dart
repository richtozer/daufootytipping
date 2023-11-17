import 'package:daufootytipping/classes/footytipping_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:daufootytipping/classes/dau.dart';

class DatabaseService {
  final _db = FirebaseDatabase.instance.ref();

  getDAUComps() async {
    DatabaseReference dauComps = FirebaseDatabase.instance.ref(dauCompsPath);
    dauComps.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
    });
  }

  addDAUComp(DAUComp dauCompData) async {
    // A post entry.
    final postData = dauCompData.toMap();

    // Get a key for a new Post.
    final newDAUCompKey = _db.child(dauCompsPath).push().key;

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    final Map<String, Map> updates = {};
    updates['$dauCompsPath/$newDAUCompKey'] = postData;
    //updates['/user-posts/$uid/$newPostKey'] = postData;

    return FirebaseDatabase.instance
        .ref()
        .update(updates)
        .then((_) {})
        .catchError((onError) {
      print(onError.toString());
    });
  }

  updateDAUComp(DAUComp dauCompData) async {}

  Future<void> deleteDAUComp(String documentId) async {}

  getTippers() async {
    DatabaseReference tippers = FirebaseDatabase.instance.ref(tippersPath);
    tippers.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
    });
  }

  addTipper(Tipper tipperData) async {
    // A post entry.
    final postData = tipperData.toJson();

    // Get a key for a new Post.
    final newTipperKey = _db.child(tippersPath).push().key;

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    final Map<String, Map> updates = {};
    updates['$tippersPath/$newTipperKey'] = postData;
    //updates['/user-posts/$uid/$newPostKey'] = postData;

    return FirebaseDatabase.instance
        .ref()
        .update(updates)
        .then((_) {})
        .catchError((onError) {
      print(onError.toString());
    });
  }

  updateTipper(Tipper tipperData) async {}

  Future<void> deleteTipper(String documentId) async {}
}
