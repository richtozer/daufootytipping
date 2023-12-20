import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthViewModel {
  DatabaseReference tippersRef =
      FirebaseDatabase.instance.ref().child('/Tippers');
  User user;
  Tipper? currentTipper;
  final Completer<void> _initialLoadCompleter = Completer<void>();

  //contructor - takes Firebase authenticated user as a parameter and assigns it to the user property
  AuthViewModel(this.user);

  Future<Tipper> getCurrentTipper() async {
    if (currentTipper == null) {
      _findTipper();
    }
    log('Waiting for initial Tipper load to complete, getCurrentTipper()');
    await _initialLoadCompleter.future;
    log('tipper load complete, getCurrentTipper()');

    await FirebaseAnalytics.instance.setUserProperty(
      name: 'role',
      value: currentTipper?.tipperRole.name,
    );
    await FirebaseAnalytics.instance.setUserProperty(
      name: 'active',
      value: currentTipper?.active.toString(),
    );

    await FirebaseAnalytics.instance.setUserId(id: currentTipper?.name);

    return currentTipper!;
  }

  Future<void> _findTipper() async {
    Query tipperRefByAuthId =
        tippersRef.orderByChild('authuid').equalTo(user.uid).limitToFirst(1);

    Query tipperRefByEmail =
        tippersRef.orderByChild('email').equalTo(user.email).limitToFirst(1);

    DatabaseEvent eventByAuthId = await tipperRefByAuthId.once();
    DataSnapshot snapshotByAuthId = eventByAuthId.snapshot;
    _processTipper(snapshotByAuthId, false);

    DatabaseEvent eventByEmail = await tipperRefByEmail.once();
    DataSnapshot snapshotByEmail = eventByEmail.snapshot;
    _processTipper(snapshotByEmail, true);
  }

  void _processTipper(DataSnapshot snapshot, bool foundByEmail) async {
    try {
      // if the /Tipper key does not exist i.e brand new database, then just create a new tipper record
      if (!snapshot.exists) {
        log('YYY Root /Tipper records not found, creating new root and tipper');
        Tipper newTipper = Tipper(
          name: user.email!,
          email: user.email!,
          authuid: user.uid,
          active: false,
          tipperRole: TipperRole.tipper,
        );
        DatabaseReference ref = tippersRef.push();
        await ref.set(newTipper.toJson());
        newTipper.dbkey = ref.key;
        currentTipper = newTipper;
        if (!_initialLoadCompleter.isCompleted) {
          _initialLoadCompleter.complete();
        }

        await FirebaseAnalytics.instance.logEvent(
          name: 'new_tipper',
          parameters: <String, dynamic>{
            'name': newTipper.name,
            'email': newTipper.email,
            'authuid': newTipper.authuid,
            'active': newTipper.active.toString(),
            'tipperRole': newTipper.tipperRole.name,
          },
        );

        return;
      }
      if (snapshot.value != null) {
        List<Tipper?> searchResults = Tipper.fromJsonList(snapshot.value);

        if (searchResults.length == 1) {
          Tipper foundTipper = searchResults.first as Tipper;

          log('YYY found tipper: ${foundTipper.name}');

          // Update authuid if tipper was found by email
          if (foundByEmail && foundTipper.authuid != user.uid) {
            log('YYY found tipper by email, updating uid: ${user.uid}');
            foundTipper.authuid = user.uid;
            await tippersRef
                .child(searchResults.first!.dbkey!)
                .update(foundTipper.toJson());

            await FirebaseAnalytics.instance.logEvent(
              name: 'existing_tipper_uid_updated',
              parameters: <String, dynamic>{
                'name': foundTipper.name,
                'email': foundTipper.email,
                'authuid': foundTipper.authuid,
                'active': foundTipper.active.toString(),
                'tipperRole': foundTipper.tipperRole.name,
              },
            );
          } else {
            await FirebaseAnalytics.instance.logEvent(
              name: 'existing_tipper_already_linked',
              parameters: <String, dynamic>{
                'name': foundTipper.name,
                'email': foundTipper.email,
                'authuid': foundTipper.authuid,
                'active': foundTipper.active.toString(),
                'tipperRole': foundTipper.tipperRole.name,
              },
            );
          }

          // Use the found Tipper
          log('YYY new linking logic complete');
          currentTipper = foundTipper;
          if (!_initialLoadCompleter.isCompleted) {
            _initialLoadCompleter.complete();
          }
        } else {
          // Create a new Tipper
          log('YYY creating new tipper');
          String email = user.email ?? 'default@email.com';
          Tipper newTipper = Tipper(
            name: user.email!,
            email: email,
            authuid: user.uid,
            active: false,
            tipperRole: TipperRole.tipper,
          );
          await tippersRef.push().set(newTipper.toJson());
          currentTipper = newTipper;
          if (!_initialLoadCompleter.isCompleted) {
            _initialLoadCompleter.complete();
          }

          await FirebaseAnalytics.instance.logEvent(
            name: 'new_tipper',
            parameters: <String, dynamic>{
              'name': newTipper.name,
              'email': newTipper.email,
              'authuid': newTipper.authuid,
              'active': newTipper.active,
              'tipperRole': newTipper.tipperRole,
            },
          );
        }
      }
    } catch (e) {
      log('An error occurred: $e');
    } finally {}
  }
}
