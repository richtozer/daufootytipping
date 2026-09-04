import * as functions from "firebase-functions/v1";
import {resolveLocalDartFunctionUrl} from "./local_emulator_functions";

export type BackendScoringCommandType =
  | "tipWritten"
  | "officialScoreWritten"
  | "liveScoreWritten"
  | "adminRescore";

export interface BackendScoringCommandPayload {
  commandType: BackendScoringCommandType;
  compKey: string;
  roundNumber?: number;
  tipperId?: string;
  gameKey?: string;
  sourceEventId: string;
  sourcePath: string;
  scopeKey: string;
  commandId: string;
}

export interface TipWriteSnapshotLike {
  exists(): boolean;
  val(): unknown;
}

export interface TipWriteChangeLike {
  before: TipWriteSnapshotLike;
  after: TipWriteSnapshotLike;
}

export interface TipWriteContextLike {
  eventId: string;
  params: Record<string, string | undefined>;
}

export interface BackendScoringDatabaseLike {
  ref(path: string): BackendScoringDatabaseReferenceLike;
}

export interface BackendScoringDatabaseReferenceLike {
  once(eventType: "value"): Promise<{ val(): unknown }>;
}

export interface BackendScoringFetchResponseLike {
  ok: boolean;
  status: number;
  text(): Promise<string>;
}

export type BackendScoringFetchLike = (
  url: string,
  init: {
    method: "POST";
    headers: Record<string, string>;
    body: string;
  },
) => Promise<BackendScoringFetchResponseLike>;

