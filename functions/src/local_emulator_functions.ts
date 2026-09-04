const DEFAULT_PROJECT_ID = "dau-footy-tipping-f8a42";
const DEFAULT_REGION = "asia-southeast1";
const DEFAULT_FUNCTIONS_EMULATOR_ORIGIN = "http://127.0.0.1:9229";

type Environment = Record<string, string | undefined>;

/**
 * Returns true when running inside the Firebase Functions emulator worker.
 *
 * @param {Environment} environment Process environment to inspect.
 * @return {boolean} Whether emulator routing should be used.
 */
export function isRunningInFirebaseFunctionsEmulator(
  environment: Environment = process.env,
): boolean {
  const value = environment.FUNCTIONS_EMULATOR;
  return value != null && value.length > 0 &&
    value !== "false" &&
    value !== "0";
}

/**
 * Builds the local emulator URL for a Dart HTTP function.
 *
 * @param {string} functionName Hyphenated Firebase function entrypoint name.
 * @param {Environment} environment Process environment to inspect.
 * @return {string|null} Local URL, or null outside the Functions emulator.
 */
export function resolveLocalDartFunctionUrl(
  functionName: string,
  environment: Environment = process.env,
): string | null {
  if (!isRunningInFirebaseFunctionsEmulator(environment)) {
    return null;
  }

  return [
    resolveFunctionsEmulatorOrigin(environment),
    resolveFirebaseProjectId(environment),
    resolveFirebaseFunctionRegion(environment),
    functionName,
  ].join("/");
}

function resolveFirebaseProjectId(environment: Environment): string {
  return environment.GCLOUD_PROJECT ??
    environment.GOOGLE_CLOUD_PROJECT ??
    environment.GCP_PROJECT ??
    environment.FIREBASE_PROJECT ??
    DEFAULT_PROJECT_ID;
}

function resolveFirebaseFunctionRegion(environment: Environment): string {
  return environment.FUNCTION_REGION ??
    environment.FUNCTIONS_REGION ??
    DEFAULT_REGION;
}

function resolveFunctionsEmulatorOrigin(environment: Environment): string {
  const configuredOrigin =
    environment.LOCAL_FUNCTIONS_EMULATOR_ORIGIN ??
    environment.FUNCTIONS_EMULATOR_ORIGIN ??
    environment.FUNCTIONS_EMULATOR_HOST;

  if (configuredOrigin != null && configuredOrigin.trim().length > 0) {
    return normalizeOrigin(configuredOrigin);
  }

  return DEFAULT_FUNCTIONS_EMULATOR_ORIGIN;
}

function normalizeOrigin(value: string): string {
  const trimmedValue = value.trim().replace(/\/+$/, "");
  if (trimmedValue.startsWith("http://") ||
    trimmedValue.startsWith("https://")) {
    return trimmedValue;
  }

  return `http://${trimmedValue}`;
}
