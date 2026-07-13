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

/// Other RTDB roots.
const String tokensPath = '/AllTippersTokens';
const String tippersPath = '/AllTippers';
const String teamsPathRoot = '/Teams';
const String gamesPathRoot = '/DAUCompsGames';
const String configPathRoot = '/AppConfig';
const String tipsPathRoot = '/AllTips';
const String statsPathRoot = '/Stats';

/// Legacy/client-owned scoring branches under [statsPathRoot].
const String roundStatsLegacyRoot = 'round_stats_v3';
const String gameStatsLegacyRoot = 'game_stats_v3';
const String liveScoresLegacyRoot = 'live_scores_v3';

/// Backend-owned scoring shadow branches under [statsPathRoot].
///
/// Keep these versioned independently. Do not assume that bumping one backend
/// branch version implies bumping all backend scoring branches.
const String roundStatsBackendRoot = 'round_stats_backend_v1';
const String gameStatsBackendRoot = 'game_stats_backend_v1';
const String liveScoresBackendRoot = 'live_scores_backend_v1';
const String scoringIdempotencyBackendRoot = 'scoring_idempotency_backend_v1';
const String scoringStatusKey = 'scoring_status';

/// App config keys under [configPathRoot].
const String currentDAUCompKey = 'currentDAUComp';
const String minAppVersionKey = 'minAppVersion';
const String createLinkedTipperKey = 'createLinkedTipper';
const String googleClientIdKey = 'googleClientId';
const String cloudFunctionsBaseURLKey = 'cloudFunctionsBaseURL';
const String useBackendScoringBranchesKey = 'useBackendScoringBranches';
