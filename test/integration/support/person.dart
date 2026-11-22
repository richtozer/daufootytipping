import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_support.dart';

/// One signed-in person: their account, the app's own services pointed at the
/// real server, and the database as their device sees it under the rules in force.
class Person {
  Person(EmulatorDatabase database, this.account)
    : invoker = HttpIdentityCallableInvoker(account),
      client = database.as(account) {
    identity = IdentityService(invoker);
    resolver = LinkedTipperResolver(
      reads: RestIdentityReads(client),
      identity: identity,
      resolveComps: (_) async => const [],
      retryDelays: const <Duration>[],
    );
  }

  final Account account;
  final HttpIdentityCallableInvoker invoker;
  final ClientDatabase client;
  late final IdentityService identity;
  late final LinkedTipperResolver resolver;

  LinkAccount get link => LinkAccount(uid: account.uid, isAnonymous: false);

  /// Signs in as the app does for a first visit: asked for an alias, then given
  /// a new record. Returns the tipper the app would hold.
  Future<Tipper> signUp(String alias) async {
    final first = await resolver.resolve(link);
    expect(first.status, LinkStatus.needsAlias, reason: 'a new account');
    final created = await resolver.resolve(link, alias: alias);
    expect(created.status, LinkStatus.linked, reason: created.message);
    return created.tipper!;
  }

  /// The tipper record this account is linked to, by a fresh sign-in.
  Future<Tipper> signIn() async {
    final resolution = await resolver.resolve(link);
    expect(resolution.status, LinkStatus.linked, reason: resolution.message);
    return resolution.tipper!;
  }
}
