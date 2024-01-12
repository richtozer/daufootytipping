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

    _remoteConfig.activate();
    _remoteConfig.fetch(); //fetch updated config for next time user starts app
  }
}
