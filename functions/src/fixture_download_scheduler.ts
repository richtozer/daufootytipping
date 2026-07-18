import {onSchedule} from "firebase-functions/v2/scheduler";

export interface ScheduledFixtureDownloadLoggerLike {
  log(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

export interface ScheduledFixtureDownloadDependencies {
  fetchImpl?: typeof fetch;
  commandUrl?: string;
  commandSecret?: string;
  logger?: ScheduledFixtureDownloadLoggerLike;
}

const DEFAULT_COMMAND_URL_ENV_KEYS = [
  "DART_FIXTURE_DOWNLOAD_COMMAND_URL",
  "FIXTURE_DOWNLOAD_COMMAND_URL",
];

const DEFAULT_COMMAND_SECRET_ENV_KEYS = [
  "BACKEND_SCORING_COMMAND_SECRET",
  "DART_BACKEND_SCORING_COMMAND_SECRET",
];

const FIXTURE_DOWNLOAD_COMMAND_SECRET_HEADER = "x-backend-scoring-secret";
const FIXTURE_DOWNLOAD_SCHEDULE = "0 16 * * *";

function resolveScheduledFixtureDownloadEnv(
  keys: string[],
): string | undefined {
  for (const key of keys) {
    const value = process.env[key];
    if (value != null && value.length > 0) {
      return value;
    }
  }
  return undefined;
}

export async function forwardScheduledFixtureDownload(
  deps: ScheduledFixtureDownloadDependencies = {},
): Promise<void> {
  const logger = deps.logger ?? console;
  const commandUrl =
    deps.commandUrl ?? resolveScheduledFixtureDownloadEnv(DEFAULT_COMMAND_URL_ENV_KEYS);
  const commandSecret =
    deps.commandSecret ?? resolveScheduledFixtureDownloadEnv(DEFAULT_COMMAND_SECRET_ENV_KEYS);

  if (commandUrl == null || commandUrl.length === 0) {
    throw new Error("Scheduled fixture download URL is not configured");
  }
  if (commandSecret == null || commandSecret.length === 0) {
    throw new Error("Scheduled fixture download secret is not configured");
  }

  const fetchImpl = deps.fetchImpl ?? fetch;
  logger.log(`forwardScheduledFixtureDownload: POST ${commandUrl}`);
  const response = await fetchImpl(commandUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      [FIXTURE_DOWNLOAD_COMMAND_SECRET_HEADER]: commandSecret,
    },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    const responseBody = await response.text();
    throw new Error(
      `Scheduled fixture download failed with HTTP ${response.status}: ${responseBody}`,
    );
  }

  logger.log("forwardScheduledFixtureDownload: completed successfully");
}

export const scheduledFixtureDownload = onSchedule(
  {
    schedule: FIXTURE_DOWNLOAD_SCHEDULE,
    timeZone: "UTC",
  },
  async () => {
    await forwardScheduledFixtureDownload();
  },
);
