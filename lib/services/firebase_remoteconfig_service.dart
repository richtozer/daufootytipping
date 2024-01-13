import 'dart:developer';

import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  RemoteConfigService();

  FirebaseRemoteConfig get remoteConfig => _remoteConfig;

  Future<void> initialize() async {
    await _remoteConfig.setDefaults(const {
      "currentDAUComp":
          '-Nk88l-ww9pYF1j_jUq7', //TODO this should be updated every year
      "minAppVersion":
          "1.0.0", // Make sure to set the default/fallback value on the client to a version number that is not forcing them to update
    });
    log('activating remote config');
    await _remoteConfig.activate();
    log('actviated! fetching any updated remote config');
    await _remoteConfig
        .fetch(); // fetch any new remote config changes lazyly - these will be actvated the next time the user starts the app
    log('fetched! config initialised ');
  }
}
