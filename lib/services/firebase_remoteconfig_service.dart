import 'dart:async';
import 'dart:developer';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

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

    await _remoteConfig.setDefaults(const {
      // These are defaults that are used for clients installed for the very first time
      // The initial remote config fetch will overwrite these values but wont take
      // effect until the next client restart
      "currentDAUComp":
          '-Nk88l-ww9pYF1j_jUq7', //TODO this should be updated every year
      "minAppVersion":
          "1.0.0", // Make sure to set the default/fallback version number of the client to a number that is not forcing them to update unnessarily
    });
    log('activating remote config');
    await _remoteConfig.fetchAndActivate();
    _initialization.complete();
    log('config initialised ');
  }
}
