import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter/foundation.dart';

/// Reads a `cloud_functions` error as an [IdentityFailure]: the plugin's code,
/// message and details (the server's `ErrorInfo` list) are what the client needs.
IdentityFailure identityFailureFromFunctionsException(
  FirebaseFunctionsException error,
) => IdentityFailure.fromFunctionsError(
  code: error.code,
  message: error.message,
  details: error.details,
);

/// An [IdentityCallableInvoker] over the `cloud_functions` plugin. The plugin adds
/// the signed-in user's ID token and the App Check token, which the identity
/// callables require.
class FunctionsIdentityCallableInvoker implements IdentityCallableInvoker {
  /// [emulatorHost] and [emulatorPort] point at the local Functions emulator
  /// instead of the deployed services (debug builds only).
  FunctionsIdentityCallableInvoker({
    required this.endpoints,
    this.region = 'asia-southeast1',
    this.emulatorHost,
    this.emulatorPort = 9229,
  });

  /// Evaluated on each call, so an address changed in `AppConfig` applies at once.
  final IdentityEndpoints Function() endpoints;
  final String region;
  final String? emulatorHost;
  final int emulatorPort;

  FirebaseFunctions? _emulatorFunctions;

  HttpsCallable _callable(String endpoint, Duration timeout) {
    final options = HttpsCallableOptions(timeout: timeout);
    final host = emulatorHost;
    if (host != null && kDebugMode) {
      // useFunctionsEmulator may be called once per instance, so keep it.
      final functions = _emulatorFunctions ??= FirebaseFunctions.instanceFor(
        region: region,
      )..useFunctionsEmulator(host, emulatorPort);
      return functions.httpsCallable(endpoint, options: options);
    }
    return FirebaseFunctions.instance.httpsCallableFromUrl(
      endpoints().urlFor(endpoint),
      options: options,
    );
  }

  @override
  Future<Object?> call(
    String endpoint,
    Map<String, Object?> data, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    try {
      final result = await _callable(endpoint, timeout).call<Object?>(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw identityFailureFromFunctionsException(error);
    } on Exception catch (error) {
      // A failure before the server answered: no connection, a timeout.
      throw IdentityFailure.network(error);
    }
  }
}
