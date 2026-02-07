// Centralized app path constants to avoid magic strings.
// Keep all Firebase RTDB keys/paths here for single-source-of-truth.

/// Root path for all DAU competitions in RTDB.
const String daucompsPath = '/AllDAUComps';

/// Key under a DAU comp where combined rounds are stored.
const String combinedRoundsPath = 'combinedRounds2';

/// Suffix/key used for per-comp download locks.
const String downloadLockKey = 'downloadLock';

/// Per-round field: start date key.
const String roundStartDateKey = 'roundStartDate';

/// Per-round field: end date key.
const String roundEndDateKey = 'roundEndDate';

/// Admin override date keys per round.
const String adminOverrideRoundStartDateKey = 'adminOverrideRoundStartDate';
const String adminOverrideRoundEndDateKey = 'adminOverrideRoundEndDate';

/// DAUComp field keys.
const String compNameKey = 'name';
const String aflFixtureJsonURLKey = 'aflFixtureJsonURL';
const String nrlFixtureJsonURLKey = 'nrlFixtureJsonURL';
const String lastFixtureUTCKey = 'lastFixtureUTC';
const String aflRegularCompEndDateUTCKey = 'aflRegularCompEndDateUTC';
const String nrlRegularCompEndDateUTCKey = 'nrlRegularCompEndDateUTC';
const String aflFixtureBaselineKey = 'aflFixtureBaseline';
const String nrlFixtureBaselineKey = 'nrlFixtureBaseline';

/// Other RTDB roots.
const String tokensPath = '/AllTippersTokens';
const String tippersPath = '/AllTippers';
const String teamsPathRoot = '/Teams';
const String gamesPathRoot = '/DAUCompsGames';
const String configPathRoot = '/AppConfig';
const String tipsPathRoot = '/AllTips';
const String statsPathRoot = '/Stats';

/// App config keys under [configPathRoot].
const String currentDAUCompKey = 'currentDAUComp';
const String minAppVersionKey = 'minAppVersion';
const String createLinkedTipperKey = 'createLinkedTipper';
const String googleClientIdKey = 'googleClientId';
