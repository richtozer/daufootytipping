class LockManager {
  const LockManager();

  String lockPathForComp(String daucompsPath, String compDbKey) =>
      '$daucompsPath/$compDbKey/downloadLock';

  bool isLockFresh(DateTime? lockTimestamp, DateTime now, Duration ttl) {
    if (lockTimestamp == null) return false;
    return now.difference(lockTimestamp) < ttl;
  }
}

