import * as functions from "firebase-functions/v1";

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

export const tipWrittenBackendScoring = functions.database
  .ref("/AllTips/{compKey}/{tipperId}/{gameKey}")
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

export const officialScoreWrittenBackendScoring = functions.database
  .ref("/DAUCompsGames/{compKey}/{gameKey}")
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

export function buildTipWrittenBackendScoringCommand(
  compKey: string,
  tipperId: string,
  gameKey: string,
  sourceEventId: string,
): BackendScoringCommandPayload {
  const sourcePath = `/AllTips/${compKey}/${tipperId}/${gameKey}`;
  return {
    commandType: "tipWritten",
    compKey,
    tipperId,
    gameKey,
    sourceEventId,
    sourcePath,
    scopeKey: `comp:${compKey}/game:${gameKey}/tipper:${tipperId}`,
    commandId: sourceEventId,
  };
}

export function buildOfficialScoreWrittenBackendScoringCommand(
  compKey: string,
  gameKey: string,
  sourceEventId: string,
): BackendScoringCommandPayload {
  const sourcePath = `/DAUCompsGames/${compKey}/${gameKey}`;
  return {
    commandType: "officialScoreWritten",
    compKey,
    gameKey,
    sourceEventId,
    sourcePath,
    scopeKey: `comp:${compKey}/game:${gameKey}`,
    commandId: sourceEventId,
  };
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

function isNoopWrite(change: TipWriteChangeLike): boolean {
  const beforeExists = change.before.exists();
  const afterExists = change.after.exists();
  if (!beforeExists || !afterExists) {
    return false;
  }

  return stringifySnapshot(change.before.val()) ===
    stringifySnapshot(change.after.val());
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
  const current = raw.current != null && typeof raw.current === "object"
    ? raw.current as Record<string, unknown>
    : raw;
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
  const commandUrl = resolveBackendScoringCommandUrl(deps.commandUrl);
  if (commandUrl == null) {
    logger.error(
      "backendScoring tipWritten: missing command URL configuration",
    );
    return "permanentFailure";
  }

  const commandSecret = resolveBackendScoringCommandSecret(deps.commandSecret);
  if (commandSecret == null) {
    logger.error(
      "backendScoring tipWritten: missing command secret configuration",
    );
    return "permanentFailure";
  }

  const fetchImpl = deps.fetchImpl ?? globalThis.fetch?.bind(globalThis);
  if (fetchImpl == null) {
    logger.error("backendScoring tipWritten: fetch is not available");
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
    `backendScoring tipWritten: worker responded with ${response.status}: ${responseText}`;

  if (response.status >= 500) {
    throw new Error(message);
  }

  logger.warn(message);
  return "permanentFailure";
}

function resolveBackendScoringCommandUrl(
  overrideUrl?: string,
): string | null {
  if (overrideUrl != null && overrideUrl.trim().length > 0) {
    return overrideUrl.trim();
  }

  for (const envKey of DEFAULT_COMMAND_URL_ENV_KEYS) {
    const value = process.env[envKey];
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
    logger?.error(`backendScoring tipWritten: missing context param ${key}`);
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
): string | null {
  if (overrideSecret != null && overrideSecret.trim().length > 0) {
    return overrideSecret.trim();
  }

  for (const envKey of DEFAULT_COMMAND_SECRET_ENV_KEYS) {
    const value = process.env[envKey];
    if (value != null && value.trim().length > 0) {
      return value.trim();
    }
  }

  return null;
}
