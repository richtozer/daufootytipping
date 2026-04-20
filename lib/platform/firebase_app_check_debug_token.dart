import 'firebase_app_check_debug_token_stub.dart'
    if (dart.library.js_interop) 'firebase_app_check_debug_token_web.dart'
    as impl;

void setFirebaseAppCheckDebugToken(Object? token) {
  impl.setFirebaseAppCheckDebugToken(token);
}

Object? getFirebaseAppCheckDebugToken() {
  return impl.getFirebaseAppCheckDebugToken();
}
