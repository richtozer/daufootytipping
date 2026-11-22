// Proves the isolation itself, and enforces it across the whole test directory.
// See support/no_production.mjs, support/safety.mjs and DESIGN-database-rules-phase3.md section 8.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { PRODUCTION_PROJECT_ID, sandboxEnv } from './support/safety.mjs';

const here = import.meta.dirname;
const sandboxDir = mkdtempSync(join(tmpdir(), 'safety-'));
const env = sandboxEnv(sandboxDir);
after(() => rmSync(sandboxDir, { recursive: true, force: true }));

/** Run a snippet in a Node child that has the guard preloaded (through NODE_OPTIONS), as every test child does. */
function inGuardedChild(code) {
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8', env, timeout: 30_000 });
  return { ...r, out: `${r.stdout}${r.stderr}` };
}

describe('the preload blocks all non-loopback network access', () => {
  it('a raw TCP connection to a public host is refused', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      try { net.connect(443, 'example.com'); console.log('CONNECTED'); } catch (e) { console.log('BLOCKED ' + e.message); }
    `);
    assert.match(r.out, /BLOCKED NO_PRODUCTION_GUARD/);
    assert.doesNotMatch(r.out, /CONNECTED/);
  });

  it('an IP-literal connection to a public address is refused', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      try { net.connect({ host: '8.8.8.8', port: 53 }); console.log('CONNECTED'); } catch (e) { console.log('BLOCKED ' + e.message); }
    `);
    assert.match(r.out, /BLOCKED NO_PRODUCTION_GUARD/);
  });

  it('fetch to a public https URL is refused', () => {
    const r = inGuardedChild(`
      try { await fetch('https://example.com/'); console.log('FETCHED'); } catch (e) { console.log('BLOCKED ' + e.message + ' | ' + (e.cause?.message ?? '')); }
    `);
    assert.match(r.out, /NO_PRODUCTION_GUARD/);
    assert.doesNotMatch(r.out, /FETCHED/);
  });

  it('DNS lookups of non-loopback names are refused (callback and promise forms)', () => {
    const r = inGuardedChild(`
      import dns from 'node:dns';
      dns.lookup('example.com', (e) => console.log('CB ' + (e ? e.message : 'RESOLVED')));
      try { await dns.promises.lookup('example.com'); console.log('PROMISE RESOLVED'); } catch (e) { console.log('PROMISE ' + e.message); }
    `);
    assert.match(r.out, /CB NO_PRODUCTION_GUARD/);
    assert.match(r.out, /PROMISE NO_PRODUCTION_GUARD/);
  });

  it('loopback still works (the emulators run there)', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      const server = net.createServer((s) => s.end('hi')).listen(0, '127.0.0.1', () => {
        const c = net.connect(server.address().port, '127.0.0.1');
        c.on('data', (d) => { console.log('LOOPBACK OK ' + d); c.destroy(); server.close(); });
      });
    `);
    assert.match(r.out, /LOOPBACK OK hi/);
  });

  it('hostnames that merely START with 127. are not loopback (connect and DNS)', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      import dns from 'node:dns';
      try { net.connect(80, '127.example.com'); console.log('CONNECTED'); } catch (e) { console.log('CONNECT ' + e.message); }
      dns.lookup('127.example.com', (e) => console.log('DNS ' + (e ? e.message : 'RESOLVED')));
    `);
    assert.match(r.out, /CONNECT NO_PRODUCTION_GUARD/);
    assert.match(r.out, /DNS NO_PRODUCTION_GUARD/);
  });

  it('0.0.0.0 and :: are not loopback addresses and are refused', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      for (const host of ['0.0.0.0', '::', '[::]']) {
        try { net.connect(80, host); console.log('CONNECTED ' + host); } catch (e) { console.log('REFUSED ' + host); }
      }
    `);
    assert.match(r.out, /REFUSED 0\.0\.0\.0/);
    assert.match(r.out, /REFUSED ::/);
    assert.doesNotMatch(r.out, /CONNECTED/);
  });

  it('real loopback addresses and the exact name localhost pass the guard (the OS then answers)', () => {
    const r = inGuardedChild(`
      import net from 'node:net';
      for (const host of ['127.0.0.1', '127.1.2.3', '::1', '::ffff:127.0.0.1', 'localhost', 'LOCALHOST']) {
        try { const s = net.connect(1, host); s.on('error', () => {}); s.destroy(); console.log('PASSED ' + host); } catch (e) { console.log('REFUSED ' + host + ' ' + e.message); }
      }
    `);
    for (const host of ['127.0.0.1', '127.1.2.3', '::1', '::ffff:127.0.0.1', 'localhost', 'LOCALHOST']) {
      assert.match(r.out, new RegExp(`PASSED ${host.replace(/[.:]/g, '\\$&')}`), host);
    }
  });

  it('the guard also covers grandchildren: a Node process spawned by a Node child inherits it', () => {
    const r = inGuardedChild(`
      import { spawnSync } from 'node:child_process';
      const g = spawnSync(process.execPath, ['--input-type=module', '-e', "import net from 'node:net'; try { net.connect(443, 'example.com'); console.log('GRANDCHILD CONNECTED'); } catch (e) { console.log('GRANDCHILD ' + e.message); }"], { encoding: 'utf8', env: process.env });
      console.log(g.stdout + g.stderr);
    `);
    assert.match(r.out, /GRANDCHILD NO_PRODUCTION_GUARD/);
  });
});

describe('the preload blocks real firebase and gcloud executables', () => {
  const attempts = {
    'spawnSync firebase': "spawnSync('firebase', ['--version'])",
    'spawnSync gcloud': "spawnSync('gcloud', ['--version'])",
    'execFileSync firebase by absolute path outside the temp dir': "execFileSync('/nonexistent-sandbox/bin/firebase', ['deploy'])",
    'execSync with firebase in a shell string': "execSync('firebase deploy --only database')",
    'execSync with gcloud after a separator': "execSync('echo hi; gcloud auth list')",
    'spawn with shell:true': "spawn('firebase deploy', { shell: true })",
    'npx firebase': "spawnSync('npx', ['firebase', 'deploy'])",
    'npx firebase-tools': "spawnSync('npx', ['firebase-tools', 'deploy'])",
  };
  for (const [label, call] of Object.entries(attempts)) {
    it(`refuses: ${label}`, () => {
      const r = inGuardedChild(`
        import { spawn, spawnSync, execSync, execFileSync } from 'node:child_process';
        try { ${call}; console.log('RAN'); } catch (e) { console.log('REFUSED ' + e.message); }
      `);
      assert.match(r.out, /REFUSED NO_PRODUCTION_GUARD/, r.out);
      assert.doesNotMatch(r.out, /RAN\b/);
    });
  }

  it('allows ordinary commands and ONLY the exact sandbox stub', () => {
    const r = inGuardedChild(`
      import { spawnSync } from 'node:child_process';
      console.log(spawnSync(process.execPath, ['-e', 'console.log("node-ok")'], { encoding: 'utf8' }).stdout.trim());
      console.log('STUB:' + spawnSync(process.env.FIREBASE_BIN, ['use'], { encoding: 'utf8', cwd: ${JSON.stringify(sandboxDir)} }).status);
    `);
    assert.match(r.out, /node-ok/);
    assert.match(r.out, /STUB:0/);
  });

  it('a byte-identical copy of the stub elsewhere in the temp directory is refused (location is not enough)', () => {
    const copyDir = mkdtempSync(join(tmpdir(), 'stubcopy-'));
    try {
      const copy = join(copyDir, 'firebase');
      copyFileSync(env.FIREBASE_BIN, copy);
      chmodSync(copy, 0o755);
      const r = inGuardedChild(`
        import { spawnSync } from 'node:child_process';
        try { spawnSync(${JSON.stringify(copy)}, ['use']); console.log('RAN'); } catch (e) { console.log('REFUSED ' + e.message); }
      `);
      assert.match(r.out, /REFUSED NO_PRODUCTION_GUARD/);
    } finally {
      rmSync(copyDir, { recursive: true, force: true });
    }
  });

  it('a modified stub at the exact stub path is refused (identity is by content)', () => {
    const modDir = mkdtempSync(join(tmpdir(), 'stubmod-'));
    try {
      const modified = join(modDir, 'firebase');
      writeFileSync(modified, `${readFileSync(env.FIREBASE_BIN, 'utf8')}\n# tampered\n`);
      chmodSync(modified, 0o755);
      const r = spawnSync(process.execPath, ['--input-type=module', '-e', `
        import { spawnSync } from 'node:child_process';
        try { spawnSync(${JSON.stringify(modified)}, ['use']); console.log('RAN'); } catch (e) { console.log('REFUSED ' + e.message); }
      `], { encoding: 'utf8', env: { ...env, NO_PRODUCTION_STUB: modified }, timeout: 30_000 });
      assert.match(`${r.stdout}${r.stderr}`, /REFUSED NO_PRODUCTION_GUARD/);
    } finally {
      rmSync(modDir, { recursive: true, force: true });
    }
  });

  it('gcloud is never allowed, even as a stub', () => {
    const gcloudDir = mkdtempSync(join(tmpdir(), 'gcloudstub-'));
    try {
      const fake = join(gcloudDir, 'gcloud');
      writeFileSync(fake, '#!/bin/sh\necho hi\n');
      chmodSync(fake, 0o755);
      const r = inGuardedChild(`
        import { spawnSync } from 'node:child_process';
        try { spawnSync(${JSON.stringify(fake)}, ['--version']); console.log('RAN'); } catch (e) { console.log('REFUSED ' + e.message); }
      `);
      assert.match(r.out, /REFUSED NO_PRODUCTION_GUARD/);
    } finally {
      rmSync(gcloudDir, { recursive: true, force: true });
    }
  });
});

