import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:daufootytipping/services/tipper_link_service.dart';
import 'package:daufootytipping/view_models/sign_in_link_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements TipperLinkService {}

Tipper _tipper({
  String name = 'Alice',
  String? key = 't1',
  bool guest = false,
}) => Tipper(
  dbkey: key,
  authuid: 'uidA',
  email: null,
  name: name,
  tipperRole: TipperRole.tipper,
  compsPaidFor: <DAUComp>[],
  isAnonymous: guest,
);

const LinkAccount _alice = LinkAccount(
  uid: 'uidA',
  isAnonymous: false,
  photoUrl: 'g.png',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockService service;
  late List<Tipper> adopted;
  late List<String?> photos;
  late List<LinkPhase> phases;
  late SignInLinkController controller;

  SignInLinkController make({bool canCreate = true}) {
    final made = SignInLinkController(
      service: service,
      adoptTipper: adopted.add,
      syncPhoto: (String? url) async => photos.add(url),
      canCreateTippers: canCreate,
    );
    made.addListener(() => phases.add(made.phase));
    return made;
  }

  setUpAll(() {
    registerFallbackValue(_alice);
  });

  setUp(() {
    service = _MockService();
    adopted = <Tipper>[];
    photos = <String?>[];
    phases = <LinkPhase>[];
    controller = make();
  });

  tearDown(() => controller.dispose());

  void beginReturns(LinkStart start) {
    when(() => service.begin(any())).thenAnswer((_) async => start);
  }

  void refreshReturns(LinkResolution resolution) {
    when(() => service.refreshCached(any()))
        .thenAnswer((_) async => resolution);
  }

  group('opening from the tipper kept on the device', () {
    test('the app opens at once, then the link is confirmed and the fresh tipper adopted', () async {
      beginReturns(LinkStart.cached(_tipper(name: 'Old')));
      refreshReturns(LinkResolution.linked(_tipper(name: 'New')));
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.ready);
      expect(adopted.map((t) => t.name), ['Old']);
      await _settle();
      expect(adopted.map((t) => t.name), ['Old', 'New']);
      expect(photos, ['g.png']);
      expect(controller.phase, LinkPhase.ready);
    });

    test('a delay in confirming changes nothing: the app stays open', () async {
      beginReturns(LinkStart.cached(_tipper()));
      refreshReturns(const LinkResolution.unavailable('busy'));
      await controller.start(_alice);
      await _settle();
      expect(controller.phase, LinkPhase.ready);
      expect(adopted, hasLength(1));
    });

    test(
      'a refusal while confirming closes the app on the server\'s reason',
      () async {
        beginReturns(LinkStart.cached(_tipper()));
        refreshReturns(
          const LinkResolution.refused(
            'This tipper belongs to another account.',
          ),
        );
        await controller.start(_alice);
        await _settle();
        expect(controller.phase, LinkPhase.refused);
        expect(controller.message, 'This tipper belongs to another account.');
      },
    );

    test('an account that turns out not to be linked any more is told so, not asked for an alias', () async {
      beginReturns(LinkStart.cached(_tipper()));
      refreshReturns(const LinkResolution.needsAlias());
      await controller.start(_alice);
      await _settle();
      expect(controller.phase, LinkPhase.refused);
      expect(controller.message, contains('no longer linked'));
    });

    test('a failure of the confirmation itself is not a verdict', () async {
      beginReturns(LinkStart.cached(_tipper()));
      when(() => service.refreshCached(any())).thenThrow(StateError('boom'));
      await controller.start(_alice);
      await _settle();
      expect(controller.phase, LinkPhase.ready);
    });
  });

  group('with nothing kept', () {
    test('a linked account opens the app and syncs its photo', () async {
      beginReturns(LinkStart.resolved(LinkResolution.linked(_tipper())));
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.ready);
      expect(adopted, hasLength(1));
      expect(photos, ['g.png']);
      verifyNever(() => service.refreshCached(any()));
    });

    test(
      'a guest opens the app with its local tipper, and has no photo to sync',
      () async {
        beginReturns(
          LinkStart.resolved(
            LinkResolution.guest(_tipper(key: null, guest: true)),
          ),
        );
        await controller.start(
          const LinkAccount(uid: 'guest1', isAnonymous: true),
        );
        expect(controller.phase, LinkPhase.ready);
        expect(adopted.single.isAnonymous, true);
        expect(photos, isEmpty);
      },
    );

    test('a new account is asked for an alias', () async {
      beginReturns(const LinkStart.resolved(LinkResolution.needsAlias()));
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.needsAlias);
      expect(adopted, isEmpty);
    });

    test('a new account is told when no new tippers can be added, not asked for an alias', () async {
      controller.dispose();
      controller = make(canCreate: false);
      beginReturns(const LinkStart.resolved(LinkResolution.needsAlias()));
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.refused);
      expect(controller.message, contains('cannot be added right now'));
    });

    test(
      '"not now" offers to try again, and trying again can succeed',
      () async {
        beginReturns(
          const LinkStart.resolved(
            LinkResolution.unavailable('Could not reach the server.'),
          ),
        );
        await controller.start(_alice);
        expect(controller.phase, LinkPhase.unavailable);
        expect(controller.message, 'Could not reach the server.');

        beginReturns(LinkStart.resolved(LinkResolution.linked(_tipper())));
        await controller.retry();
        expect(controller.phase, LinkPhase.ready);
        expect(controller.message, isNull);
        verify(() => service.begin(any())).called(2);
      },
    );

    test('a refusal shows the server\'s reason', () async {
      beginReturns(
        const LinkStart.resolved(
          LinkResolution.refused('More than one tipper matches your email.'),
        ),
      );
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.refused);
      expect(controller.message, 'More than one tipper matches your email.');
    });

    test('a failure of linking itself is reported, not thrown', () async {
      when(() => service.begin(any())).thenThrow(StateError('boom'));
      await controller.start(_alice);
      expect(controller.phase, LinkPhase.refused);
      expect(controller.message, contains('Something went wrong'));
    });
  });

  group('choosing an alias', () {
    setUp(() async {
      beginReturns(const LinkStart.resolved(LinkResolution.needsAlias()));
      await controller.start(_alice);
    });

    test('an accepted alias opens the app', () async {
      when(() => service.createWithAlias(any(), 'The Oracle')).thenAnswer(
        (_) async => LinkResolution.linked(_tipper(name: 'The Oracle')),
      );
      expect(await controller.submitAlias('The Oracle'), true);
      expect(controller.phase, LinkPhase.ready);
      expect(adopted.single.name, 'The Oracle');
      expect(photos, ['g.png']);
    });

    test('a refused alias stays in the dialog with the reason', () async {
      when(() => service.createWithAlias(any(), any())).thenAnswer(
        (_) async => const LinkResolution.refused(
          'That alias is already taken.',
          reason: 'alias_taken',
        ),
      );
      expect(await controller.submitAlias('Taken'), false);
      expect(controller.phase, LinkPhase.needsAlias);
      expect(controller.aliasError, 'That alias is already taken.');
      expect(adopted, isEmpty);
    });

    test('"not now" while creating also stays in the dialog', () async {
      when(() => service.createWithAlias(any(), any())).thenAnswer(
        (_) async => const LinkResolution.unavailable('Try again shortly.'),
      );
      expect(await controller.submitAlias('x'), false);
      expect(controller.phase, LinkPhase.needsAlias);
      expect(controller.aliasError, 'Try again shortly.');
    });

    test('a new attempt clears the old error', () async {
      when(() => service.createWithAlias(any(), 'bad'))
          .thenAnswer((_) async => const LinkResolution.refused('Taken'));
      await controller.submitAlias('bad');
      expect(controller.aliasError, 'Taken');
      when(() => service.createWithAlias(any(), 'good'))
          .thenAnswer((_) async => LinkResolution.linked(_tipper()));
      await controller.submitAlias('good');
      expect(controller.aliasError, isNull);
    });

    test(
      'a failure of creating is reported in the dialog, not thrown',
      () async {
        when(() => service.createWithAlias(any(), any()))
            .thenThrow(StateError('boom'));
        expect(await controller.submitAlias('x'), false);
        expect(controller.aliasError, contains('Something went wrong'));
      },
    );

    test('an alias submitted when none was asked for is ignored', () async {
      controller.dispose();
      controller = make();
      expect(await controller.submitAlias('x'), false);
      verifyNever(() => service.createWithAlias(any(), any()));
    });
  });

  group('starting', () {
    test('starting again for the same account does nothing', () async {
      beginReturns(LinkStart.resolved(LinkResolution.linked(_tipper())));
      await controller.start(_alice);
      await controller.start(_alice);
      verify(() => service.begin(any())).called(1);
    });

    test('a different account starts over', () async {
      beginReturns(LinkStart.resolved(LinkResolution.linked(_tipper())));
      await controller.start(_alice);
      beginReturns(const LinkStart.resolved(LinkResolution.needsAlias()));
      await controller.start(
        const LinkAccount(uid: 'uidB', isAnonymous: false),
      );
      expect(controller.phase, LinkPhase.needsAlias);
    });

    test('the page sees "resolving" first', () async {
      beginReturns(LinkStart.resolved(LinkResolution.linked(_tipper())));
      await controller.start(_alice);
      expect(phases.first, LinkPhase.resolving);
      expect(phases.last, LinkPhase.ready);
    });

    test('an answer that arrives after a newer start is ignored', () async {
      final slow = Completer<LinkStart>();
      when(() => service.begin(any())).thenAnswer((_) => slow.future);
      final first = controller.start(_alice);
      beginReturns(
        LinkStart.resolved(LinkResolution.linked(_tipper(name: 'Second'))),
      );
      await controller.start(
        const LinkAccount(uid: 'uidB', isAnonymous: false),
      );
      slow.complete(
        LinkStart.resolved(LinkResolution.linked(_tipper(name: 'First'))),
      );
      await first;
      expect(adopted.map((t) => t.name), ['Second']);
    });

    test(
      'an answer that arrives after the page has gone does nothing',
      () async {
        final slow = Completer<LinkStart>();
        when(() => service.begin(any())).thenAnswer((_) => slow.future);
        final pending = controller.start(_alice);
        controller.dispose();
        slow.complete(LinkStart.resolved(LinkResolution.linked(_tipper())));
        await pending;
        expect(adopted, isEmpty);
        controller = make(); // so the tear-down has something to dispose
      },
    );
  });
}
