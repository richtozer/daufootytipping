import 'package:test/test.dart';

import 'package:daufootytipping/services/lock_manager.dart';

void main() {
  group('LockManager', () {
    final lm = LockManager();

    test('lockPathForComp builds expected path', () {
      expect(lm.lockPathForComp('/AllDAUComps', 'abc123'), '/AllDAUComps/abc123/downloadLock');
    });

    test('isLockFresh checks TTL correctly', () {
      final now = DateTime.utc(2025, 1, 2, 0, 0, 0);
      final fresh = now.subtract(const Duration(hours: 1));
      final stale = now.subtract(const Duration(hours: 25));
      expect(lm.isLockFresh(fresh, now, const Duration(hours: 24)), isTrue);
      expect(lm.isLockFresh(stale, now, const Duration(hours: 24)), isFalse);
      expect(lm.isLockFresh(null, now, const Duration(hours: 24)), isFalse);
    });
  });
}

