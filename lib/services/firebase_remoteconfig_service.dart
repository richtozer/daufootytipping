import 'dart:async';
import 'dart:developer';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  RemoteConfigService() {
    initialize();
  }

  final Completer<void> _initialization = Completer<void>();

  Future<String> getConfigCurrentDAUComp() async {
    await _initialization.future;
    return _remoteConfig.getString('currentDAUComp');
  }

  Future<String> getConfigMinAppVersion() async {
    await _initialization.future;
    return _remoteConfig.getString('minAppVersion');
  }

  Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(minutes: kDebugMode ? 5 : 720),
    ));

    await _remoteConfig.setDefaults({
      // These are defaults that are used for clients installed for the very first time
      // The initial remote config fetch will overwrite these values but wont take
      // effect until the next client restart
      "currentDAUComp": dotenv.env['CURRENT_DAU_COMP'],
      "minAppVersion": dotenv.env[
          'MIN_APP_VERSION'], // Make sure to set the default/fallback version number of the client to a number that is not forcing them to update unnessarily
    });
    log('activating remote config');

    try {
      await _remoteConfig.fetchAndActivate();
      log('config initialised ');
    } catch (e) {
      log('Error fetching remote config: $e');
    } finally {
      _initialization.complete();
    }
  }
}
