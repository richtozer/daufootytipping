// scripts/deploy-database-rules.sh run end to end in a throwaway git repository.
//
// SAFETY (see support/safety.mjs and DESIGN-database-rules-phase3.md section 8): every spawned
// process gets `sandboxEnv`, never `process.env`: no credentials, an empty HOME, a PATH of only
// the sandbox bin and /usr/bin:/bin, an explicit FIREBASE_BIN stub, the no-network preload, and a
// demo- project. The stub refuses any deploy that is not aimed at an explicit demo- project, so
// even a bug in this file could not deploy to a real project.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { describe, it } from 'node:test';
import { allowlistRevision } from '../scripts/build_admin_allowlist.mjs';
import {
  PRODUCTION_PROJECT_ID,
  SANDBOX_PROJECT_ID,
  assertIsolated,
  assertSandboxProject,
  sandboxEnv,
  writeSandboxFirebaserc,
} from './support/safety.mjs';

const UID_A = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const repoRoot = resolve(import.meta.dirname, '..');

function makeSandbox(adminUids, extraEnv = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'deploy-'));
  for (const rel of ['scripts', 'config', 'functions_dart/bin', 'firebase.json', 'database.rules.json']) {
    cpSync(resolve(repoRoot, rel), join(dir, rel), { recursive: true });
  }
  rmSync(join(dir, 'config', 'deployments'), { recursive: true, force: true });
  writeFileSync(join(dir, 'config', 'admin-auth-uids.json'), JSON.stringify({ adminAuthUids: adminUids }));
  writeSandboxFirebaserc(dir); // never copied from the repo
  assertSandboxProject(dir);
  const env = sandboxEnv(dir, { extra: extraEnv });
  const git = (...args) => spawnSync('git', args, { cwd: dir, encoding: 'utf8', env });
  git('init', '-q');
  git('config', 'user.email', 'test@example.test');
  git('config', 'user.name', 'Test');
  return { dir, git, env };
}

const node = (sb, ...args) =>
  spawnSync(process.execPath, [join(sb.dir, 'scripts', 'build_admin_allowlist.mjs'), ...args], { cwd: sb.dir, encoding: 'utf8', env: sb.env });
const commitAll = (sb) => {
  sb.git('add', '-A');
  sb.git('commit', '-q', '-m', 'sandbox');
};
const deploy = (sb, args, input = '') =>
  spawnSync('/bin/bash', [join(sb.dir, 'scripts', 'deploy-database-rules.sh'), ...args], {
    cwd: sb.dir,
    encoding: 'utf8',
    env: sb.env,
    input,
  });
const read = (sb, name) => (existsSync(join(sb.dir, name)) ? readFileSync(join(sb.dir, name), 'utf8').trim() : '');
const deployed = (sb) => read(sb, 'firebase-deploy.log');
const recordLines = (sb) => {
  const text = read(sb, 'config/deployments/allowlist-deployments.jsonl');
  return text ? text.split('\n').map((l) => JSON.parse(l)) : [];
};
const withSandbox = (adminUids, fn, extraEnv) => {
  const sb = makeSandbox(adminUids, extraEnv);
  try {
    return fn(sb);
  } finally {
    rmSync(sb.dir, { recursive: true, force: true });
  }
};
const prepare = (sb, variant = 'r1') => {
  node(sb); // generate
  node(sb, '--install-rules', '--variant', variant);
  commitAll(sb);
};
const DEMO = ['--project', SANDBOX_PROJECT_ID];

