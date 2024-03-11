import 'package:daufootytipping/models/tipperrole.dart';
import 'package:test/test.dart';

void main() {
  group('TipperRole', () {
    test('should have correct values', () {
      expect(TipperRole.admin.name, equals('admin'));
      expect(TipperRole.tipper.name, equals('tipper'));
    });
  });
}
