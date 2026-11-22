import 'package:http/http.dart' as http;

/// A client that authenticates to the Realtime Database emulator as its admin
/// (`Bearer owner`), the way the deployed functions' service account bypasses
/// rules in production. Only for a database reached through
/// `FIREBASE_DATABASE_EMULATOR_HOST`.
class EmulatorAdminClient extends http.BaseClient {
  EmulatorAdminClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
