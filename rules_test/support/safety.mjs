// Test isolation helpers. Anything that spawns a script (deploy scripts, the audit CLIs, the
// generator) must build its environment with `sandboxEnv`, never by spreading `process.env`.
//
// IMPORTANT: this is one of THREE layers, and not the strongest. The real boundary is the
// operating-system sandbox in support/isolated.sh (no outbound network except loopback, credential
// stores unreadable), proven by os_boundary.test.mjs. This file and support/no_production.mjs are
// additional checks that make mistakes fail early; they do not, on their own, make a test unable
// to reach production.
//
// What `sandboxEnv` / `assertIsolated` check for the scripts a test spawns:
//   * a minimal, explicit environment: no GOOGLE_APPLICATION_CREDENTIALS, FIREBASE_TOKEN, gcloud or
//     firebase configuration, and HOME is an empty directory inside the sandbox;
//   * the Node preload (no_production.mjs) is loaded into every Node child;
//   * scripts are told which `firebase` to run through FIREBASE_BIN: the exact checked-in stub
//     (support/firebase_stub.sh, compared by content), and the PATH holds only the sandbox bin plus
//     /usr/bin and /bin;
//   * the stub refuses any deploy that is not aimed at an explicit `demo-` project, the sandbox
//     project is `demo-sandbox-never-deploy`, and assertNotProduction rejects the real id.
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { delimiter, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Built from parts so this file is the only place the real id is spelled out, and a repo-wide
// test (safety.test.mjs) can assert no other test file mentions it.
export const PRODUCTION_PROJECT_ID = ['dau', 'footy', 'tipping', 'f8a42'].join('-');
export const SANDBOX_PROJECT_ID = 'demo-sandbox-never-deploy';
export const GUARD_FILE = resolve(import.meta.dirname, 'no_production.mjs');
export const STUB_SOURCE = resolve(import.meta.dirname, 'firebase_stub.sh');
const sha256 = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');

const FORBIDDEN_ENV = [
  /^GOOGLE_APPLICATION_CREDENTIALS$/,
  /^GOOGLE_CLOUD_PROJECT$/,
  /^GCLOUD_/,
  /^CLOUDSDK_/,
  /^FIREBASE_TOKEN$/,
  /^FIREBASE_CONFIG$/,
  /^FIREBASE_PROJECT$/,
  /^XDG_CONFIG_HOME$/,
  /^npm_config_/i,
];
const LOOPBACK_EMULATOR = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;

export function assertNotProduction(label, ...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.includes(PRODUCTION_PROJECT_ID)) {
      throw new Error(`SAFETY: ${label} names the production project (${PRODUCTION_PROJECT_ID}); tests must use a demo- project`);
    }
  }
}

function findExecutable(name) {
  for (const dir of ['/usr/bin', '/bin', '/opt/homebrew/bin', '/usr/local/bin']) {
    const candidate = join(dir, name);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

/** Create sandbox/bin (node, git, the firebase stub) and sandbox/home. Idempotent. */
export function prepareSandbox(dir) {
  const bin = join(dir, 'bin');
  const home = join(dir, 'home');
  mkdirSync(bin, { recursive: true });
  mkdirSync(home, { recursive: true });
  const link = (name, target) => {
    const at = join(bin, name);
    if (target && !existsSync(at)) symlinkSync(target, at);
  };
  link('node', process.execPath);
  link('git', findExecutable('git'));
  const stub = join(bin, 'firebase');
  if (!existsSync(stub)) {
    copyFileSync(STUB_SOURCE, stub); // byte-for-byte: the preload verifies it by content
    chmodSync(stub, 0o755);
  }
  return { bin, home, stub };
}

/** The ONLY environment tests may hand to a spawned script. */
export function sandboxEnv(dir, { extra = {} } = {}) {
  // FAIL CLOSED: a test that spawns processes must run inside the OS boundary (support/isolated.sh,
  // which sets OS_BOUNDARY=1; os_boundary.test.mjs proves the boundary is real). A stray
  // `node --test some.test.mjs` therefore cannot silently run unprotected.
  if (process.env.OS_BOUNDARY !== '1') {
    throw new Error('SAFETY: not inside the OS boundary. Run the tests through npm (npm test / npm run test:unit), which use support/isolated.sh.');
  }
  const { bin, home, stub } = prepareSandbox(dir);
  for (const [key, value] of Object.entries(extra)) {
    if (FORBIDDEN_ENV.some((re) => re.test(key))) throw new Error(`SAFETY: env var ${key} may not be passed to a sandboxed script`);
    assertNotProduction(`env ${key}`, value);
    if (/EMULATOR_HOST$/.test(key) && !LOOPBACK_EMULATOR.test(String(value))) {
      throw new Error(`SAFETY: ${key}=${value} is not a loopback address`);
    }
  }
  const env = {
    HOME: home,
    PATH: `${bin}${delimiter}/usr/bin${delimiter}/bin`,
    TMPDIR: tmpdir(),
    LANG: 'C',
    LC_ALL: 'C',
    NODE_OPTIONS: `--import=${pathToFileURL(GUARD_FILE).href}`,
    FIREBASE_BIN: stub,
    NO_PRODUCTION_STUB: stub,
    ADMIN_SCRIPTS_PROJECT_ID: SANDBOX_PROJECT_ID,
    ...extra,
  };
  assertIsolated(env);
  return env;
}

const realOrSelf = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return resolve(p);
  }
};

