// scripts/deploy-functions.sh: the hardening required before any backend deployment.
//
// SAFETY: only refusal paths and --dry-run are exercised here. --dry-run exits before any build or
// deploy step, so even a bug could not reach `firebase deploy`; and every spawn gets `sandboxEnv`
// (no credentials, explicit stub that refuses anything but a demo- project), inside the OS boundary.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { describe, it } from 'node:test';
import { SANDBOX_PROJECT_ID, sandboxEnv, writeSandboxFirebaserc, assertSandboxProject } from './support/safety.mjs';

const UID_A = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const repoRoot = resolve(import.meta.dirname, '..');

function makeSandbox(adminUids, extraEnv = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'deploy-fn-'));
  for (const rel of ['scripts', 'config', 'functions_dart/bin', 'firebase.json']) {
    cpSync(resolve(repoRoot, rel), join(dir, rel), { recursive: true });
  }
  rmSync(join(dir, 'config', 'deployments'), { recursive: true, force: true });
  writeFileSync(join(dir, 'config', 'admin-auth-uids.json'), JSON.stringify({ adminAuthUids: adminUids }));
  writeSandboxFirebaserc(dir);
  assertSandboxProject(dir);
  const env = sandboxEnv(dir, { extra: extraEnv });
  const git = (...args) => spawnSync('git', args, { cwd: dir, encoding: 'utf8', env });
  git('init', '-q');
  git('config', 'user.email', 'test@example.test');
  git('config', 'user.name', 'Test');
  if (adminUids.length > 0) {
    spawnSync(process.execPath, [join(dir, 'scripts', 'build_admin_allowlist.mjs')], { cwd: dir, encoding: 'utf8', env });
  }
  git('add', '-A');
  git('commit', '-q', '-m', 'sandbox');
  return { dir, env, git };
}

const withSandbox = (adminUids, fn, extraEnv) => {
  const sb = makeSandbox(adminUids, extraEnv);
  try {
    return fn(sb);
  } finally {
    rmSync(sb.dir, { recursive: true, force: true });
  }
};
const run = (sb, args, { env = sb.env, input = '' } = {}) =>
  spawnSync('/bin/bash', [join(sb.dir, 'scripts', 'deploy-functions.sh'), ...args], { cwd: sb.dir, encoding: 'utf8', env, input });
const calls = (sb) => (existsSync(join(sb.dir, 'firebase-calls.log')) ? readFileSync(join(sb.dir, 'firebase-calls.log'), 'utf8').trim().split('\n') : []);
const deployCalls = (sb) => calls(sb).filter((c) => c.startsWith('deploy'));
const DEMO = ['--project', SANDBOX_PROJECT_ID];

describe('deploy-functions.sh requires an explicit, exactly matching project', () => {
  it('--yes without --project is refused', () => {
    withSandbox([UID_A], (sb) => {
      const r = run(sb, ['--yes', '--only', 'default']);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /--yes requires --project/);
      assert.deepEqual(deployCalls(sb), []);
    });
  });

  it('even interactively, a deploy needs --project', () => {
    withSandbox([UID_A], (sb) => {
      const r = run(sb, ['--only', 'default'], { input: 'deploy\n' });
      assert.equal(r.status, 1);
      assert.match(r.stderr, /requires --project/);
      assert.deepEqual(deployCalls(sb), []);
    });
  });

  it('a --project that merely contains, or is contained in, the active project is refused (exact match)', () => {
    withSandbox([UID_A], (sb) => {
      for (const wrong of [`${SANDBOX_PROJECT_ID}-extra`, 'demo-sandbox', 'never-deploy', `x${SANDBOX_PROJECT_ID}`, SANDBOX_PROJECT_ID.toUpperCase()]) {
        const r = run(sb, ['--dry-run', '--only', 'default', '--project', wrong]);
        assert.equal(r.status, 1, `--project ${wrong} must be refused`);
        assert.match(r.stderr, /not the active firebase project/);
      }
      assert.deepEqual(deployCalls(sb), []);
    });
  });

  it('accepts the exact active project in both shapes `firebase use` prints', () => {
    for (const style of ['plain', 'verbose']) {
      withSandbox([UID_A], (sb) => {
        const r = run(sb, ['--dry-run', '--only', 'default', ...DEMO]);
        assert.equal(r.status, 0, `${style}: ${r.stdout}${r.stderr}`);
        assert.match(r.stdout, /Dry run/);
      }, { STUB_USE_STYLE: style });
    }
  });
});

