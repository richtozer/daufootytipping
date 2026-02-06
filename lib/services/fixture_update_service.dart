import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';

typedef AcquireLock = Future<bool> Function();
typedef ReleaseLock = Future<void> Function();
typedef SetDownloading = void Function(bool value);
typedef ProcessFetchedFixtures = Future<String> Function(
    DAUComp comp, List<dynamic> nrlGames, List<dynamic> aflGames);

class FixtureUpdateService {
  final FixtureDownloadService _downloader;
  const FixtureUpdateService(this._downloader);

  Future<String> runUpdate({
    required DAUComp comp,
    required AcquireLock acquireLock,
    required ReleaseLock releaseLock,
    required SetDownloading setDownloading,
    required ProcessFetchedFixtures processFetched,
  }) async {
    // Try to acquire distributed lock
    final locked = await acquireLock();
    if (!locked) {
      return 'Another instance is already downloading the fixture data. Skipping download.';
    }

    setDownloading(true);
    try {
      final fixtures = await _downloader.fetch(
        comp.nrlFixtureJsonURL,
        comp.aflFixtureJsonURL,
        true,
      );
      final nrlGames = fixtures['nrlGames'] ?? <dynamic>[];
      final aflGames = fixtures['aflGames'] ?? <dynamic>[];
      return await processFetched(comp, nrlGames, aflGames);
    } finally {
      setDownloading(false);
      await releaseLock();
    }
  }
}

