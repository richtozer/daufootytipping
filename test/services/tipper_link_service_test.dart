import 'dart:convert';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/cached_tipper_store.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:daufootytipping/services/tipper_link_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockResolver extends Mock implements LinkedTipperResolver {}

Tipper _tipper({
  String? key = 't1',
  String uid = 'uidA',
  String name = 'Alice',
  bool guest = false,
}) => Tipper(
  dbkey: key,
  authuid: uid,
  email: 'a@example.test',
  logon: 'a@example.test',
  name: name,
  tipperRole: TipperRole.admin,
  compsPaidFor: <DAUComp>[],
  isAnonymous: guest,
);

const LinkAccount _alice = LinkAccount(uid: 'uidA', isAnonymous: false);

Future<String?> _stored() async => (await SharedPreferences.getInstance())
    .getString(CachedTipperStore.cachedTipperKey);

void main() {
  late CachedTipperStore cache;
  late _MockResolver resolver;
  late TipperLinkService service;

  setUpAll(() {
    registerFallbackValue(_alice);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cache = CachedTipperStore();
    resolver = _MockResolver();
    service = TipperLinkService(resolver: resolver, cache: cache);
  });

  void resolvesTo(LinkResolution resolution) {
    when(() => resolver.resolve(any(), alias: any(named: 'alias')))
        .thenAnswer((_) async => resolution);
  }

  group('CachedTipperStore', () {
    test(
      'keeps a linked tipper and gives it back for the same account',
      () async {
        await cache.save(_tipper());
        final loaded = await cache.load('uidA');
        expect(loaded!.dbkey, 't1');
        expect(loaded.name, 'Alice');
        expect(loaded.tipperRole, TipperRole.admin);
      },
    );

    test('never keeps a guest, or a tipper with no record', () async {
      await cache.save(_tipper(key: null));
      await cache.save(_tipper(guest: true));
      expect(await _stored(), isNull);
    });

    test(
      'gives nothing back for another account, and throws the old one away',
      () async {
        await cache.save(_tipper());
        expect(await cache.load('uidB'), isNull);
        expect(
          await _stored(),
          isNull,
          reason: 'the previous account\'s copy is not left lying about',
        );
      },
    );

    test('a corrupt copy is nothing, not a crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CachedTipperStore.cachedTipperKey: '{not json',
      });
      expect(await CachedTipperStore().load('uidA'), isNull);
      SharedPreferences.setMockInitialValues(<String, Object>{
        CachedTipperStore.cachedTipperKey: jsonEncode(<String, Object?>{
          'authuid': 'uidA',
        }),
      });
      expect(await CachedTipperStore().load('uidA'), isNull);
    });

    test('a stored guest is not returned', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CachedTipperStore.cachedTipperKey: jsonEncode(
          _tipper(key: null, guest: true).toCacheJson(),
        ),
      });
      expect(await CachedTipperStore().load('uidA'), isNull);
    });

    test('clear removes it', () async {
      await cache.save(_tipper());
      await cache.clear();
      expect(await cache.load('uidA'), isNull);
    });
  });

  group('opening the app', () {
    test('uses the kept tipper at once and does not ask the server', () async {
      await cache.save(_tipper());
      final start = await service.begin(_alice);
      expect(start.isCached, true);
      expect(start.cachedTipper!.dbkey, 't1');
      verifyNever(() => resolver.resolve(any(), alias: any(named: 'alias')));
    });

    test(
      'with nothing kept, links, and keeps the result for next time',
      () async {
        resolvesTo(LinkResolution.linked(_tipper(name: 'Fresh')));
        final start = await service.begin(_alice);
        expect(start.isCached, false);
        expect(start.resolution!.status, LinkStatus.linked);
        expect((await cache.load('uidA'))!.name, 'Fresh');
      },
    );

    test('a first link that fails is a failure, kept nowhere', () async {
      for (final resolution in <LinkResolution>[
        const LinkResolution.unavailable('later'),
        const LinkResolution.refused('no'),
        const LinkResolution.needsAlias(),
      ]) {
        resolvesTo(resolution);
        final start = await service.begin(_alice);
        expect(start.isCached, false);
        expect(start.resolution!.status, resolution.status);
        expect(await _stored(), isNull);
      }
    });

    test(
      'a guest is never kept, and never uses another account\'s copy',
      () async {
        await cache.save(_tipper());
        resolvesTo(
          LinkResolution.guest(
            _tipper(key: null, uid: 'guestUid', guest: true),
          ),
        );
        final start = await service.begin(
          const LinkAccount(uid: 'guestUid', isAnonymous: true),
        );
        expect(start.isCached, false);
        expect(start.resolution!.status, LinkStatus.guest);
      },
    );

    test(
      'a different account signing in finds no copy of the last one\'s',
      () async {
        await cache.save(_tipper());
        resolvesTo(const LinkResolution.needsAlias());
        final start = await service.begin(
          const LinkAccount(uid: 'uidB', isAnonymous: false),
        );
        expect(start.isCached, false);
        expect(start.resolution!.status, LinkStatus.needsAlias);
        expect(await _stored(), isNull);
      },
    );
  });

  group(
    'confirming the link in the background after opening from the kept tipper',
    () {
      setUp(() async {
        await cache.save(_tipper(name: 'Old name'));
      });

      test('a confirmed link refreshes what is kept', () async {
        resolvesTo(LinkResolution.linked(_tipper(name: 'New name')));
        final resolution = await service.refreshCached(_alice);
        expect(resolution.status, LinkStatus.linked);
        expect((await cache.load('uidA'))!.name, 'New name');
      });

      test(
        'a delay (server busy, no connection) keeps using the kept tipper',
        () async {
          resolvesTo(const LinkResolution.unavailable('busy'));
          final resolution = await service.refreshCached(_alice);
          expect(resolution.status, LinkStatus.unavailable);
          expect((await cache.load('uidA'))!.name, 'Old name');
        },
      );

      test('a refusal throws the kept tipper away', () async {
        resolvesTo(
          const LinkResolution.refused(
            'This tipper belongs to another account.',
          ),
        );
        final resolution = await service.refreshCached(_alice);
        expect(resolution.status, LinkStatus.refused);
        expect(await _stored(), isNull);
      });

      test('an account that is no longer linked throws it away too', () async {
        resolvesTo(const LinkResolution.needsAlias());
        await service.refreshCached(_alice);
        expect(await _stored(), isNull);
      });
    },
  );

  group('creating a tipper', () {
    test(
      'passes the alias to the resolver, and keeps what it creates',
      () async {
        resolvesTo(LinkResolution.linked(_tipper(name: 'The Oracle')));
        final resolution = await service.createWithAlias(_alice, 'The Oracle');
        verify(() => resolver.resolve(_alice, alias: 'The Oracle')).called(1);
        expect(resolution.status, LinkStatus.linked);
        expect((await cache.load('uidA'))!.name, 'The Oracle');
      },
    );

    test('a refused alias keeps nothing', () async {
      resolvesTo(const LinkResolution.refused('Taken', reason: 'alias_taken'));
      final resolution = await service.createWithAlias(_alice, 'x');
      expect(resolution.reason, 'alias_taken');
      expect(await _stored(), isNull);
    });
  });

  test('forgetting clears what is kept', () async {
    await cache.save(_tipper());
    await service.forget();
    expect(await _stored(), isNull);
  });
}
