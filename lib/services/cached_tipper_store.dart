import 'dart:convert';
import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last linked tipper, kept on the device so the app can open at once (and
/// when the server is slow or briefly unreachable) instead of waiting for the
/// link to be confirmed. Only a **linked** tipper is ever kept (never a guest),
/// it is only returned for the account it was saved for, and it is thrown away
/// the moment a different account turns up.
class CachedTipperStore {
  CachedTipperStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const String cachedTipperKey = 'cached_tipper';

  final Future<SharedPreferences> Function() _preferences;

  /// The cached tipper for [uid], or null. A copy saved for another account is
  /// cleared and not returned.
  Future<Tipper?> load(String uid) async {
    try {
      final prefs = await _preferences();
      final text = prefs.getString(cachedTipperKey);
      if (text == null) {
        return null;
      }
      final data = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (data['authuid'] != uid) {
        await prefs.remove(cachedTipperKey);
        return null;
      }
      final tipper = Tipper.fromCacheJson(data);
      if (tipper.dbkey == null || tipper.isAnonymous) {
        return null;
      }
      return tipper;
    } on Object catch (error) {
      log('CachedTipperStore: could not load the cached tipper: $error');
      return null;
    }
  }

  /// Keeps [tipper]. A guest, which has no record, is not kept.
  Future<void> save(Tipper tipper) async {
    if (tipper.dbkey == null || tipper.isAnonymous) {
      return;
    }
    try {
      final prefs = await _preferences();
      await prefs.setString(cachedTipperKey, jsonEncode(tipper.toCacheJson()));
    } on Object catch (error) {
      log('CachedTipperStore: could not cache the tipper: $error');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _preferences();
      await prefs.remove(cachedTipperKey);
    } on Object catch (error) {
      log('CachedTipperStore: could not clear the cached tipper: $error');
    }
  }
}