/** Throws unless `env` is isolated from production credentials, executables and projects. */
export function assertIsolated(env) {
  for (const key of Object.keys(env)) {
    if (FORBIDDEN_ENV.some((re) => re.test(key))) throw new Error(`SAFETY: forbidden env var ${key}`);
  }
  for (const [key, value] of Object.entries(env)) assertNotProduction(`env ${key}`, value);

  const tmp = realOrSelf(tmpdir());
  if (!realOrSelf(env.HOME ?? '/nonexistent').startsWith(tmp)) throw new Error('SAFETY: HOME must be inside the system temp directory');
  if (!String(env.NODE_OPTIONS ?? '').includes('no_production.mjs')) throw new Error('SAFETY: the no-network / no-firebase guard is not preloaded');
  // demo- for emulator runs; fixture- for the one test that proves a LIVE run without credentials
  // fails fast (it can reach nothing: no credentials, no network, and the project does not exist).
  if (!/^(demo|fixture)-/.test(String(env.ADMIN_SCRIPTS_PROJECT_ID ?? ''))) {
    throw new Error('SAFETY: ADMIN_SCRIPTS_PROJECT_ID must be a demo- or fixture- project');
  }
  // The firebase to run must be the exact checked-in stub, identified by content, not by location.
  const bin = env.FIREBASE_BIN ?? '/nonexistent';
  if (env.NO_PRODUCTION_STUB !== bin) throw new Error('SAFETY: FIREBASE_BIN must be the sandbox stub named in NO_PRODUCTION_STUB');
  if (!existsSync(bin) || sha256(bin) !== sha256(STUB_SOURCE)) {
    throw new Error('SAFETY: FIREBASE_BIN is not byte-identical to the checked-in support/firebase_stub.sh');
  }

  const stubDir = realOrSelf(join(env.FIREBASE_BIN, '..'));
  for (const dir of String(env.PATH ?? '').split(delimiter)) {
    for (const forbidden of ['firebase', 'gcloud']) {
      const found = join(dir, forbidden);
      if (existsSync(found) && !(forbidden === 'firebase' && realOrSelf(dir) === stubDir)) {
        throw new Error(`SAFETY: a real ${forbidden} is reachable on the PATH at ${found}`);
      }
    }
  }
}

/** The sandbox's .firebaserc must name a demo project. */
export function assertSandboxProject(dir) {
  const rc = JSON.parse(readFileSync(join(dir, '.firebaserc'), 'utf8'));
  for (const id of Object.values(rc.projects ?? {})) {
    if (!String(id).startsWith('demo-')) throw new Error(`SAFETY: sandbox .firebaserc names a non-demo project: ${id}`);
  }
}

/** Write a sandbox .firebaserc that names only the demo project. */
export function writeSandboxFirebaserc(dir) {
  writeFileSync(join(dir, '.firebaserc'), JSON.stringify({ projects: { default: SANDBOX_PROJECT_ID } }));
}
