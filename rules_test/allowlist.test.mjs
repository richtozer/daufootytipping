// The admin allowlist has ONE source (config/admin-auth-uids.json) and several consumers (the R1
// rules, the recovery rules, the Dart admin endpoints) plus the file Firebase actually deploys.
// These tests make the generated artifacts agree, prove the generator fails closed, and prove the
// deployment guard checks the file that is really shipped.
//
// Note on the empty list: the unit tests tolerate it (the committed config is empty until the
// owner verifies the admins) so development can proceed. Anything that could be DEPLOYED refuses
// it: `--check-deploy`, `--install-rules` and `--record` never accept an empty list, and
// scripts/deploy-database-rules.sh and scripts/deploy-functions.sh call them.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { describe, it } from 'node:test';
import {
  PATHS,
  VARIANTS,
  allowlistRevision,
  buildRules,
  isAdminExpr,
  loadConfig,
  renderRulesFile,
  ruleLiteral,
  unescapeRuleLiteral,
  validateUids,
} from '../scripts/build_admin_allowlist.mjs';
import { SANDBOX_PROJECT_ID, assertSandboxProject, sandboxEnv, writeSandboxFirebaserc } from './support/safety.mjs';

const UID_A = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // 28 chars: the format Firebase generates
const UID_B = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const template = readFileSync(PATHS.template, 'utf8');
const repoRoot = resolve(PATHS.config, '../..');

// Awkward but valid Firebase UIDs (1 to 128 characters, any text without control characters).
const AWKWARD = ["a'b", 'a\\b', 'a$b', 'a"b', "x'\\$'y", 'user-with-a-custom-id', 'ünïcödé-uid', 'x'.repeat(128), 'k'];

describe('validateUids', () => {
  it('accepts well-formed unique UIDs, including custom ones of 1 to 128 characters', () => {
    assert.deepEqual(validateUids([UID_A, UID_B]), [UID_A, UID_B]);
    assert.deepEqual(validateUids(AWKWARD), AWKWARD);
  });
  it('rejects empty, over-long, control-character and non-string values', () => {
    for (const bad of ['', 'x'.repeat(129), 'a\nb', 'a\u0000b', 'a\u007fb', null, 42, undefined, {}]) {
      assert.throws(() => validateUids([bad]), /Not a valid Firebase UID/, JSON.stringify(bad));
    }
  });
  it('rejects duplicates', () => {
    assert.throws(() => validateUids([UID_A, UID_A]), /Duplicate/);
  });
  it('refuses an empty list unless explicitly allowed', () => {
    assert.throws(() => validateUids([]), /empty/);
    assert.deepEqual(validateUids([], { allowEmpty: true }), []);
  });
  it('rejects a non-array', () => {
    assert.throws(() => validateUids('x'), /array/);
  });
});

describe('literal escaping', () => {
  it('round-trips every awkward UID through the rules literal', () => {
    for (const uid of AWKWARD) {
      assert.equal(unescapeRuleLiteral(ruleLiteral(uid)), uid, `rules: ${uid}`);
    }
  });
  it('a quote or backslash cannot break out of the rules expression', () => {
    const text = renderRulesFile(template, ["x' || true || 'y"]);
    // the whole UID must remain a single literal: no bare `|| true` outside quotes
    const expr = JSON.parse(text).rules.AppConfig['.write'];
    assert.equal(expr, `(auth != null && (auth.uid === 'x\\' || true || \\'y'))`);
  });
  it('the generated rules JSON stays valid with awkward UIDs', () => {
    const parsed = JSON.parse(renderRulesFile(template, AWKWARD));
    assert.ok(parsed.rules.AppConfig['.write'].includes('auth.uid ==='));
  });
});

describe('allowlistRevision', () => {
  it('is a stable 12-character hex id, independent of order, and changes with the list', () => {
    const r = allowlistRevision([UID_A, UID_B]);
    assert.match(r, /^[0-9a-f]{12}$/);
    assert.equal(allowlistRevision([UID_B, UID_A]), r);
    assert.notEqual(allowlistRevision([UID_A]), r);
    assert.notEqual(allowlistRevision([UID_A, UID_B, 'extra']), r);
  });
});