describe('test isolation (these must hold before anything is deployed)', () => {
  it('the sandbox environment passes the isolation check and names only demo projects', () => {
    withSandbox([UID_A], (sb) => {
      assert.doesNotThrow(() => assertIsolated(sb.env));
      assert.equal(sb.env.ADMIN_SCRIPTS_PROJECT_ID, SANDBOX_PROJECT_ID);
      assert.ok(sb.env.FIREBASE_BIN.startsWith(sb.dir) || sb.env.FIREBASE_BIN.includes(tmpdir().replace(/^\/private/, '')));
      const keys = Object.keys(sb.env).sort();
      assert.deepEqual(keys, ['ADMIN_SCRIPTS_PROJECT_ID', 'FIREBASE_BIN', 'HOME', 'LANG', 'LC_ALL', 'NODE_OPTIONS', 'NO_PRODUCTION_STUB', 'PATH', 'TMPDIR'], 'nothing else may leak in');
    });
  });

  it('the firebase on the sandbox PATH is the stub, and no gcloud is reachable', () => {
    withSandbox([UID_A], (sb) => {
      const resolved = spawnSync('/bin/bash', ['-c', 'command -v firebase; command -v gcloud || echo NO-GCLOUD'], { env: sb.env, encoding: 'utf8' });
      const [firebasePath, gcloudResult] = resolved.stdout.trim().split('\n');
      assert.equal(firebasePath, join(sb.dir, 'bin', 'firebase'));
      assert.equal(gcloudResult, 'NO-GCLOUD');
    });
  });

  it('the stub refuses any deploy that is not aimed at an explicit demo- project, including production', () => {
    withSandbox([UID_A], (sb) => {
      const stub = sb.env.FIREBASE_BIN;
      // Run the stub script through bash: this tests the stub's own refusal logic. (Executing the
      // stub directly from THIS process is correctly refused by the preload, which is only
      // configured for stubs named in this process's own NO_PRODUCTION_STUB.)
      const run = (...args) => spawnSync('/bin/bash', [stub, ...args], { cwd: sb.dir, encoding: 'utf8', env: sb.env });
      assert.equal(run('deploy', '--only', 'database').status, 99, 'no --project');
      assert.equal(run('deploy', '--only', 'database', '--project', PRODUCTION_PROJECT_ID).status, 99, 'production');
      assert.equal(run('deploy', '--only', 'database', '--project', 'some-real-project').status, 99, 'any non-demo project');
      assert.equal(run('deploy', '--only', 'database', '--project', SANDBOX_PROJECT_ID).status, 0);
      assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`, 'only the demo deploy was recorded');
    });
  });

  it('assertIsolated rejects every way the environment could reach production', () => {
    withSandbox([UID_A], (sb) => {
      const bad = {
        'a credentials file': { ...sb.env, GOOGLE_APPLICATION_CREDENTIALS: '/x.json' },
        'a firebase token': { ...sb.env, FIREBASE_TOKEN: 'abc' },
        'a gcloud config dir': { ...sb.env, CLOUDSDK_CONFIG: '/x' },
        'the real home directory': { ...sb.env, HOME: process.env.HOME },
        'a missing network guard': { ...sb.env, NODE_OPTIONS: '' },
        'a non-demo project': { ...sb.env, ADMIN_SCRIPTS_PROJECT_ID: 'some-real-project' },
        'a firebase outside the sandbox': { ...sb.env, FIREBASE_BIN: '/usr/local/bin/firebase' },
        'a stub path that is not the declared one': { ...sb.env, NO_PRODUCTION_STUB: '/elsewhere/firebase' },
        'the production project id in any value': { ...sb.env, SOMETHING: `https://${PRODUCTION_PROJECT_ID}.example` },
      };
      for (const [label, env] of Object.entries(bad)) {
        assert.throws(() => assertIsolated(env), /SAFETY/, label);
      }
    });
  });

  it('assertIsolated rejects a PATH that contains a real firebase or gcloud', () => {
    withSandbox([UID_A], (sb) => {
      const fake = mkdtempSync(join(tmpdir(), 'fake-cli-'));
      try {
        for (const name of ['firebase', 'gcloud']) {
          writeFileSync(join(fake, name), '#!/bin/sh\nexit 0\n');
          chmodSync(join(fake, name), 0o755);
          rmSync(join(fake, name === 'firebase' ? 'gcloud' : 'firebase'), { force: true });
          assert.throws(() => assertIsolated({ ...sb.env, PATH: `${sb.env.PATH}:${fake}` }), /real (firebase|gcloud) is reachable/, name);
        }
      } finally {
        rmSync(fake, { recursive: true, force: true });
      }
    });
  });

  it('sandboxEnv refuses to be handed credentials, the production id, or a non-loopback emulator', () => {
    const dir = mkdtempSync(join(tmpdir(), 'env-'));
    try {
      assert.throws(() => sandboxEnv(dir, { extra: { GOOGLE_APPLICATION_CREDENTIALS: '/x' } }), /SAFETY/);
      assert.throws(() => sandboxEnv(dir, { extra: { X: PRODUCTION_PROJECT_ID } }), /SAFETY/);
      assert.throws(() => sandboxEnv(dir, { extra: { FIREBASE_DATABASE_EMULATOR_HOST: 'example.com:9000' } }), /SAFETY/);
      assert.doesNotThrow(() => sandboxEnv(dir, { extra: { FIREBASE_DATABASE_EMULATOR_HOST: '127.0.0.1:8000' } }));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('a sandbox .firebaserc naming a non-demo project is rejected', () => {
    const dir = mkdtempSync(join(tmpdir(), 'rc-'));
    try {
      writeFileSync(join(dir, '.firebaserc'), JSON.stringify({ projects: { default: 'some-real-project' } }));
      assert.throws(() => assertSandboxProject(dir), /non-demo project/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('deploy-database-rules.sh', () => {
  it('refuses an empty allowlist and never reaches firebase deploy', () => {
    withSandbox([], (sb) => {
      commitAll(sb);
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 1, r.stdout + r.stderr);
      assert.match(r.stderr, /empty/);
      assert.equal(deployed(sb), '');
    });
  });

  it('refuses while database.rules.json is still the open rules (the file Firebase would ship)', () => {
    withSandbox([UID_A], (sb) => {
      node(sb); // generated outputs exist, but database.rules.json has NOT been installed
      writeFileSync(join(sb.dir, 'database.rules.json'), '{"rules":{".read":"true",".write":"true"}}\n');
      commitAll(sb);
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 1, r.stdout + r.stderr);
      assert.match(r.stderr, /would ship something else/);
      assert.equal(deployed(sb), '');
    });
  });

  it('refuses a dirty working tree unless --allow-dirty', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      writeFileSync(join(sb.dir, 'scripts', 'noise.txt'), 'y');
      sb.git('add', 'scripts/noise.txt');
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 1);
      assert.match(r.stdout + r.stderr, /not clean/);
      assert.equal(deployed(sb), '');
    });
  });

  it('--yes without --project is refused (a non-interactive run can never use an implicit project)', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, ['--yes']);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /--yes requires --project/);
      assert.equal(deployed(sb), '');
    });
  });

  it('a --project that is not the active firebase project is refused', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, ['--yes', '--project', 'demo-some-other-project']);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /not the active firebase project/);
      assert.equal(deployed(sb), '');
    });
  });

  it('a --project that merely contains, or is contained in, the active project is refused (exact match)', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      for (const wrong of [`${SANDBOX_PROJECT_ID}-extra`, 'demo-sandbox', 'never-deploy', `x${SANDBOX_PROJECT_ID}`, SANDBOX_PROJECT_ID.toUpperCase()]) {
        const r = deploy(sb, ['--yes', '--project', wrong]);
        assert.equal(r.status, 1, `--project ${wrong} must be refused`);
        assert.match(r.stderr, /not the active firebase project/);
      }
      assert.equal(deployed(sb), '');
    });
  });

  it('accepts the exact active project in both shapes `firebase use` prints', () => {
    for (const style of ['plain', 'verbose']) {
      withSandbox([UID_A], (sb) => {
        prepare(sb);
        const r = deploy(sb, ['--yes', ...DEMO]);
        assert.equal(r.status, 0, `${style}: ${r.stdout}${r.stderr}`);
        assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`);
      }, { STUB_USE_STYLE: style });
    }
  });

  it('even interactively, a deploy needs --project', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, [], 'deploy\n');
      assert.equal(r.status, 1);
      assert.match(r.stderr, /requires --project/);
      assert.equal(deployed(sb), '');
    });
  });

  it('--dry-run runs every check, deploys nothing and records nothing', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, ['--dry-run']);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.match(r.stdout, /Dry run: all checks passed/);
      assert.match(r.stdout, new RegExp(`Allowlist revision: ${allowlistRevision([UID_A])}`));
      assert.equal(deployed(sb), '');
      assert.equal(recordLines(sb).length, 0);
    });
  });

  it('declining the confirmation prompt aborts without deploying', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, [...DEMO], 'no\n');
      assert.equal(r.status, 1);
      assert.match(r.stdout, /Aborted/);
      assert.equal(deployed(sb), '');
    });
  });

  it('deploys exactly the database target to the explicit project and records the allowlist revision', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`);
      const [entry, ...rest] = recordLines(sb);
      assert.equal(rest.length, 0);
      assert.equal(entry.kind, 'rules');
      assert.equal(entry.variant, 'r1');
      assert.equal(entry.allowlistRevision, allowlistRevision([UID_A]));
      assert.equal(entry.project, SANDBOX_PROJECT_ID);
      assert.match(entry.rulesSha256, /^[0-9a-f]{64}$/);
    });
  });

  it('the recovery variant is deployable only after it is installed, and says what it relaxes', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb, 'r1');
      const wrong = deploy(sb, ['--yes', '--variant', 'r1-recovery', ...DEMO]);
      assert.equal(wrong.status, 1, 'R1 is installed, so a recovery deploy must be refused');
      assert.equal(deployed(sb), '');

      node(sb, '--install-rules', '--variant', 'r1-recovery');
      commitAll(sb);
      const r = deploy(sb, ['--yes', '--variant', 'r1-recovery', ...DEMO]);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.match(r.stdout, /RECOVERY ruleset/);
      assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`);
      assert.equal(recordLines(sb)[0].variant, 'r1-recovery');
    });
  });

  it('rejects an unknown variant', () => {
    withSandbox([UID_A], (sb) => {
      const r = deploy(sb, ['--yes', '--variant', 'open', ...DEMO]);
      assert.equal(r.status, 1);
      assert.equal(deployed(sb), '');
    });
  });

  it('a hand edit to the installed rules after committing is caught before deploy', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const p = join(sb.dir, 'database.rules.json');
      writeFileSync(p, readFileSync(p, 'utf8').replace('"AppConfig"', '"AppConfigX"'));
      commitAll(sb);
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 1);
      assert.equal(deployed(sb), '');
    });
  });

  it('without FIREBASE_BIN, a firebase placed earlier on the PATH is never shadowed by a user npm bin', () => {
    // This tests the PATH logic on its own (the explicit FIREBASE_BIN would otherwise mask it).
    // The decoy only logs and exits; it cannot deploy anything.
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      const decoyBin = join(sb.env.HOME, '.npm-global', 'bin');
      mkdirSync(decoyBin, { recursive: true });
      writeFileSync(join(decoyBin, 'firebase'), '#!/bin/sh\necho DECOY-RAN >> "$HOME/decoy.log"\nexit 0\n');
      chmodSync(join(decoyBin, 'firebase'), 0o755);
      const env = { ...sb.env };
      delete env.FIREBASE_BIN;
      const r = spawnSync('/bin/bash', [join(sb.dir, 'scripts', 'deploy-database-rules.sh'), '--yes', ...DEMO], {
        cwd: sb.dir,
        encoding: 'utf8',
        env,
        input: '',
      });
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.equal(existsSync(join(sb.env.HOME, 'decoy.log')), false, 'the decoy firebase must never run');
      assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`, 'the stub earlier on the PATH was used');
    });
  });

  it('the script does not prepend a user npm bin that could shadow the explicit firebase', () => {
    withSandbox([UID_A], (sb) => {
      prepare(sb);
      // Even with a decoy npm-global dir containing a "firebase" in HOME, the explicit stub wins.
      const decoyBin = join(sb.env.HOME, '.npm-global', 'bin');
      mkdirSync(decoyBin, { recursive: true });
      writeFileSync(join(decoyBin, 'firebase'), '#!/bin/sh\necho DECOY-RAN >> "$HOME/decoy.log"\nexit 0\n');
      chmodSync(join(decoyBin, 'firebase'), 0o755);
      const r = deploy(sb, ['--yes', ...DEMO]);
      assert.equal(r.status, 0, r.stdout + r.stderr);
      assert.equal(existsSync(join(sb.env.HOME, 'decoy.log')), false, 'the decoy firebase must never run');
      assert.equal(deployed(sb), `deploy --only database --project ${SANDBOX_PROJECT_ID}`);
    });
  });
});
