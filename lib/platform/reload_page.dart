import 'reload_page_stub.dart'
    if (dart.library.js_interop) 'reload_page_web.dart'
    as impl;

/// Reloads the web page from the server, first dropping any service worker that
/// could hand back the old copy of the app. Does nothing off the web.
Future<void> reloadPage() => impl.reloadPage();
