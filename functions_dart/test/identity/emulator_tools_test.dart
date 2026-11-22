import 'package:dart_functions/identity/emulator_tools.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('without the emulator host the tools go through the Firebase CLI', () {
    expect(emulatorDatabaseFromEnvironment(const {}), isNull);
    expect(
      emulatorDatabaseFromEnvironment(const {
        'FIREBASE_DATABASE_EMULATOR_HOST': '',
      }),
      isNull,
    );
  });

  test(
    'with it, they use that emulator, as its administrator, in the demo namespace',
    () async {
      late http.BaseRequest seen;
      final database = emulatorDatabaseFromEnvironment(
        const {'FIREBASE_DATABASE_EMULATOR_HOST': '127.0.0.1:9361'},
        client: MockClient((request) async {
          seen = request;
          return http.Response('null', 200);
        }),
      );

      await database!.ref('/AllTippers').once();

      expect(seen.url.host, '127.0.0.1');
      expect(seen.url.port, 9361);
      expect(seen.url.queryParameters['ns'], 'demo-dau-rules');
      expect(seen.headers['Authorization'], 'Bearer owner');
    },
  );

  test('the namespace can be named', () async {
    late http.BaseRequest seen;
    final database = emulatorDatabaseFromEnvironment(
      const {
        'FIREBASE_DATABASE_EMULATOR_HOST': 'localhost:9000',
        'RTDB_EMULATOR_NAMESPACE': 'demo-other',
      },
      client: MockClient((request) async {
        seen = request;
        return http.Response('null', 200);
      }),
    );

    await database!.ref('/x').once();

    expect(seen.url.queryParameters['ns'], 'demo-other');
  });
}