describe('sandboxEnv fails closed outside the OS boundary', () => {
  it('refuses to build an environment when OS_BOUNDARY is not set', () => {
    const dir = mkdtempSync(join(tmpdir(), 'noboundary-'));
    try {
      const r = spawnSync(process.execPath, ['--input-type=module', '-e', `
        import { sandboxEnv } from ${JSON.stringify(new URL('./support/safety.mjs', import.meta.url).href)};
        try { sandboxEnv(${JSON.stringify(dir)}); console.log('BUILT'); } catch (e) { console.log('REFUSED ' + e.message); }
      `], { encoding: 'utf8', env: { ...env, OS_BOUNDARY: '' }, timeout: 30_000 });
      assert.match(`${r.stdout}${r.stderr}`, /REFUSED SAFETY: not inside the OS boundary/);
      assert.doesNotMatch(`${r.stdout}${r.stderr}`, /BUILT/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('repo-wide rules for tests', () => {
  const testFiles = readdirSync(here).filter((f) => f.endsWith('.test.mjs'));
  const read = (f) => readFileSync(join(here, f), 'utf8');

  it('no test file names the production project (only support/safety.mjs spells it out)', () => {
    assert.ok(testFiles.length > 5);
    for (const file of testFiles) {
      assert.ok(!read(file).includes(PRODUCTION_PROJECT_ID), `${file} names the production project`);
    }
    for (const file of readdirSync(join(here, 'support')).filter((f) => f !== 'safety.mjs')) {
      assert.ok(!readFileSync(join(here, 'support', file), 'utf8').includes(PRODUCTION_PROJECT_ID), `support/${file}`);
    }
  });

  it('no test hands the whole process environment to a spawned process', () => {
    for (const file of testFiles) {
      // This file contains these patterns as text, and one snippet hands a guarded CHILD's own
      // (already sandboxed) environment to a grandchild on purpose.
      if (file === 'safety.test.mjs') continue;
      const text = read(file);
      assert.ok(!/\.\.\.process\.env/.test(text), `${file} spreads process.env`);
      assert.ok(!/env:\s*process\.env\b/.test(text), `${file} passes process.env as env`);
    }
  });

  it('every test file that spawns a process builds its environment with sandboxEnv', () => {
    for (const file of testFiles) {
      if (file === 'safety.test.mjs') continue;
      const text = read(file);
      if (!/spawnSync|spawn\(|execFileSync|execSync/.test(text)) continue;
      assert.ok(/sandboxEnv/.test(text), `${file} spawns processes without sandboxEnv`);
    }
  });

  it('no test names a user npm bin or a gcloud/firebase configuration directory', () => {
    for (const file of testFiles) {
      if (file === 'deploy_scripts.test.mjs' || file === 'deploy_functions.test.mjs') continue; // name a decoy ~/.npm-global/bin inside a sandbox HOME on purpose
      if (file === 'os_boundary.test.mjs') continue; // names the credential stores to prove they are unreadable
      if (file === 'safety.test.mjs') continue; // holds the pattern as text
      const text = read(file);
      assert.ok(!/\.npm-global|\.config\/(gcloud|configstore)|firebase-tools\.json/.test(text), file);
    }
  });

  it('the npm scripts preload the guard into the node processes that run the tests', () => {
    const scripts = JSON.parse(readFileSync(resolve(here, 'package.json'), 'utf8')).scripts;
    for (const name of ['test', 'test:unit', 'test:live']) {
      assert.match(scripts[name], /NODE_OPTIONS=--import=\.\/support\/no_production\.mjs/, `npm run ${name}`);
    }
  });

  it('the live and emulator test commands use a demo- project', () => {
    const scripts = JSON.parse(readFileSync(resolve(here, 'package.json'), 'utf8')).scripts;
    for (const [name, command] of Object.entries(scripts)) {
      for (const [, project] of command.matchAll(/--project\s+([^\s"]+)/g)) {
        assert.match(project, /^demo-/, `npm run ${name} uses project ${project}`);
      }
      assert.ok(!command.includes(PRODUCTION_PROJECT_ID), `npm run ${name}`);
    }
  });

  it('this process is itself guarded when run through npm (the preload is active)', () => {
    // When run via `npm test` NODE_OPTIONS carries the preload; the guard module marks itself by
    // refusing the connection below. Skipped only when run by hand without the preload.
    if (!String(process.env.NODE_OPTIONS ?? '').includes('no_production.mjs')) return;
    const net = process.getBuiltinModule('node:net');
    assert.throws(() => net.connect(443, 'example.com'), /NO_PRODUCTION_GUARD/);
  });
});
