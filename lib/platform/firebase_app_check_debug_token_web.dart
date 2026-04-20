import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _globalThis;

void setFirebaseAppCheckDebugToken(Object? token) {
  final JSAny? jsValue = switch (token) {
    bool value => value.toJS,
    String value => value.toJS,
    null => null,
    _ => throw ArgumentError.value(
      token,
      'token',
      'Expected a bool, String, or null.',
    ),
  };

  _globalThis.setProperty(
    'FIREBASE_APPCHECK_DEBUG_TOKEN'.toJS,
    jsValue,
  );
}

Object? getFirebaseAppCheckDebugToken() {
  final JSAny? jsValue = _globalThis['FIREBASE_APPCHECK_DEBUG_TOKEN'];
  if (jsValue == null || jsValue.isUndefined) {
    return null;
  }

  return jsValue.dartify();
}
