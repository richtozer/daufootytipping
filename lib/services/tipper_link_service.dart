import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/cached_tipper_store.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';

/// What the sign-in page has to start with.
class LinkStart {
  const LinkStart._({this.cachedTipper, this.resolution});

  /// Open with the tipper kept on the device; confirm the link in the background
  /// with [TipperLinkService.refreshCached].
  const LinkStart.cached(Tipper tipper) : this._(cachedTipper: tipper);

  /// Nothing was kept (or it is a guest): this is the answer.
  const LinkStart.resolved(LinkResolution resolution)
    : this._(resolution: resolution);

  final Tipper? cachedTipper;
  final LinkResolution? resolution;

  bool get isCached => cachedTipper != null;
}

/// Links the signed-in account to its tipper for the sign-in page, deciding when
/// the tipper kept on the device may be used (DESIGN-database-rules-phase4.md, M7).
///
/// - The cache is used only for an account that has been linked before, and only the
///   copy saved for this very account.
/// - While a refresh is merely **delayed** (the server busy, no connection) the
///   cached tipper stays in use.
/// - If the server says the account is no longer linked, or refuses it, the cache is
///   thrown away: it described something that is not true any more.
/// - A first-time link that fails is a failure, never answered from a cache.
class TipperLinkService {
  TipperLinkService({
    required LinkedTipperResolver resolver,
    required CachedTipperStore cache,
  }) : _resolver = resolver,
       _cache = cache;

  final LinkedTipperResolver _resolver;
  final CachedTipperStore _cache;

  Future<LinkStart> begin(LinkAccount account) async {
    if (!account.isAnonymous) {
      final cached = await _cache.load(account.uid);
      if (cached != null) {
        return LinkStart.cached(cached);
      }
    }
    return LinkStart.resolved(await _resolve(account));
  }

  /// Confirms, after opening from the cache, that the account is still linked.
  Future<LinkResolution> refreshCached(LinkAccount account) async {
    final resolution = await _resolver.resolve(account);
    switch (resolution.status) {
      case LinkStatus.linked:
        await _cache.save(resolution.tipper!);
      case LinkStatus.unavailable:
        break; // keep using what we have
      case LinkStatus.needsAlias:
      case LinkStatus.refused:
      case LinkStatus.guest:
        await _cache.clear();
    }
    return resolution;
  }

  /// Creates the account's tipper with [alias], after [begin] answered
  /// [LinkStatus.needsAlias].
  Future<LinkResolution> createWithAlias(LinkAccount account, String alias) =>
      _resolve(account, alias: alias);

  /// Forgets the kept tipper: on sign-out and when the account is deleted.
  Future<void> forget() => _cache.clear();

  Future<LinkResolution> _resolve(LinkAccount account, {String? alias}) async {
    final resolution = await _resolver.resolve(account, alias: alias);
    if (resolution.status == LinkStatus.linked) {
      await _cache.save(resolution.tipper!);
    }
    return resolution;
  }
}