export interface BackendScoringCommandLoggerLike {
  log(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

export interface TipWrittenBackendScoringDependencies {
  fetchImpl?: BackendScoringFetchLike;
  commandUrl?: string;
  commandSecret?: string;
  logger?: BackendScoringCommandLoggerLike;
  environment?: Record<string, string | undefined>;
}

type BackendScoringDispatchOutcome = "success" | "permanentFailure";

const DEFAULT_COMMAND_URL_ENV_KEYS = [
  "BACKEND_SCORING_COMMAND_URL",
  "DART_BACKEND_SCORING_COMMAND_URL",
];

const DEFAULT_COMMAND_SECRET_ENV_KEYS = [
  "BACKEND_SCORING_COMMAND_SECRET",
  "DART_BACKEND_SCORING_COMMAND_SECRET",
];

const BACKEND_SCORING_COMMAND_SECRET_HEADER = "x-backend-scoring-secret";
const STATS_PATH_ROOT = "/Stats";
const TIPS_PATH_ROOT = "/AllTips";
const GAMES_PATH_ROOT = "/DAUCompsGames";
const LIVE_SCORES_BACKEND_ROOT = "live_scores_backend_v1";
const LIVE_SCORE_CURRENT_KEY = "current";
const LIVE_SCORE_CURRENT_TRIGGER_PATH =
  `${STATS_PATH_ROOT}/{compKey}/${LIVE_SCORES_BACKEND_ROOT}/{gameKey}/` +
  LIVE_SCORE_CURRENT_KEY;
const BACKEND_SCORING_REGION = "asia-southeast1";
const backendScoringFunctions = functions.region(BACKEND_SCORING_REGION);
const backendScoringDatabase = backendScoringFunctions.database;

export const tipWrittenBackendScoring = backendScoringDatabase
  .ref(`${TIPS_PATH_ROOT}/{compKey}/{tipperId}/{gameKey}`)
  .onWrite(
    async (
      change: functions.Change<functions.database.DataSnapshot>,
      context: functions.EventContext<Record<string, string>>,
    ) => {
      await handleTipWrittenBackendScoringWrite(
        change as TipWriteChangeLike,
        {
          eventId: context.eventId,
          params: context.params,
        },
      );
    },
  );

export const officialScoreWrittenBackendScoring = backendScoringDatabase
  .ref(`${GAMES_PATH_ROOT}/{compKey}/{gameKey}`)
  .onWrite(
    async (
      change: functions.Change<functions.database.DataSnapshot>,
      context: functions.EventContext<Record<string, string>>,
    ) => {
      await handleOfficialScoreWrittenBackendScoringWrite(
        change as TipWriteChangeLike,
        {
          eventId: context.eventId,
          params: context.params,
        },
      );
    },
  );

export const liveScoreWrittenBackendScoring = backendScoringDatabase
  .ref(LIVE_SCORE_CURRENT_TRIGGER_PATH)
  .onWrite(
    async (
      change: functions.Change<functions.database.DataSnapshot>,
      context: functions.EventContext<Record<string, string>>,
    ) => {
      await handleLiveScoreWrittenBackendScoringWrite(
        change as TipWriteChangeLike,
        {
          eventId: context.eventId,
          params: context.params,
        },
      );
    },
  );

export function buildTipWrittenBackendScoringCommand(
  compKey: string,
  tipperId: string,
  gameKey: string,
  sourceEventId: string,
): BackendScoringCommandPayload {
  const sourcePath = `${TIPS_PATH_ROOT}/${compKey}/${tipperId}/${gameKey}`;
  const commandId = buildBackendScoringCommandId(sourceEventId);
  return {
    commandType: "tipWritten",
    compKey,
    tipperId,
    gameKey,
    sourceEventId,
    sourcePath,
    scopeKey: `comp:${compKey}/game:${gameKey}/tipper:${tipperId}`,
    commandId,
  };
}

export function buildOfficialScoreWrittenBackendScoringCommand(
  compKey: string,
  gameKey: string,
  sourceEventId: string,
): BackendScoringCommandPayload {
  const sourcePath = `${GAMES_PATH_ROOT}/${compKey}/${gameKey}`;
  const commandId = buildBackendScoringCommandId(sourceEventId);
  return {
    commandType: "officialScoreWritten",
    compKey,
    gameKey,
    sourceEventId,
    sourcePath,
    scopeKey: `comp:${compKey}/game:${gameKey}`,
    commandId,
  };
}

/**
 * Builds the backend scoring command for a live score current snapshot write.
 *
 * @param {string} compKey Competition key from the RTDB trigger path.
 * @param {string} gameKey Game key from the RTDB trigger path.
 * @param {string} sourceEventId Firebase event id for idempotency.
 * @return {BackendScoringCommandPayload} Compact Dart worker command payload.
 */
export function buildLiveScoreWrittenBackendScoringCommand(
  compKey: string,
  gameKey: string,
  sourceEventId: string,
): BackendScoringCommandPayload {
  const sourcePath =
    `${STATS_PATH_ROOT}/${compKey}/${LIVE_SCORES_BACKEND_ROOT}/${gameKey}/` +
    LIVE_SCORE_CURRENT_KEY;
  const commandId = buildBackendScoringCommandId(sourceEventId);
  return {
    commandType: "liveScoreWritten",
    compKey,
    gameKey,
    sourceEventId,
    sourcePath,
    scopeKey: `comp:${compKey}/game:${gameKey}`,
    commandId,
  };
}

export function buildBackendScoringCommandId(sourceEventId: string): string {
  return `event_${Buffer.from(sourceEventId, "utf8").toString("base64url")}`;
}

export async function handleTipWrittenBackendScoringWrite(
  change: TipWriteChangeLike,
  context: TipWriteContextLike,
  deps: TipWrittenBackendScoringDependencies = {},
): Promise<void> {
  const logger = deps.logger ?? functions.logger;

  if (isNoopWrite(change)) {
    return;
  }

  const compKey = requiredContextParam(context, "compKey", logger);
  const tipperId = requiredContextParam(context, "tipperId", logger);
  const gameKey = requiredContextParam(context, "gameKey", logger);
  if (compKey == null || tipperId == null || gameKey == null) {
    return;
  }

  const command = buildTipWrittenBackendScoringCommand(
    compKey,
    tipperId,
    gameKey,
    context.eventId,
  );

  const outcome = await dispatchBackendScoringCommand(command, deps);
  if (outcome === "permanentFailure") {
    return;
  }
}

export async function handleOfficialScoreWrittenBackendScoringWrite(
  change: TipWriteChangeLike,
  context: TipWriteContextLike,
  deps: TipWrittenBackendScoringDependencies = {},
): Promise<void> {
  const logger = deps.logger ?? functions.logger;

  if (!isOfficialScoreWrite(change)) {
    return;
  }

  const compKey = requiredContextParam(context, "compKey", logger);
  const gameKey = requiredContextParam(context, "gameKey", logger);
  if (compKey == null || gameKey == null) {
    return;
  }

  const command = buildOfficialScoreWrittenBackendScoringCommand(
    compKey,
    gameKey,
    context.eventId,
  );

  const outcome = await dispatchBackendScoringCommand(command, deps);
  if (outcome === "permanentFailure") {
    return;
  }
}

/**
 * Dispatches backend scoring for live score current snapshot writes.
 *
 * @param {TipWriteChangeLike} change RTDB before/after snapshot pair.
 * @param {TipWriteContextLike} context RTDB event context.
 * @param {TipWrittenBackendScoringDependencies} deps Injectable test deps.
 * @return {Promise<void>} Resolves once the command is handled or skipped.
 */
export async function handleLiveScoreWrittenBackendScoringWrite(
  change: TipWriteChangeLike,
  context: TipWriteContextLike,
  deps: TipWrittenBackendScoringDependencies = {},
): Promise<void> {
  const logger = deps.logger ?? functions.logger;

  if (!isLiveScoreMaterialWrite(change)) {
    return;
  }

  const compKey = requiredContextParam(context, "compKey", logger);
  const gameKey = requiredContextParam(context, "gameKey", logger);
  if (compKey == null || gameKey == null) {
    return;
  }

  const command = buildLiveScoreWrittenBackendScoringCommand(
    compKey,
    gameKey,
    context.eventId,
  );

  const outcome = await dispatchBackendScoringCommand(command, deps);
  if (outcome === "permanentFailure") {
    return;
  }
}

function isNoopWrite(change: TipWriteChangeLike): boolean {
  const beforeExists = change.before.exists();
  const afterExists = change.after.exists();
  if (!beforeExists || !afterExists) {
    return false;
  }

  return stringifySnapshot(change.before.val()) ===
    stringifySnapshot(change.after.val());
}

function isLiveScoreMaterialWrite(change: TipWriteChangeLike): boolean {
  const beforeMaterial = extractLiveScoreMaterial(change.before.val());
  const afterMaterial = extractLiveScoreMaterial(change.after.val());
  const beforeHasScore = hasLiveScoreMaterial(beforeMaterial);
  const afterHasScore = hasLiveScoreMaterial(afterMaterial);

  if (!change.before.exists() || !change.after.exists()) {
    return beforeHasScore || afterHasScore;
  }

  if (!beforeHasScore && !afterHasScore) {
    return false;
  }

  return beforeMaterial.homeInterimScore !== afterMaterial.homeInterimScore ||
    beforeMaterial.awayInterimScore !== afterMaterial.awayInterimScore ||
    beforeMaterial.gameComplete !== afterMaterial.gameComplete;
}

function extractLiveScoreMaterial(
  value: unknown,
): {
  homeInterimScore: string | null;
  awayInterimScore: string | null;
  gameComplete: boolean | null;
} {
  if (value == null || typeof value !== "object") {
    return {
      homeInterimScore: null,
      awayInterimScore: null,
      gameComplete: null,
    };
  }

  const raw = value as Record<string, unknown>;
  return {
    homeInterimScore: normalizeLiveScoreValue(raw.homeInterimScore),
    awayInterimScore: normalizeLiveScoreValue(raw.awayInterimScore),
    gameComplete: typeof raw.gameComplete === "boolean" ?
      raw.gameComplete :
      null,
  };
}

function hasLiveScoreMaterial(
  material: {
    homeInterimScore: string | null;
    awayInterimScore: string | null;
    gameComplete: boolean | null;
  },
): boolean {
  return material.homeInterimScore != null ||
    material.awayInterimScore != null ||
    material.gameComplete != null;
}

function normalizeLiveScoreValue(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value.toString();
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const numericValue = Number(value);
    return Number.isFinite(numericValue) ? numericValue.toString() : value;
  }
  return null;
}

function isOfficialScoreWrite(change: TipWriteChangeLike): boolean {
  const beforeScores = extractOfficialScores(change.before.val());
  const afterScores = extractOfficialScores(change.after.val());

  if (!change.before.exists() || !change.after.exists()) {
    return afterScores.homeTeamScore != null ||
      afterScores.awayTeamScore != null;
  }

  return beforeScores.homeTeamScore !== afterScores.homeTeamScore ||
    beforeScores.awayTeamScore !== afterScores.awayTeamScore;
}

function extractOfficialScores(
  value: unknown,
): {homeTeamScore: unknown; awayTeamScore: unknown} {
  if (value == null || typeof value !== "object") {
    return {homeTeamScore: null, awayTeamScore: null};
  }

  const raw = value as Record<string, unknown>;
  const current = raw.current != null && typeof raw.current === "object" ?
    raw.current as Record<string, unknown> :
    raw;
  return {
    homeTeamScore: current.HomeTeamScore ?? current.homeTeamScore ?? null,
    awayTeamScore: current.AwayTeamScore ?? current.awayTeamScore ?? null,
  };
}

async function dispatchBackendScoringCommand(
  command: BackendScoringCommandPayload,
  deps: TipWrittenBackendScoringDependencies,
): Promise<BackendScoringDispatchOutcome> {
  const logger = deps.logger ?? functions.logger;
  const environment = deps.environment ?? process.env;
  const commandUrl = resolveBackendScoringCommandUrl(
    deps.commandUrl,
    environment,
  );
  if (commandUrl == null) {
    logger.error(
      "backendScoring command: missing command URL configuration",
    );
    return "permanentFailure";
  }

  const commandSecret = resolveBackendScoringCommandSecret(
    deps.commandSecret,
    environment,
  );
  if (commandSecret == null) {
    logger.error(
      "backendScoring command: missing command secret configuration",
    );
    return "permanentFailure";
  }

  const fetchImpl = deps.fetchImpl ?? globalThis.fetch?.bind(globalThis);
  if (fetchImpl == null) {
    logger.error("backendScoring command: fetch is not available");
    return "permanentFailure";
  }

  const response = await fetchImpl(commandUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      [BACKEND_SCORING_COMMAND_SECRET_HEADER]: commandSecret,
    },
    body: JSON.stringify({
      command,
    }),
  });

  if (response.ok) {
    return "success";
  }

  const responseText = await response.text().catch(() => "");
  const message =
    `backendScoring command: worker responded with ${response.status}: ` +
    responseText;

  if (response.status >= 500) {
    throw new Error(message);
  }

  logger.warn(message);
  return "permanentFailure";
}

