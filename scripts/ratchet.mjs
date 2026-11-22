#!/usr/bin/env node
// Ratchet check: numbers we want to shrink may fall but never rise.
//
//   node scripts/ratchet.mjs            check the code against the baseline
//   node scripts/ratchet.mjs --update   lower the baseline to what the code is now
//
// The baseline is config/ratchet-baseline.json. `--update` only ever lowers a
// number. Raising one is a decision for the maintainer, made by editing the
// file by hand.

import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

/// A source file longer than this must be listed in the baseline, and a listed
/// file may not grow past the length recorded for it.
export const maxFileLines = 600;

/// Where the file length limit applies. Tests and generated code are left out.
const sizedSources = [
  /^lib\/.*\.dart$/,
  /^packages\/[^/]+\/lib\/.*\.dart$/,
  /^functions_dart\/(lib|bin)\/.*\.dart$/,
  /^functions\/src\/.*\.ts$/,
];
const notSized = [/\.g\.dart$/, /\.freezed\.dart$/, /\.test\.ts$/, /^lib\/firebase_options\.dart$/];

/// Counted patterns. Each counts the lines that match in the files it covers;
/// a line that is only a comment is not counted.
export const countedPatterns = {
  'dynamic in lib': {
    files: /^lib\/.*\.dart$/,
    pattern: /\bdynamic\b/,
  },
  'service locator in view models': {
    files: /^lib\/view_models\/.*\.dart$/,
    pattern: /\bdi<|\bdi\.(register|unregister|isRegistered)/,
  },
  'Provider widgets in lib': {
    files: /^lib\/.*\.dart$/,
    pattern: /\b(ChangeNotifierProvider|MultiProvider|Consumer\d?<|Selector\d?<)/,
  },
};

function isSized(path) {
  return sizedSources.some((re) => re.test(path)) && !notSized.some((re) => re.test(path));
}

function lineCount(text) {
  if (text.length === 0) {
    return 0;
  }
  const lines = text.split('\n').length;
  return text.endsWith('\n') ? lines - 1 : lines;
}

function isCommentOnly(line) {
  return line.trimStart().startsWith('//');
}

/// Measures [sources], a map of repository path to file text.
export function measure(sources) {
  const largeFiles = {};
  const counts = {};
  for (const name of Object.keys(countedPatterns)) {
    counts[name] = 0;
  }
  for (const [path, text] of Object.entries(sources)) {
    if (isSized(path)) {
      const lines = lineCount(text);
      if (lines > maxFileLines) {
        largeFiles[path] = lines;
      }
    }
    for (const [name, {files, pattern}] of Object.entries(countedPatterns)) {
      if (!files.test(path)) {
        continue;
      }
      for (const line of text.split('\n')) {
        if (!isCommentOnly(line) && pattern.test(line)) {
          counts[name] += 1;
        }
      }
    }
  }
  return {largeFiles, counts};
}

/// Compares what the code is now with the baseline. `raised` are failures the
/// code must fix; `lowered` are gains the baseline has not recorded yet.
export function compare(baseline, current) {
  const raised = [];
  const lowered = [];

  for (const [path, lines] of Object.entries(current.largeFiles)) {
    const allowed = baseline.largeFiles[path];
    if (allowed === undefined) {
      raised.push(`${path} is ${lines} lines; a new file may not pass ${maxFileLines}.`);
    } else if (lines > allowed) {
      raised.push(`${path} grew from ${allowed} to ${lines} lines.`);
    } else if (lines < allowed) {
      lowered.push(`${path} shrank from ${allowed} to ${lines} lines.`);
    }
  }
  for (const path of Object.keys(baseline.largeFiles)) {
    if (current.largeFiles[path] === undefined) {
      lowered.push(`${path} is no longer over ${maxFileLines} lines.`);
    }
  }

  for (const [name, count] of Object.entries(current.counts)) {
    const allowed = baseline.counts[name];
    if (allowed === undefined) {
      raised.push(`"${name}" has no baseline; the maintainer adds one by hand.`);
    } else if (count > allowed) {
      raised.push(`"${name}" rose from ${allowed} to ${count}.`);
    } else if (count < allowed) {
      lowered.push(`"${name}" fell from ${allowed} to ${count}.`);
    }
  }
  return {raised, lowered};
}

/// The baseline after recording every gain in [current]. Nothing is raised and
/// nothing new is admitted.
export function loweredBaseline(baseline, current) {
  const largeFiles = {};
  for (const [path, allowed] of Object.entries(baseline.largeFiles)) {
    const lines = current.largeFiles[path];
    if (lines !== undefined) {
      largeFiles[path] = Math.min(allowed, lines);
    }
  }
  const counts = {};
  for (const [name, allowed] of Object.entries(baseline.counts)) {
    const count = current.counts[name];
    counts[name] = count === undefined ? allowed : Math.min(allowed, count);
  }
  return {largeFiles: sortKeys(largeFiles), counts: sortKeys(counts)};
}

function sortKeys(object) {
  // Plain code-unit order, so the file reads the same on every machine.
  return Object.fromEntries(
    Object.entries(object).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
  );
}

function readSources(root) {
  const listed = execFileSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024},
  );
  const sources = {};
  for (const path of listed.split('\0')) {
    const wanted =
      isSized(path) || Object.values(countedPatterns).some(({files}) => files.test(path));
    if (!wanted || !existsSync(join(root, path))) {
      continue;
    }
    sources[path] = readFileSync(join(root, path), 'utf8');
  }
  return sources;
}

function main() {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const baselinePath = join(root, 'config', 'ratchet-baseline.json');
  const baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
  const current = measure(readSources(root));
  const {raised, lowered} = compare(baseline, current);
  const update = process.argv.includes('--update');

  if (update && lowered.length > 0) {
    writeFileSync(
      baselinePath,
      `${JSON.stringify(loweredBaseline(baseline, current), null, 2)}\n`,
    );
    console.log('Baseline lowered:');
    for (const line of lowered) {
      console.log(`  ${line}`);
    }
  }

  if (raised.length > 0) {
    console.error('Ratchet failed. These may fall but not rise:');
    for (const line of raised) {
      console.error(`  ${line}`);
    }
    console.error(
      'Put the new behaviour somewhere else or shrink something first. ' +
        'Only the maintainer raises a number in config/ratchet-baseline.json.',
    );
    process.exit(1);
  }

  if (!update && lowered.length > 0) {
    console.error('Ratchet baseline is out of date. These improved:');
    for (const line of lowered) {
      console.error(`  ${line}`);
    }
    console.error('Record the gain: node scripts/ratchet.mjs --update');
    process.exit(1);
  }

  console.log('Ratchet passed.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
