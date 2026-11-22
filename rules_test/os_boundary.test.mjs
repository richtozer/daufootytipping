// The OPERATING-SYSTEM boundary: the actual guarantee (support/isolated.sh).
//
// Everything else (the Node preload, sandboxEnv, the stub) is a check inside Node or a convention for
// the scripts under test; none of it can stop a Bash script, a native executable, Dart or Java from
// opening a connection. These tests prove the OS-level boundary is really in force, using processes
// that are NOT Node and children that do NOT load the Node preload.
//
// SAFETY OF THE CANARIES: nothing here sends a packet to a real host unless the boundary has first
// been proven. The first check connects to 192.0.2.1, an RFC 5737 documentation address that is never
// routed, and requires the OS to answer EPERM (denied by the sandbox). Outside a boundary that same
// connect merely times out, which is how the two cases are told apart. Every later attempt calls
// `requireBoundary()` first and aborts the test if that proof is missing.
//
// Run only through the npm scripts (they use support/isolated.sh and set OS_BOUNDARY=1).
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import net from 'node:net';
import { homedir, tmpdir } from 'node:os';
import { basename, delimiter, join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { sandboxEnv } from './support/safety.mjs';

const TEST_NET_1 = '192.0.2.1'; // RFC 5737 documentation range: never routed
const sandboxDir = mkdtempSync(join(tmpdir(), 'os-boundary-'));
after(() => rmSync(sandboxDir, { recursive: true, force: true }));

// Children for the OS-level proof must NOT load the Node preload, or the preload would answer first.
const childEnv = (() => {
  const env = { ...sandboxEnv(sandboxDir) };
  delete env.NODE_OPTIONS;
  return env;
})();

const run = (file, args, options = {}) =>
  spawnSync(file, args, { encoding: 'utf8', env: childEnv, timeout: 30_000, ...options });

function findOnPath(name) {
  for (const dir of String(process.env.PATH ?? '').split(delimiter)) {
    const candidate = join(dir, name);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

let proven; // cached proof result
function boundaryProof() {
  if (proven) return proven;
  if (process.env.OS_BOUNDARY !== '1') {
    proven = { ok: false, why: 'OS_BOUNDARY is not set: these tests must be run through npm (support/isolated.sh)' };
    return proven;
  }
  const code = `
    import net from 'node:net';
    const s = net.connect({ host: '${TEST_NET_1}', port: 80 });
    s.setTimeout(4000);
    s.on('error', (e) => { console.log('ERR ' + e.code); process.exit(0); });
    s.on('timeout', () => { console.log('TIMEOUT'); process.exit(0); });
    s.on('connect', () => { console.log('CONNECTED'); process.exit(0); });
  `;
  const r = run(process.execPath, ['--input-type=module', '-e', code]);
  const out = r.stdout.trim();
  proven = out === 'ERR EPERM'
    ? { ok: true }
    : { ok: false, why: `the OS did not deny an outbound connection (got "${out}"); the boundary is NOT in force` };
  return proven;
}

function requireBoundary() {
  const proof = boundaryProof();
  assert.ok(proof.ok, `NOT INSIDE THE OS BOUNDARY: ${proof.why}. Refusing to attempt any external connection.`);
}

describe('the OS boundary is in force (proven before anything else is attempted)', () => {
  it('the runner marked it, and the OS answers EPERM to an outbound connection', () => {
    assert.equal(process.env.OS_BOUNDARY, '1', 'run through npm so support/isolated.sh sets this');
    requireBoundary();
  });

  it('this very test process runs with no credential variables and an empty config directory', () => {
    const forbidden = [/^GOOGLE_APPLICATION_CREDENTIALS$/, /^FIREBASE_TOKEN$/, /^GCLOUD_/, /^CLOUDSDK_/, /^FIREBASE_CONFIG$/, /^(HTTPS?|ALL|NO)_PROXY$/i, /^AWS_/, /^GITHUB_TOKEN$/, /^NPM_TOKEN$/];
    for (const key of Object.keys(process.env)) {
      // The Firebase emulator launcher sets GCLOUD_PROJECT itself (a project NAME, not a credential);
      // it is acceptable only when it names a demo- project.
      if (key === 'GCLOUD_PROJECT' && /^demo-/.test(process.env[key])) continue;
      // Likewise FIREBASE_CONFIG: a project descriptor, acceptable only when it names a demo- project.
      if (key === 'FIREBASE_CONFIG') {
        const config = JSON.parse(process.env[key]);
        assert.match(config.projectId, /^demo-/, 'FIREBASE_CONFIG must name a demo- project');
        assert.ok(!/credential|token|secret|key/i.test(Object.keys(config).join(' ')), 'FIREBASE_CONFIG must carry no credentials');
        continue;
      }
      assert.ok(!forbidden.some((re) => re.test(key)), `forbidden variable in the test process: ${key}`);
    }
    const config = process.env.XDG_CONFIG_HOME;
    assert.ok(config && existsSync(config), 'XDG_CONFIG_HOME must point at the runner\'s empty config dir');
    // The runner starts it EMPTY; the Firebase CLI may then write its own state (for example the
    // update-notifier file). What must never be present is a stored login.
    const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));
    for (const file of walk(config)) {
      assert.notEqual(basename(file), 'firebase-tools.json', `a Firebase CLI login file exists: ${file}`);
      let parsed = {};
      try {
        parsed = JSON.parse(readFileSync(file, 'utf8'));
      } catch {
        // not JSON: nothing to inspect for keys
      }
      for (const key of ['tokens', 'user', 'auth', 'refresh_token', 'access_token', 'id_token']) {
        assert.ok(!(key in parsed), `${file} holds a "${key}" entry`);
      }
    }
  });
});

describe('every kind of process is blocked from the outside world', () => {
  it('a native executable (curl) cannot reach a real host by name or by address', () => {
    requireBoundary();
    const curl = '/usr/bin/curl';
    assert.ok(existsSync(curl));
    for (const url of ['https://example.com/', `http://${TEST_NET_1}/`, 'http://1.1.1.1/']) {
      const r = run(curl, ['-s', '-m', '8', '-o', '/dev/null', '-w', '%{http_code}', url]);
      assert.notEqual(r.status, 0, `curl ${url} must fail`);
      assert.equal(r.stdout.trim(), '000', `curl ${url} must not receive an HTTP response`);
    }
  });

  it('Bash itself (/dev/tcp) cannot open a connection', () => {
    requireBoundary();
    const r = run('/bin/bash', ['-c', `exec 3<>/dev/tcp/${TEST_NET_1}/80 && echo CONNECTED || echo BLOCKED`]);
    assert.match(r.stdout, /BLOCKED/);
    assert.doesNotMatch(r.stdout, /CONNECTED/);
  });

  it('Python cannot open a connection', { skip: existsSync('/usr/bin/python3') ? false : 'python3 not present' }, () => {
    requireBoundary();
    const r = run('/usr/bin/python3', ['-c', `import socket; s=socket.socket(); s.settimeout(4); print(s.connect_ex(("${TEST_NET_1}", 80)))`]);
    assert.match(r.stdout.trim(), /^1$/, `expected EPERM (1), got "${r.stdout.trim()}"`);
  });

  it('Dart cannot open a connection', { skip: findOnPath('dart') ? false : 'dart not on PATH' }, () => {
    requireBoundary();
    const dart = findOnPath('dart');
    const script = join(sandboxDir, 'connect.dart');
    spawnSync('/usr/bin/tee', [script], {
      input: `import 'dart:io';\nFuture<void> main() async { try { final s = await Socket.connect('${TEST_NET_1}', 80, timeout: Duration(seconds: 5)); print('CONNECTED'); s.destroy(); } catch (e) { print('BLOCKED'); } }\n`,
      stdio: ['pipe', 'ignore', 'ignore'],
    });
    const r = run(dart, ['run', script], { env: { ...childEnv, PATH: `${childEnv.PATH}${delimiter}${resolve(dart, '..')}` } });
    assert.match(r.stdout, /BLOCKED/);
    assert.doesNotMatch(r.stdout, /CONNECTED/);
  });

  it('loopback still works for every kind of process (the emulators run there)', async () => {
    requireBoundary();
    // Async spawns: a synchronous curl would block this process's own event loop, and with it the
    // loopback server the curl is talking to.
    const exec = (file, args) =>
      new Promise((done) => {
        const child = spawn(file, args, { env: childEnv });
        let out = '';
        child.stdout.on('data', (d) => (out += d));
        const timer = setTimeout(() => child.kill('SIGKILL'), 10_000);
        child.on('close', () => {
          clearTimeout(timer);
          done(out.trim());
        });
      });
    const server = net.createServer((socket) => {
      socket.on('error', () => {}); // a probe that closes abruptly (bash /dev/tcp) resets the connection
      socket.end('HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nhi');
    });
    await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
    const { port } = server.address();
    try {
      assert.equal(await exec('/usr/bin/curl', ['-s', '-m', '8', '-o', '/dev/null', '-w', '%{http_code}', `http://127.0.0.1:${port}/`]), '200', 'curl to loopback');
      assert.match(await exec('/bin/bash', ['-c', `exec 3<>/dev/tcp/127.0.0.1/${port} && echo OK`]), /OK/, 'bash /dev/tcp to loopback');
    } finally {
      server.close();
    }
  });
});

describe('credential stores are unreadable', () => {
  const home = homedir();
  const stores = ['.config/configstore', '.config/gcloud', '.config/gh', '.ssh', '.aws', '.azure', '.kube', '.docker', '.netrc', 'Library/Keychains'];
  for (const rel of stores) {
    const path = join(home, rel);
    it(`${rel}: unreadable when it exists`, { skip: existsSync(path) ? false : 'not present on this machine' }, () => {
      requireBoundary();
      const r = run('/bin/ls', [path]);
      assert.notEqual(r.status, 0, `${path} must not be listable from inside the boundary`);
    });
  }
});

describe('the runner hands nothing from the caller\'s environment to what it runs', () => {
  it('credentials, proxies and a stored Firebase login in the CALLER\'s environment are all dropped', () => {
    requireBoundary();
    // A deliberately hostile caller environment (fake values only).
    const hostile = {
      PATH: process.env.PATH,
      HOME: homedir(),
      XDG_CONFIG_HOME: '/should/not/pass',
      GOOGLE_APPLICATION_CREDENTIALS: '/should/not/pass.json',
      FIREBASE_TOKEN: 'should-not-pass',
      GCLOUD_PROJECT: 'should-not-pass',
      CLOUDSDK_CONFIG: '/should/not/pass',
      HTTPS_PROXY: 'http://should-not-pass:1',
      AWS_ACCESS_KEY_ID: 'should-not-pass',
      GITHUB_TOKEN: 'should-not-pass',
      NODE_OPTIONS: '--no-warnings',
    };
    const r = spawnSync('/bin/bash', [resolve(import.meta.dirname, 'support', 'isolated.sh'), '/usr/bin/env'], { encoding: 'utf8', env: hostile, timeout: 30_000 });
    assert.equal(r.status, 0, r.stderr);
    const seen = Object.fromEntries(r.stdout.trim().split('\n').map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
    for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_TOKEN', 'GCLOUD_PROJECT', 'CLOUDSDK_CONFIG', 'HTTPS_PROXY', 'AWS_ACCESS_KEY_ID', 'GITHUB_TOKEN', 'NODE_OPTIONS']) {
      assert.equal(seen[key], undefined, `${key} leaked through the runner`);
    }
    assert.notEqual(seen.XDG_CONFIG_HOME, '/should/not/pass', 'the caller\'s XDG_CONFIG_HOME must be replaced by the runner\'s empty directory');
    assert.match(seen.XDG_CONFIG_HOME, /isolated\./);
    assert.equal(seen.OS_BOUNDARY, '1');
  });
});

describe('the npm scripts cannot bypass the boundary', () => {
  it('every test command runs through support/isolated.sh and loads the Node preload', () => {
    const scripts = JSON.parse(readFileSync(resolve(import.meta.dirname, 'package.json'), 'utf8')).scripts;
    for (const [name, command] of Object.entries(scripts)) {
      assert.match(command, /^\.\/support\/isolated\.sh /, `npm run ${name} must start with the boundary runner`);
    }
    for (const name of ['test', 'test:unit', 'test:live']) {
      assert.match(scripts[name], /NODE_OPTIONS=--import=\.\/support\/no_production\.mjs/, name);
    }
  });
});
