import * as functions from "firebase-functions/v1";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {getDatabase} from "firebase-admin/database";
import {getMessaging, Message, Messaging} from "firebase-admin/messaging";
import {resolveLocalDartFunctionUrl} from "./local_emulator_functions";

interface SnapshotLike {
  exists(): boolean;
  val(): unknown;
}

interface ChangeLike {
  before: SnapshotLike;
  after: SnapshotLike;
}

interface ContextLike {
  params: Record<string, string | undefined>;
}

interface ReferenceLike {
  once(eventType: "value"): Promise<SnapshotLike>;
  remove(): Promise<unknown>;
}

interface DatabaseLike {
  ref(path: string): ReferenceLike;
}

interface LoggerLike {
  log(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

interface FetchResponseLike {
  ok: boolean;
  status: number;
  text(): Promise<string>;
  json(): Promise<unknown>;
}

type FetchLike = (
  url: string,
  init: {
    method: "POST";
    headers: Record<string, string>;
    body: string;
  },
) => Promise<FetchResponseLike>;

interface MessagingLike {
  sendEach(messages: Message[]): Promise<{
    responses: Array<{
      success: boolean;
      error?: { code?: string };
    }>;
  }>;
}

export interface AppBadgeDependencies {
  db?: DatabaseLike;
  messaging?: MessagingLike;
  fetchImpl?: FetchLike;
  commandUrl?: string;
  commandSecret?: string;
  environment?: Record<string, string | undefined>;
  logger?: LoggerLike;
  now?: Date;
}

interface BadgeCountResponse {
  compKey: string;
  calculatedAt: string;
  counts: Record<string, number>;
}

const REGION = "asia-southeast1";
const TIPS_PATH = "/AllTips";
const TIPPERS_PATH = "/AllTippers";
const TOKENS_PATH = "/AllTippersTokens";
const GAMES_PATH = "/DAUCompsGames";
const COMPS_PATH = "/AllDAUComps";
const COMBINED_ROUNDS_PATH = "combinedRounds2";
const CURRENT_COMP_PATH = "/AppConfig/currentDAUComp";
const ENABLED_PATH = "/AppConfig/outstandingTipsPushEnabled";
const COMMAND_SECRET_HEADER = "x-app-badge-secret";
const MESSAGE_TYPE = "outstanding_tips_badge";
const COLLAPSE_ID = "outstanding-tips-badge";
const MAX_FCM_BATCH_SIZE = 500;
const COMMAND_URL_ENV_KEYS = [
  "APP_BADGE_COUNT_URL",
  "DART_APP_BADGE_COUNT_URL",
];
const COMMAND_SECRET_ENV_KEYS = [
  "APP_BADGE_COMMAND_SECRET",
  "DART_APP_BADGE_COMMAND_SECRET",
];
const PERMANENT_TOKEN_ERRORS = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

const appBadgeFunctions = functions.region(REGION);

export const tipWrittenAppBadge = appBadgeFunctions.database
  .ref(`${TIPS_PATH}/{compKey}/{tipperId}/{gameKey}`)
  .onWrite(async (change, context) => {
    await handleTipWrittenAppBadge(change, context);
  });

export const tipperWrittenAppBadge = appBadgeFunctions.database
  .ref(`${TIPPERS_PATH}/{tipperId}`)
  .onWrite(async (change, context) => {
    await handleTipperWrittenAppBadge(change, context);
  });

export const tipperTokenCreatedAppBadge = appBadgeFunctions.database
  .ref(`${TOKENS_PATH}/{tipperId}/{token}`)
  .onCreate(async (snapshot, context) => {
    await handleTipperTokenCreatedAppBadge(snapshot, context);
  });

export const kickoffOutstandingTipsAppBadge = onSchedule(
  {schedule: "* * * * *", timeZone: "UTC", region: REGION},
  async () => {
    await handleKickoffAppBadgeSweep();
  },
);

export const reconcileOutstandingTipsAppBadge = onSchedule(
  {schedule: "15 * * * *", timeZone: "UTC", region: REGION},
  async () => {
    await handleAppBadgeReconciliation();
  },
);

export async function handleTipWrittenAppBadge(
  change: ChangeLike,
  context: ContextLike,
  deps: AppBadgeDependencies = {},
): Promise<void> {
  if (sameSnapshotValue(change.before, change.after)) return;
  const compKey = context.params.compKey;
  const tipperId = context.params.tipperId;
  if (compKey == null || tipperId == null) return;
  if (await currentCompKey(deps) !== compKey) return;
  await syncAppBadges(compKey, [tipperId], deps);
}

export async function handleTipperWrittenAppBadge(
  change: ChangeLike,
  context: ContextLike,
  deps: AppBadgeDependencies = {},
): Promise<void> {
  if (!tipperEligibilityChanged(
    change.before.val(),
    change.after.val(),
  )) return;
  const tipperId = context.params.tipperId;
  if (tipperId == null) return;
  const compKey = await currentCompKey(deps);
  if (compKey != null) await syncAppBadges(compKey, [tipperId], deps);
}

export async function handleTipperTokenCreatedAppBadge(
  _snapshot: SnapshotLike,
  context: ContextLike,
  deps: AppBadgeDependencies = {},
): Promise<void> {
  const tipperId = context.params.tipperId;
  const token = context.params.token;
  if (tipperId == null || token == null) return;
  const compKey = await currentCompKey(deps);
  if (compKey != null) {
    await syncAppBadges(compKey, [tipperId], deps, {tipperId, token});
  }
}

export async function handleKickoffAppBadgeSweep(
  deps: AppBadgeDependencies = {},
): Promise<void> {
  if (!await appBadgePushEnabled(deps)) return;
  const compKey = await currentCompKey(deps);
  if (compKey == null) return;
  const reachedKickoff = await hasRecentKickoff(compKey, deps);
  const reachedActivation = reachedKickoff ? false :
    await hasRecentBadgeActivation(compKey, deps);
  if (!reachedKickoff && !reachedActivation) return;
  await syncAppBadges(compKey, undefined, deps, undefined, true);
}

export async function handleAppBadgeReconciliation(
  deps: AppBadgeDependencies = {},
): Promise<void> {
  const compKey = await currentCompKey(deps);
  if (compKey != null) await syncAppBadges(compKey, undefined, deps);
}

export async function syncAppBadges(
  compKey: string,
  tipperIds: string[] | undefined,
  deps: AppBadgeDependencies = {},
  tokenOverride?: {tipperId: string; token: string},
  alreadyEnabled = false,
): Promise<void> {
  const logger = deps.logger ?? functions.logger;
  if (!alreadyEnabled && !await appBadgePushEnabled(deps)) return;
  const result = await requestBadgeCounts(compKey, tipperIds, deps);
  const messages: Message[] = [];
  const messageOwners: Array<{tipperId: string; token: string}> = [];
  const bulkTokens = tokenOverride == null && tipperIds == null ?
    await allTokensByTipper(deps) : null;

  for (const [tipperId, count] of Object.entries(result.counts)) {
    let tokens: string[];
    if (tokenOverride?.tipperId === tipperId) {
      tokens = [tokenOverride.token];
    } else if (bulkTokens != null) {
      tokens = bulkTokens[tipperId] ?? [];
    } else {
      tokens = await tokensForTipper(tipperId, deps);
    }
    for (const token of tokens) {
      messages.push(buildOutstandingTipsBadgeMessage(
        token,
        count,
        result.calculatedAt,
      ));
      messageOwners.push({tipperId, token});
    }
  }

  if (messages.length === 0) {
    logger.log("Outstanding tips badge sync found no registered devices");
    return;
  }
  const messaging = deps.messaging ?? getMessaging();
  for (let offset = 0; offset < messages.length; offset += MAX_FCM_BATCH_SIZE) {
    const batch = messages.slice(offset, offset + MAX_FCM_BATCH_SIZE);
    const owners = messageOwners.slice(offset, offset + MAX_FCM_BATCH_SIZE);
    const response = await messaging.sendEach(batch);
    for (let index = 0; index < response.responses.length; index++) {
      const sendResult = response.responses[index];
      const owner = owners[index];
      if (!sendResult.success && owner != null &&
          PERMANENT_TOKEN_ERRORS.has(sendResult.error?.code ?? "")) {
        await appBadgeDatabase(deps)
          .ref(`${TOKENS_PATH}/${owner.tipperId}/${owner.token}`).remove();
      }
    }
  }
  logger.log(
    `Outstanding tips badge sync sent ${messages.length} device updates`,
  );
}

export function buildOutstandingTipsBadgeMessage(
  token: string,
  count: number,
  calculatedAt: string,
): Message {
  return {
    token,
    data: {
      type: MESSAGE_TYPE,
      count: String(count),
      calculatedAt,
    },
    android: {
      priority: "high",
      collapseKey: COLLAPSE_ID,
      ttl: 60 * 60 * 1000,
    },
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": COLLAPSE_ID,
      },
      payload: {
        aps: {badge: count},
      },
    },
  };
}