describe('deploy-functions.sh --dry-run runs the checks and stops', () => {
  it('never builds or deploys, and only asks firebase which project is active', () => {
    withSandbox([UID_A], (sb) => {
      const r = run(sb, ['--dry-run', '--only', 'all', ...DEMO]);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.match(r.stdout, /Nothing was built or deployed/);
      assert.deepEqual(calls(sb), ['use'], 'firebase may only be asked for the active project');
    });
  });

  it('the Dart codebase is refused while the allowlist is empty; the TypeScript codebase is not affected', () => {
    withSandbox([], (sb) => {
      const dart = run(sb, ['--dry-run', '--only', 'dart', ...DEMO]);
      assert.equal(dart.status, 1);
      assert.match(`${dart.stdout}${dart.stderr}`, /empty/);
      const ts = run(sb, ['--dry-run', '--only', 'default', ...DEMO]);
      assert.equal(ts.status, 0, ts.stdout + ts.stderr);
    });
  });

  it('a dirty working tree is refused unless --allow-dirty', () => {
    withSandbox([UID_A], (sb) => {
      writeFileSync(join(sb.dir, 'scripts', 'tracked-noise.txt'), 'x');
      sb.git('add', 'scripts/tracked-noise.txt');
      const r = run(sb, ['--dry-run', '--only', 'default', ...DEMO]);
      assert.equal(r.status, 1);
      assert.match(`${r.stdout}${r.stderr}`, /not clean/);
    });
  });
});

describe('deploy-functions.sh does not let the PATH shadow the firebase it was told to use', () => {
  it('without FIREBASE_BIN, a firebase earlier on the PATH is not shadowed by a user npm bin', () => {
    withSandbox([UID_A], (sb) => {
      const decoyBin = join(sb.env.HOME, '.npm-global', 'bin');
      mkdirSync(decoyBin, { recursive: true });
      writeFileSync(join(decoyBin, 'firebase'), '#!/bin/sh\necho DECOY-RAN >> "$HOME/decoy.log"\nexit 0\n');
      chmodSync(join(decoyBin, 'firebase'), 0o755);
      const env = { ...sb.env };
      delete env.FIREBASE_BIN;
      const r = run(sb, ['--dry-run', '--only', 'default', ...DEMO], { env });
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.equal(existsSync(join(sb.env.HOME, 'decoy.log')), false, 'the decoy firebase must never run');
      assert.deepEqual(calls(sb), ['use'], 'the stub earlier on the PATH was used');
    });
  });

  it('with FIREBASE_BIN set, the named executable is used regardless of the PATH', () => {
    withSandbox([UID_A], (sb) => {
      const decoyBin = join(sb.env.HOME, '.npm-global', 'bin');
      mkdirSync(decoyBin, { recursive: true });
      writeFileSync(join(decoyBin, 'firebase'), '#!/bin/sh\necho DECOY-RAN >> "$HOME/decoy.log"\nexit 0\n');
      chmodSync(join(decoyBin, 'firebase'), 0o755);
      const r = run(sb, ['--dry-run', '--only', 'default', ...DEMO]);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.equal(existsSync(join(sb.env.HOME, 'decoy.log')), false);
    });
  });
});

describe('every deploy invocation in the deploy scripts is explicit (source-level check)', () => {
  // No test performs the final deploy step (the heavy build steps precede it), so this guards the
  // line itself: it must go through $firebase_bin and name the project explicitly.
  for (const name of ['deploy-functions.sh', 'deploy-database-rules.sh']) {
    it(`${name}: firebase is always $firebase_bin, and every deploy passes --project "$project"`, () => {
      const lines = readFileSync(join(repoRoot, 'scripts', name), 'utf8').split('\n');
      // Command positions only: usage text inside heredocs and echo lines may mention firebase freely.
      const commandLines = lines.filter((l) => !/^\s*#/.test(l));
      const deploys = commandLines.filter((l) => /^\s*("\$firebase_bin"|firebase)\s+deploy\b/.test(l));
      assert.ok(deploys.length >= 1, 'the script must contain a deploy invocation');
      for (const line of deploys) {
        assert.match(line, /^\s*"\$firebase_bin" deploy /, `deploy must run through $firebase_bin: ${line.trim()}`);
        assert.match(line, /--project "\$project"/, `deploy must name the project explicitly: ${line.trim()}`);
      }
      for (const line of commandLines) {
        assert.ok(!/^\s*firebase\s/.test(line), `a bare \`firebase\` command remains: ${line.trim()}`);
        assert.ok(!/(\$\(|[|;&])\s*firebase\s/.test(line), `a bare \`firebase\` command remains: ${line.trim()}`);
      }
    });
  }
});
