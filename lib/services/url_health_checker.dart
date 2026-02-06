import 'package:dio/dio.dart';

class UrlHealthChecker {
  final Dio _dio;
  UrlHealthChecker({Dio? dio}) : _dio = dio ?? Dio();

  Future<bool> isActive(Uri uri) async {
    try {
      final res = await _dio.getUri(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

