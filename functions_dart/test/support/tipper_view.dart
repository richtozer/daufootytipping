import 'package:dau_shared/dau_shared.dart';

/// Everything about a tipper that the backend can see, as comparable data.
Map<String, Object?> tipperView(Tipper tipper) => {
  'dbkey': tipper.dbkey,
  'name': tipper.name,
  'photoURL': tipper.photoURL,
  'authuid': tipper.authuid,
  'email': tipper.email,
  'logon': tipper.logon,
  'tipperRole': tipper.tipperRole,
  'isAnonymous': tipper.isAnonymous,
  'acctCreatedUTC': tipper.acctCreatedUTC,
  'acctLoggedOnUTC': tipper.acctLoggedOnUTC,
  'compsPaidFor': [for (final comp in tipper.compsPaidFor) comp.dbkey],
};