describe('generated rules', () => {
  it('inline every UID and leave no placeholder', () => {
    const text = renderRulesFile(template, [UID_A, UID_B]);
    assert.ok(text.includes(`auth.uid === '${UID_A}'`));
    assert.ok(text.includes(`auth.uid === '${UID_B}'`));
    assert.ok(!text.includes('{{'));
  });
  it('an empty list produces rules where no one is an admin (fail closed)', () => {
    assert.equal(isAdminExpr([]), 'false');
    assert.ok(!renderRulesFile(template, []).includes('auth.uid ==='));
  });
  it('the sign-in requirement excludes anonymous users', () => {
    assert.ok(renderRulesFile(template, [UID_A]).includes("sign_in_provider !== 'anonymous'"));
  });
  it('the template contains no hard-coded UIDs', () => {
    assert.ok(!template.includes('auth.uid ==='));
    assert.ok(template.includes('{{IS_ADMIN}}'));
  });
});

describe('recovery variant (what to deploy instead of reopening the database)', () => {
  const r1 = buildRules(template, [UID_A]).rules;
  const recovery = buildRules(template, [UID_A], { variant: 'r1-recovery' }).rules;

  it('keeps every allowlist-protected area identical to R1', () => {
    for (const area of ['AppConfig', 'AllDAUComps', 'Teams', 'DAUCompsGames']) {
      assert.deepEqual(recovery[area], r1[area], area);
    }
    assert.equal(recovery.AllTippers['.write'], r1.AllTippers['.write']);
    assert.equal(recovery.AllTippers.$tipperId['.write'], r1.AllTippers.$tipperId['.write']);
    assert.equal(recovery.AllTippers.$tipperId['.validate'], r1.AllTippers.$tipperId['.validate']);
    for (const field of ['authuid', 'tipperRole', 'compsParticipatedIn']) {
      assert.deepEqual(recovery.AllTippers.$tipperId[field], r1.AllTippers.$tipperId[field], field);
      assert.equal(recovery.AllTippers.$tipperId[field]['.write'], undefined, `${field} must stay non-writable by users`);
    }
    assert.deepEqual(recovery.AllTippersTokens, r1.AllTippersTokens);
    assert.equal(recovery.AllTips.$comp.$tipperId['.write'], r1.AllTips.$comp.$tipperId['.write']);
  });
  it('relaxes only validation strictness and re-admits the legacy Stats writers', () => {
    assert.deepEqual(Object.keys(recovery.AllTips.$comp.$tipperId.$game), ['.write']);
    assert.equal(recovery.AllTippers.$tipperId.$other, undefined);
    for (const b of ['game_stats_v3', 'live_scores_v3', 'round_stats_v3', 'scoring_audit_v3', 'admin_scoring_freshness_probe']) {
      assert.ok(recovery.Stats.$comp[b]['.write'].includes("sign_in_provider !== 'anonymous'"), b);
      assert.equal(r1.Stats.$comp[b], undefined, `${b} is not writable in R1`);
    }
  });
  it('never reopens the backend-owned Stats branches or the root', () => {
    assert.equal(recovery.Stats.$comp.round_stats_backend_v1, undefined);
    assert.equal(recovery.Stats.$comp.game_stats_backend_v1, undefined);
    assert.equal(recovery.Stats.$comp.scoring_status, undefined);
    assert.equal(recovery['.write'], undefined);
    assert.equal(recovery['.read'], undefined);
  });
});

describe('compat variant (R1 plus the two reads the R2 client needs)', () => {
  const r1 = buildRules(template, [UID_A]).rules;
  const compat = buildRules(template, [UID_A], { variant: 'r1-compat' }).rules;

  it('is R1 plus AuthIndex and TipperPrivate, with every R1 node unchanged', () => {
    assert.deepEqual(Object.keys(compat).filter((k) => !(k in r1)).sort(), ['AuthIndex', 'TipperPrivate']);
    for (const key of Object.keys(r1)) assert.deepEqual(compat[key], r1[key], key);
  });

  it('puts the allowlist into the TipperPrivate admin read and nowhere else it adds', () => {
    assert.ok(compat.TipperPrivate['.read'].includes(`auth.uid === '${UID_A}'`));
    assert.ok(!JSON.stringify(compat.AuthIndex).includes(UID_A));
  });

  it('an empty allowlist leaves the admin read false, never open', () => {
    const empty = buildRules(template, [], { variant: 'r1-compat' }).rules;
    assert.equal(empty.TipperPrivate['.read'], 'false');
  });
});

