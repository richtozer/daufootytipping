/// Refuses to start a deployed function that has the emulator's debug switches
/// on.
///
/// firebase_functions skips the check of the ID token and the App Check token
/// when `FIREBASE_DEBUG_FEATURES` contains `skipTokenVerification`, and it
/// does not check that it is running in the emulator: set on a deployed
/// function, the switch would let anyone claim any uid. Nothing in this
/// repository sets it, and this makes sure nothing ever can by accident.
///
/// The emulator is recognised by `FUNCTIONS_EMULATOR=true` (which the Functions
/// emulator sets) and the absence of `K_SERVICE` (which Cloud Run sets on every
/// deployed service). Any value of `FIREBASE_DEBUG_FEATURES` outside the
/// emulator is refused, not only the one switch: they are all for the emulator.
void assertNoDebugFeaturesOutsideEmulator(Map<String, String> environment) {
  final features = environment['FIREBASE_DEBUG_FEATURES'];
  if (features == null || features.trim().isEmpty) {
    return;
  }
  final inEmulator =
      environment['FUNCTIONS_EMULATOR'] == 'true' &&
      (environment['K_SERVICE'] ?? '').isEmpty;
  if (inEmulator) {
    return;
  }
  throw StateError(
    'FIREBASE_DEBUG_FEATURES is set outside the Functions emulator. It can '
    'switch off the verification of ID tokens and App Check tokens, so this '
    'function will not start. Remove it from the function\'s environment '
    '(functions_dart/.env, functions/.env, the deploy environment).',
  );
}
