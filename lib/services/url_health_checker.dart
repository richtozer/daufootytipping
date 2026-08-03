import 'package:dio/dio.dart';

typedef FixtureUrlRemoteChecker = Future<bool> Function(Uri uri);

class UrlHealthChecker {
  final Dio _dio;
  final FixtureUrlRemoteChecker? _remoteChecker;
  final bool _allowDirectFallback;

  /// [allowDirectFallback] controls what happens when [remoteChecker] throws
  /// (e.g. the backend proxy is unreachable or not configured). Set this to
  /// false on platforms where a direct request would itself be blocked (e.g.
  /// browser CORS restrictions on web) — a direct-check attempt there would
  /// just recreate the original failure and misreport it as "not active"
  /// rather than surfacing the real "validation backend unavailable" error.
  UrlHealthChecker({
    Dio? dio,
    FixtureUrlRemoteChecker? remoteChecker,
    bool allowDirectFallback = true,
  }) : _dio = dio ?? Dio(),
       _remoteChecker = remoteChecker,
       _allowDirectFallback = allowDirectFallback;

  Future<bool> isActive(Uri uri) async {
    final remoteChecker = _remoteChecker;
    if (remoteChecker != null) {
      if (!_allowDirectFallback) {
        return remoteChecker(uri);
      }
      try {
        return await remoteChecker(uri);
      } catch (_) {
        // Fall through to a direct check.
      }
    }

    try {
      final res = await _dio.getUri(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isActiveIfChanged(Uri uri, {Uri? previousUri}) async {
    if (uri == previousUri) {
      return true;
    }

    return isActive(uri);
  }
}