describe('freeze and r2 variants', () => {
  const r2Template = readFileSync(PATHS.r2Template, 'utf8');
  const compat = buildRules(template, [UID_A], { variant: 'r1-compat' }).rules;
  const freeze = buildRules(template, [UID_A], { variant: 'freeze' }).rules;
  const r2 = buildRules(r2Template, [UID_A], { variant: 'r2' }).rules;

  it('freeze is R1-compat with the identity writes removed: the same nodes, only AllTippers and AllTips changed', () => {
    assert.deepEqual(Object.keys(freeze).sort(), Object.keys(compat).sort());
    const changed = Object.keys(compat).filter((k) => JSON.stringify(compat[k]) !== JSON.stringify(freeze[k]));
    assert.deepEqual(changed.sort(), ['AllTippers', 'AllTips']);
  });

  it('freeze keeps the allowlist for the admin paid toggle, and an empty allowlist leaves it false, never open', () => {
    assert.ok(freeze.AllTippers.$tipperId.compsParticipatedIn['.write'].includes(`auth.uid === '${UID_A}'`));
    const empty = buildRules(template, [], { variant: 'freeze' }).rules;
    assert.equal(empty.AllTippers.$tipperId.compsParticipatedIn['.write'], 'false');
  });

  it('r2 takes no allowlist: the same rules whatever the list, and no uid literal in them', () => {
    for (const uids of [[], [UID_A], [UID_A, UID_B]]) {
      assert.deepEqual(buildRules(r2Template, uids, { variant: 'r2' }).rules, r2);
    }
    assert.doesNotMatch(JSON.stringify(r2), /auth\.uid === '/);
    assert.ok(!JSON.stringify(r2).includes(UID_A));
  });

  it('r2 leaves no placeholder behind, and refuses a template with an unknown one', () => {
    assert.ok(!JSON.stringify(r2).includes('{{'));
    assert.throws(() => buildRules('{"rules":{"x":{".read":"{{NOPE}}"}}}', [], { variant: 'r2' }), /Unresolved placeholder/);
  });

  it('there are five variants, each written to its own file', () => {
    assert.deepEqual([...VARIANTS], ['r1', 'r1-recovery', 'r1-compat', 'freeze', 'r2']);
    const files = [PATHS.rulesOut, PATHS.recoveryOut, PATHS.compatOut, PATHS.freezeOut, PATHS.r2Out];
    assert.equal(new Set(files).size, 5);
  });
});

describe('committed outputs match config/admin-auth-uids.json', () => {
  const uids = validateUids(loadConfig(), { allowEmpty: true });

  it('the committed R1 rules, recovery rules, compat rules, freeze rules and R2 rules are current', () => {
    assert.equal(readFileSync(PATHS.rulesOut, 'utf8'), renderRulesFile(template, uids));
    assert.equal(readFileSync(PATHS.recoveryOut, 'utf8'), renderRulesFile(template, uids, { variant: 'r1-recovery' }));
    assert.equal(readFileSync(PATHS.compatOut, 'utf8'), renderRulesFile(template, uids, { variant: 'r1-compat' }));
    assert.equal(readFileSync(PATHS.freezeOut, 'utf8'), renderRulesFile(template, uids, { variant: 'freeze' }));
    assert.equal(
      readFileSync(PATHS.r2Out, 'utf8'),
      renderRulesFile(readFileSync(PATHS.r2Template, 'utf8'), uids, { variant: 'r2' }),
    );
  });
  it('the R1 family of rules names exactly the configured UIDs, and R2 names none', () => {
    const fromRules = (path) =>
      [...readFileSync(path, 'utf8').matchAll(/auth\.uid === ('(?:[^'\\]|\\.)*')/g)].map((m) => unescapeRuleLiteral(m[1]));
    const norm = (list) => [...new Set(list)].sort();
    for (const path of [PATHS.rulesOut, PATHS.recoveryOut, PATHS.compatOut, PATHS.freezeOut]) {
      assert.deepEqual(norm(fromRules(path)), norm(uids), path);
    }
    assert.deepEqual(fromRules(PATHS.r2Out), [], 'R2 names no allowlisted uid at all');
  });
});

describe('the generator CLI and the deployment guard', () => {
  // SAFETY: the sandbox never copies the repo's .firebaserc (it names the production project)
  // and every spawn gets the isolated environment from support/safety.mjs.
  function sandbox(adminUids) {
    const dir = mkdtempSync(join(tmpdir(), 'allowlist-'));
    for (const rel of ['scripts', 'config', 'functions_dart/bin', 'firebase.json', 'database.rules.json']) {
      const from = resolve(repoRoot, rel);
      if (existsSync(from)) cpSync(from, join(dir, rel), { recursive: true });
    }
    rmSync(join(dir, 'config', 'deployments'), { recursive: true, force: true });
    writeFileSync(join(dir, 'config', 'admin-auth-uids.json'), JSON.stringify({ adminAuthUids: adminUids }));
    writeSandboxFirebaserc(dir);
    assertSandboxProject(dir);
    return dir;
  }
  const run = (dir, ...args) =>
    spawnSync(process.execPath, [join(dir, 'scripts', 'build_admin_allowlist.mjs'), ...args], { encoding: 'utf8', env: sandboxEnv(dir) });
  const withSandbox = (adminUids, fn) => {
    const dir = sandbox(adminUids);
    try {
      return fn(dir);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };

  it('--check fails on an empty list and succeeds with --allow-empty', () => {
    withSandbox([], (dir) => {
      assert.equal(run(dir, '--check').status, 1);
      run(dir, '--allow-empty');
      assert.equal(run(dir, '--check', '--allow-empty').status, 0);
    });
  });

  it('--check detects drift when a UID is added but the outputs are not regenerated', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      assert.equal(run(dir, '--check').status, 0);
      writeFileSync(join(dir, 'config', 'admin-auth-uids.json'), JSON.stringify({ adminAuthUids: [UID_A, UID_B] }));
      const drift = run(dir, '--check');
      assert.equal(drift.status, 1);
      assert.match(drift.stderr, /STALE/);
    });
  });

  it('--check detects a hand-edited recovery ruleset', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      const recoveryPath = join(dir, 'config', 'generated', 'database.rules.r1-recovery.json');
      writeFileSync(recoveryPath, readFileSync(recoveryPath, 'utf8').replace(UID_A, UID_B));
      assert.equal(run(dir, '--check').status, 1);
    });
  });

  it('--check detects a hand-edited compat ruleset, and --check-deploy tells the variants apart', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      const compatPath = join(dir, 'config', 'generated', 'database.rules.r1-compat.json');
      writeFileSync(compatPath, readFileSync(compatPath, 'utf8').replace(UID_A, UID_B));
      assert.equal(run(dir, '--check').status, 1);
      run(dir);
      assert.equal(run(dir, '--check').status, 0);

      run(dir, '--install-rules', '--variant', 'r1-compat');
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1-compat').status, 0);
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1').status, 1, 'compat installed is not R1');
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1-recovery').status, 1, 'compat installed is not recovery');
    });
  });

  it('--check detects a hand-edited freeze or r2 ruleset, and --check-deploy tells all five variants apart', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      for (const name of ['freeze', 'r2']) {
        const path = join(dir, 'config', 'generated', `database.rules.${name}.json`);
        const original = readFileSync(path, 'utf8');
        writeFileSync(path, original.replace('"auth != null"', '"true"'));
        assert.equal(run(dir, '--check').status, 1, `a hand-edited ${name} ruleset must be caught`);
        writeFileSync(path, original);
        assert.equal(run(dir, '--check').status, 0);
      }
      const variants = ['r1', 'r1-recovery', 'r1-compat', 'freeze', 'r2'];
      for (const installed of variants) {
        run(dir, '--install-rules', '--variant', installed);
        for (const asked of variants) {
          assert.equal(
            run(dir, '--check-deploy', '--variant', asked).status,
            asked === installed ? 0 : 1,
            `${installed} installed, ${asked} asked`,
          );
        }
      }
    });
  });

  it('--last-rules-variant reads the deployment log: the last rules entry, ignoring functions, or none', () => {
    withSandbox([UID_A], (dir) => {
      assert.equal(run(dir, '--last-rules-variant').stdout.trim(), 'none');
      const log = join(dir, 'config', 'deployments', 'allowlist-deployments.jsonl');
      mkdirSync(join(dir, 'config', 'deployments'), { recursive: true });
      const line = (kind, variant) => `${JSON.stringify({ kind, variant })}\n`;
      writeFileSync(log, line('rules', 'r1') + line('rules', 'freeze') + line('functions', null));
      assert.equal(run(dir, '--last-rules-variant').stdout.trim(), 'freeze');
    });
  });

  it('refuses malformed UIDs in the config', () => {
    withSandbox(['x'.repeat(129)], (dir) => {
      const r = run(dir);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /Not a valid Firebase UID/);
    });
  });

  it('--check-deploy checks the file Firebase actually ships, and never accepts an empty list', () => {
    withSandbox([], (dir) => {
      const r = run(dir, '--check-deploy', '--allow-empty'); // --allow-empty must not apply to deploys
      assert.equal(r.status, 1);
      assert.match(r.stderr, /empty/);
      assert.equal(run(dir, '--install-rules', '--allow-empty').status, 1);
      assert.equal(run(dir, '--record', 'rules', '--allow-empty').status, 1);
    });
  });

  it('--check-deploy fails while database.rules.json is not the generated rules (for example still open), then passes after --install-rules', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      writeFileSync(join(dir, 'database.rules.json'), '{"rules":{".read":"true",".write":"true"}}\n'); // the open rules
      const before = run(dir, '--check-deploy');
      assert.equal(before.status, 1);
      assert.match(before.stderr, /would ship something else/);
      assert.equal(run(dir, '--install-rules').status, 0);
      const after = run(dir, '--check-deploy');
      assert.equal(after.status, 0, after.stderr);
      assert.match(after.stdout, new RegExp(`allowlist revision ${allowlistRevision([UID_A])}`));
    });
  });

  it('a hand edit to the installed database.rules.json is caught', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      run(dir, '--install-rules');
      const path = join(dir, 'database.rules.json');
      writeFileSync(path, readFileSync(path, 'utf8').replace(`'${UID_A}'`, `'${UID_B}'`));
      assert.equal(run(dir, '--check-deploy').status, 1);
    });
  });

  it('variants are not interchangeable: installed R1 fails the recovery check and vice versa', () => {
    withSandbox([UID_A], (dir) => {
      run(dir);
      run(dir, '--install-rules', '--variant', 'r1');
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1').status, 0);
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1-recovery').status, 1);
      run(dir, '--install-rules', '--variant', 'r1-recovery');
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1-recovery').status, 0);
      assert.equal(run(dir, '--check-deploy', '--variant', 'r1').status, 1);
    });
  });

  it('--record appends one JSON line per rules deployment with the allowlist revision, and refuses anything else', () => {
    withSandbox([UID_A, UID_B], (dir) => {
      run(dir);
      assert.equal(run(dir, '--record', 'rules').status, 0);
      const refused = run(dir, '--record', 'functions');
      assert.notEqual(refused.status, 0, 'the functions no longer use the allowlist');
      assert.match(refused.stderr, /--record must be 'rules'/);
      const lines = readFileSync(join(dir, 'config', 'deployments', 'allowlist-deployments.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
      assert.equal(lines.length, 1);
      assert.equal(lines[0].kind, 'rules');
      assert.equal(lines[0].allowlistRevision, allowlistRevision([UID_A, UID_B]));
      assert.equal(lines[0].adminUidCount, 2);
      assert.equal(lines[0].project, SANDBOX_PROJECT_ID);
      assert.match(lines[0].at, /^\d{4}-\d{2}-\d{2}T/);
      assert.match(lines[0].rulesSha256, /^[0-9a-f]{64}$/);
    });
  });

  it('--revision prints the same id the deployment records use', () => {
    withSandbox([UID_A], (dir) => {
      assert.equal(run(dir, '--revision').stdout.trim(), allowlistRevision([UID_A]));
    });
  });

  it('the guard still fails when invoked through a symlink (it must not silently do nothing)', () => {
    withSandbox([], (dir) => {
      const link = join(dir, 'link.mjs');
      symlinkSync(join(dir, 'scripts', 'build_admin_allowlist.mjs'), link);
      const r = spawnSync(process.execPath, [link, '--check'], { encoding: 'utf8', env: sandboxEnv(dir) });
      assert.equal(r.status, 1);
    });
  });
});