export function tipperEligibilityChanged(
  before: unknown,
  after: unknown,
): boolean {
  return JSON.stringify(eligibilityFields(before)) !==
    JSON.stringify(eligibilityFields(after));
}

async function requestBadgeCounts(
  compKey: string,
  tipperIds: string[] | undefined,
  deps: AppBadgeDependencies,
): Promise<BadgeCountResponse> {
  const environment = deps.environment ?? process.env;
  const commandUrl = deps.commandUrl ??
    // Mirrors appBadgeCountEndpoint in
    // packages/dau_shared/lib/constants/function_endpoints.dart - keep in sync.
    resolveLocalDartFunctionUrl("app-badge-count", environment) ??
    firstEnvironmentValue(COMMAND_URL_ENV_KEYS, environment);
  const commandSecret = deps.commandSecret ??
    firstEnvironmentValue(COMMAND_SECRET_ENV_KEYS, environment);
  if (commandUrl == null) {
    throw new Error("App badge count URL is not configured");
  }
  if (commandSecret == null) {
    throw new Error("App badge command secret is not configured");
  }
  const response = await (deps.fetchImpl ?? fetch)(commandUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      [COMMAND_SECRET_HEADER]: commandSecret,
    },
    body: JSON.stringify({compKey, ...(tipperIds == null ? {} : {tipperIds})}),
  });
  if (!response.ok) {
    throw new Error(
      `App badge count failed with HTTP ${response.status}: ` +
      await response.text(),
    );
  }
  const value = await response.json();
  if (!isBadgeCountResponse(value)) {
    throw new Error("App badge count returned an invalid response");
  }
  if (value.compKey !== compKey) {
    throw new Error("App badge count returned the wrong competition");
  }
  return value;
}

