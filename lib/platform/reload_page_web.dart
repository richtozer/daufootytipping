import 'dart:developer';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _globalThis;

/// Reloads the page, after unregistering the service workers, so that the
/// reload cannot be answered from an old copy of the app that a worker cached.
/// A worker that cannot be cleared must not stop the reload.
Future<void> reloadPage() async {
  try {
    await _unregisterServiceWorkers();
  } on Object catch (error) {
    log('reloadPage: could not clear the service workers: $error');
  }
  final JSObject? location = _globalThis['location'] as JSObject?;
  location?.callMethod<JSAny?>('reload'.toJS);
}

Future<void> _unregisterServiceWorkers() async {
  final JSObject? navigator = _globalThis['navigator'] as JSObject?;
  final JSObject? workers = navigator?['serviceWorker'] as JSObject?;
  if (workers == null) {
    return;
  }
  final JSAny? registrations = await workers
      .callMethod<JSPromise<JSAny?>>('getRegistrations'.toJS)
      .toDart;
  if (registrations == null) {
    return;
  }
  for (final JSAny? registration in (registrations as JSArray<JSAny?>).toDart) {
    await (registration as JSObject)
        .callMethod<JSPromise<JSAny?>>('unregister'.toJS)
        .toDart;
  }
}
