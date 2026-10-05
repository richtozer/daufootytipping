// Preloaded with `node --import` into every test process AND every Node child process the tests
// spawn (via NODE_OPTIONS). It is a CHECK inside Node, not a sandbox:
//
//   1. NETWORK (Node APIs only): a connection to anything but a validated loopback address or the
//      exact name "localhost" is refused, and DNS lookups of anything else fail.
//   2. EXECUTABLES (Node child_process only): `firebase` and `gcloud` are refused unless the file
//      is byte-for-byte the checked-in stub (support/firebase_stub.sh, compared by SHA-256) located
//      at the exact path in NO_PRODUCTION_STUB. Being somewhere under the temp directory is NOT
//      enough. `gcloud` is never allowed.
//
// What this does NOT cover: Bash, native executables, Dart and Java can open connections it never
// sees. The real boundary is operating-system level (support/isolated.sh: macOS sandbox-exec, no
// outbound network except loopback, credential stores unreadable), proven by os_boundary.test.mjs.
// This preload is an additional, earlier, friendlier failure; it is not what makes the tests safe.
import childProcess from 'node:child_process';
import { createHash } from 'node:crypto';
import dns from 'node:dns';
import { readFileSync, realpathSync } from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import net from 'node:net';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PREFIX = 'NO_PRODUCTION_GUARD';

// Strict loopback: a real 127.0.0.0/8 or ::1 address (validated with net.isIP, so a hostname such
// as `127.example.com` is NOT accepted), or exactly the name "localhost". 0.0.0.0 and :: are not
// loopback addresses and are refused. An absent host means a unix-socket path or Node's own default
// of localhost.
const isLoopback = (host) => {
  if (host === undefined || host === null || host === '') return true;
  const h = String(host).toLowerCase().replace(/^\[|\]$/g, '');
  if (h === 'localhost') return true;
  const kind = net.isIP(h);
  if (kind === 4) return h.split('.')[0] === '127';
  if (kind === 6) {
    if (h === '::1') return true;
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(h);
    return mapped !== null && net.isIP(mapped[1]) === 4 && mapped[1].split('.')[0] === '127';
  }
  return false;
};

// ---- 1. network
const originalConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function guardedConnect(...args) {
  let first = args[0];
  if (Array.isArray(first)) first = first[0]; // Node's internal normalised form
  let host;
  if (first && typeof first === 'object') {
    if (first.path) host = undefined; // unix socket
    else host = first.host ?? 'localhost';
  } else if (typeof first === 'number' || (typeof first === 'string' && /^\d+$/.test(first))) {
    host = typeof args[1] === 'string' ? args[1] : 'localhost';
  } else {
    host = undefined; // path
  }
  if (!isLoopback(host)) {
    const error = new Error(`${PREFIX}: network access to "${host}" is blocked in tests (only loopback is allowed)`);
    error.code = 'ENOTFOUND';
    throw error;
  }
  return originalConnect.apply(this, args);
};

const blockedLookup = (hostname) => {
  const error = new Error(`${PREFIX}: DNS lookup of "${hostname}" is blocked in tests`);
  error.code = 'ENOTFOUND';
  return error;
};
const originalLookup = dns.lookup;
dns.lookup = function guardedLookup(hostname, ...rest) {
  if (!isLoopback(hostname)) {
    const callback = rest.find((r) => typeof r === 'function');
    if (callback) return process.nextTick(callback, blockedLookup(hostname));
    throw blockedLookup(hostname);
  }
  return originalLookup.call(this, hostname, ...rest);
};
const originalPromisesLookup = dns.promises.lookup;
dns.promises.lookup = async function guardedPromisesLookup(hostname, ...rest) {
  if (!isLoopback(hostname)) throw blockedLookup(hostname);
  return originalPromisesLookup.call(this, hostname, ...rest);
};

// ---- 2. executables
const FORBIDDEN = new Set(['firebase', 'gcloud']);
const RUNNERS = new Set(['npx', 'npm', 'pnpm', 'yarn']);

const sha256File = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const here = dirname(fileURLToPath(import.meta.url));
const CHECKED_IN_STUB_SHA = sha256File(join(here, 'firebase_stub.sh'));

const real = (p) => {
  try {
    return realpathSync(resolve(String(p)));
  } catch {
    return null;
  }
};

/** True only for the exact stub of this sandbox: same path as NO_PRODUCTION_STUB AND identical bytes. */
function isTheSandboxStub(file) {
  const expected = process.env.NO_PRODUCTION_STUB;
  if (!expected) return false;
  const actual = real(file);
  if (actual === null || actual !== real(expected)) return false;
  try {
    return sha256File(actual) === CHECKED_IN_STUB_SHA;
  } catch {
    return false;
  }
}

function refuse(what) {
  throw new Error(`${PREFIX}: refusing to run ${what} from a test. Tests may only run the exact checked-in stub of their own sandbox.`);
}

function checkCommand(file, args = []) {
  const name = basename(String(file));
  if (name === 'gcloud') refuse(`"${file}"`);
  if (name === 'firebase' && !isTheSandboxStub(file)) refuse(`"${file}"`);
  if (RUNNERS.has(name) && args.some((a) => FORBIDDEN.has(String(a)) || /^firebase-tools/.test(String(a)))) refuse(`"${file} ${args.join(' ')}"`);
}

function checkShellString(command) {
  if (/(^|[\s;&|(`'"/])(firebase|gcloud)(\s|$|;|&|\||\)|`|'|")/.test(String(command))) refuse(`shell command "${command}"`);
}

for (const name of ['spawn', 'spawnSync', 'execFile', 'execFileSync']) {
  const original = childProcess[name];
  childProcess[name] = function guarded(file, args, options) {
    const argv = Array.isArray(args) ? args : [];
    checkCommand(file, argv);
    const opts = Array.isArray(args) ? options : args;
    if (opts && opts.shell) checkShellString([file, ...argv].join(' '));
    return original.apply(this, arguments);
  };
}
for (const name of ['exec', 'execSync']) {
  const original = childProcess[name];
  childProcess[name] = function guarded(command) {
    checkShellString(command);
    return original.apply(this, arguments);
  };
}

syncBuiltinESMExports();
