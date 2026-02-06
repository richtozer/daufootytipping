import 'package:daufootytipping/constants/paths.dart' as p;

class LockManager {
  const LockManager();

  String lockPathForComp(String daucompsPath, String compDbKey) =>
      '$daucompsPath/$compDbKey/${p.downloadLockKey}';

  bool isLockFresh(DateTime? lockTimestamp, DateTime now, Duration ttl) {
    if (lockTimestamp == null) return false;
    return now.difference(lockTimestamp) < ttl;
  }
}
