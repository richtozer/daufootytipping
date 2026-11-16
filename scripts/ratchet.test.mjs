import assert from 'node:assert/strict';
import {test} from 'node:test';

import {compare, loweredBaseline, maxFileLines, measure} from './ratchet.mjs';

const lines = (count) => 'x\n'.repeat(count);

test('measures only source files over the limit', () => {
  const current = measure({
    'lib/big.dart': lines(maxFileLines + 1),
    'lib/at_limit.dart': lines(maxFileLines),
    'test/huge_test.dart': lines(5000),
    'lib/models/thing.g.dart': lines(5000),
    'functions/src/big.test.ts': lines(5000),
    'functions_dart/bin/server.dart': lines(700),
  });

  assert.deepEqual(current.largeFiles, {
    'lib/big.dart': maxFileLines + 1,
    'functions_dart/bin/server.dart': 700,
  });
});

test('counts matching lines in the covered files, skipping comment lines', () => {
  const current = measure({
    'lib/a.dart': [
      'Map<String, dynamic> row = {};',
      '// dynamic is mentioned here only',
      'final dynamicName = 1;',
      'ChangeNotifierProvider(create: (_) => x);',
      'Consumer<Foo>(builder: build);',
    ].join('\n'),
    'lib/view_models/b.dart': 'final t = di<Tippers>();\ndi.registerSingleton(x);',
    'lib/pages/c.dart': 'final t = di<Tippers>();',
    'functions_dart/lib/d.dart': 'dynamic db;',
  });

  assert.deepEqual(current.counts, {
    'dynamic in lib': 1,
    'service locator in view models': 2,
    'Provider widgets in lib': 2,
  });
});

const baseline = {
  largeFiles: {'lib/big.dart': 800, 'lib/other.dart': 700},
  counts: {'dynamic in lib': 10},
};

test('passes when nothing moved', () => {
  const result = compare(baseline, {
    largeFiles: {'lib/big.dart': 800, 'lib/other.dart': 700},
    counts: {'dynamic in lib': 10},
  });

  assert.deepEqual(result, {raised: [], lowered: []});
});

test('reports a listed file that grew, a new large file and a count that rose', () => {
  const result = compare(baseline, {
    largeFiles: {'lib/big.dart': 801, 'lib/other.dart': 700, 'lib/new.dart': 601},
    counts: {'dynamic in lib': 11},
  });

  assert.equal(result.raised.length, 3);
  assert.match(result.raised[0], /lib\/big\.dart grew from 800 to 801/);
  assert.match(result.raised[1], /lib\/new\.dart is 601 lines/);
  assert.match(result.raised[2], /rose from 10 to 11/);
  assert.deepEqual(result.lowered, []);
});

test('reports gains so the baseline can record them', () => {
  const result = compare(baseline, {
    largeFiles: {'lib/big.dart': 750},
    counts: {'dynamic in lib': 8},
  });

  assert.deepEqual(result.raised, []);
  assert.equal(result.lowered.length, 3);
});

test('a count with no baseline fails rather than being admitted', () => {
  const result = compare(baseline, {
    largeFiles: {},
    counts: {'dynamic in lib': 10, 'something new': 4},
  });

  assert.match(result.raised[0], /"something new" has no baseline/);
});

test('updating lowers the baseline and never raises or admits anything', () => {
  const updated = loweredBaseline(baseline, {
    largeFiles: {'lib/big.dart': 900, 'lib/new.dart': 650},
    counts: {'dynamic in lib': 12},
  });
  assert.deepEqual(updated, {
    largeFiles: {'lib/big.dart': 800},
    counts: {'dynamic in lib': 10},
  });

  const lowered = loweredBaseline(baseline, {
    largeFiles: {'lib/big.dart': 640, 'lib/other.dart': 700},
    counts: {'dynamic in lib': 7},
  });
  assert.deepEqual(lowered, {
    largeFiles: {'lib/big.dart': 640, 'lib/other.dart': 700},
    counts: {'dynamic in lib': 7},
  });
});