async function appBadgePushEnabled(
  deps: AppBadgeDependencies,
): Promise<boolean> {
  const snapshot = await appBadgeDatabase(deps).ref(ENABLED_PATH).once("value");
  return snapshot.val() === true;
}

async function currentCompKey(
  deps: AppBadgeDependencies,
): Promise<string | null> {
  const snapshot = await appBadgeDatabase(deps)
    .ref(CURRENT_COMP_PATH).once("value");
  const value = snapshot.val();
  return typeof value === "string" && value.length > 0 ? value : null;
}

async function tokensForTipper(
  tipperId: string,
  deps: AppBadgeDependencies,
): Promise<string[]> {
  const snapshot = await appBadgeDatabase(deps)
    .ref(`${TOKENS_PATH}/${tipperId}`).once("value");
  const value = snapshot.val();
  return isRecord(value) ? Object.keys(value) : [];
}

async function allTokensByTipper(
  deps: AppBadgeDependencies,
): Promise<Record<string, string[]>> {
  const snapshot = await appBadgeDatabase(deps).ref(TOKENS_PATH).once("value");
  const value = snapshot.val();
  if (!isRecord(value)) return {};
  const result: Record<string, string[]> = {};
  for (const [tipperId, rawTokens] of Object.entries(value)) {
    result[tipperId] = isRecord(rawTokens) ? Object.keys(rawTokens) : [];
  }
  return result;
}

async function hasRecentKickoff(
  compKey: string,
  deps: AppBadgeDependencies,
): Promise<boolean> {
  const snapshot = await appBadgeDatabase(deps)
    .ref(`${GAMES_PATH}/${compKey}`).once("value");
  const games = snapshot.val();
  if (!isRecord(games)) return false;
  const nowMs = (deps.now ?? new Date()).getTime();
  const windowStartMs = nowMs - 2 * 60 * 1000;
  return Object.values(games).some((game) => {
    if (!isRecord(game) || typeof game.DateUtc !== "string") return false;
    const kickoffMs = Date.parse(game.DateUtc);
    return Number.isFinite(kickoffMs) &&
      kickoffMs > windowStartMs && kickoffMs <= nowMs;
  });
}

async function hasRecentBadgeActivation(
  compKey: string,
  deps: AppBadgeDependencies,
): Promise<boolean> {
  const snapshot = await appBadgeDatabase(deps)
    .ref(`${COMPS_PATH}/${compKey}/${COMBINED_ROUNDS_PATH}`).once("value");
  const rounds = snapshot.val();
  const rawRounds = Array.isArray(rounds) ? rounds :
    isRecord(rounds) ? Object.values(rounds) : [];
  const nowMs = (deps.now ?? new Date()).getTime();
  const windowStartMs = nowMs - 2 * 60 * 1000;
  const activationLeadMs = 48 * 60 * 60 * 1000;
  return rawRounds.some((round) => {
    if (!isRecord(round) || typeof round.roundStartDate !== "string") {
      return false;
    }
    const firstKickoffMs = Date.parse(round.roundStartDate);
    const activationMs = firstKickoffMs - activationLeadMs;
    return Number.isFinite(activationMs) &&
      activationMs > windowStartMs && activationMs <= nowMs;
  });
}

function eligibilityFields(value: unknown): unknown {
  if (!isRecord(value)) return null;
  return {
    isAnonymous: value.isAnonymous === true,
    compsParticipatedIn: value.compsParticipatedIn ?? null,
  };
}

function sameSnapshotValue(before: SnapshotLike, after: SnapshotLike): boolean {
  return before.exists() === after.exists() &&
    JSON.stringify(before.val()) === JSON.stringify(after.val());
}

function appBadgeDatabase(deps: AppBadgeDependencies): DatabaseLike {
  return deps.db ?? getDatabase();
}

function firstEnvironmentValue(
  keys: string[],
  environment: Record<string, string | undefined>,
): string | undefined {
  return keys.map((key) => environment[key]).find(
    (value) => value != null && value.length > 0,
  );
}

function isBadgeCountResponse(value: unknown): value is BadgeCountResponse {
  if (!isRecord(value) || typeof value.compKey !== "string" ||
      typeof value.calculatedAt !== "string" || !isRecord(value.counts)) {
    return false;
  }
  return Object.values(value.counts).every(
    (count) => typeof count === "number" &&
      Number.isInteger(count) && count >= 0,
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value != null && !Array.isArray(value);
}

export function productionMessaging(): Messaging {
  return getMessaging();
}
