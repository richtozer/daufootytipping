import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _globalThis;

void setFirebaseAppCheckDebugToken(bool enabled) {
  _globalThis.setProperty(
    'FIREBASE_APPCHECK_DEBUG_TOKEN'.toJS,
    enabled.toJS,
  );
}
