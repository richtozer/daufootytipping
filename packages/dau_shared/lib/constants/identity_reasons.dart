// Machine-readable reasons the identity callables give for a refusal, so the
// client can show the right message without parsing text. They travel in the
// error's `details` (an `ErrorInfo` entry), and are a WIRE CONTRACT with the
// R2 client: add to the list, never rename.

/// The identity callables are switched off, or the caller is not a pilot user.
const String identityReasonNotAvailable = 'not_available';

/// A migration step is in progress; try again shortly.
const String identityReasonUnavailable = 'unavailable';

/// Another change to this tipper is in progress; try again.
const String identityReasonBusy = 'busy';

/// The signed-in account's email is not verified.
const String identityReasonUnverifiedEmail = 'unverified_email';

/// More than one tipper record matches this account.
const String identityReasonAmbiguous = 'ambiguous';

/// The matching record belongs to another account, or its ownership cannot be
/// established.
const String identityReasonClaimed = 'claimed';

/// A matching record has not been audited yet (it was created after the last
/// backfill); an administrator must have it audited.
const String identityReasonNeedsAudit = 'needs_audit';

/// Another tipper already has this alias.
const String identityReasonAliasTaken = 'alias_taken';

/// The alias is blank, too long, or only symbols.
const String identityReasonInvalidAlias = 'invalid_alias';

/// No tipper matches and creating new ones is switched off.
const String identityReasonCreationDisabled = 'creation_disabled';

/// The signed-in account is not linked to a tipper.
const String identityReasonNotLinked = 'not_linked';

/// The device token is not acceptable.
const String identityReasonInvalidToken = 'invalid_token';

/// The error `domain` used in every `ErrorInfo` detail.
const String identityErrorDomain = 'dau-footy-tipping';