export function resolveBackendScoringCommandUrl(
  overrideUrl?: string,
  environment: Record<string, string | undefined> = process.env,
): string | null {
  if (overrideUrl != null && overrideUrl.trim().length > 0) {
    return overrideUrl.trim();
  }

  // Deployed Dart endpoint id. Mirrors backendScoringCommandEndpoint in
  // packages/dau_shared/lib/constants/function_endpoints.dart - TypeScript
  // cannot import it, so keep these in sync by hand.
  const localEmulatorUrl = resolveLocalDartFunctionUrl(
    "backend-scoring-command",
    environment,
  );
  if (localEmulatorUrl != null) {
    return localEmulatorUrl;
  }

  for (const envKey of DEFAULT_COMMAND_URL_ENV_KEYS) {
    const value = environment[envKey];
    if (value != null && value.trim().length > 0) {
      return value.trim();
    }
  }

  return null;
}

function requiredContextParam(
  context: TipWriteContextLike,
  key: "compKey" | "tipperId" | "gameKey",
  logger?: BackendScoringCommandLoggerLike,
): string | null {
  const value = context.params[key];
  if (value == null || value.trim().length === 0) {
    logger?.error(`backendScoring command: missing context param ${key}`);
    return null;
  }

  return value;
}

function stringifySnapshot(value: unknown): string {
  if (value == null) {
    return "";
  }

  return JSON.stringify(value);
}

function resolveBackendScoringCommandSecret(
  overrideSecret?: string,
  environment: Record<string, string | undefined> = process.env,
): string | null {
  if (overrideSecret != null && overrideSecret.trim().length > 0) {
    return overrideSecret.trim();
  }

  for (const envKey of DEFAULT_COMMAND_SECRET_ENV_KEYS) {
    const value = environment[envKey];
    if (value != null && value.trim().length > 0) {
      return value.trim();
    }
  }

  return null;
}
