import assert from "node:assert/strict";
import { test } from "node:test";

import { MAX_SVG_LENGTH, buildPatch, coverage, logoProblems, readLogos } from "./seed_team_logos.mjs";

test("every checked-in logo passes the rules' checks", () => {
  const logos = readLogos();
  assert.ok(Object.keys(logos).length >= 35);
  assert.deepEqual(logoProblems(logos), []);
});

test("problems name the bad key, the non-SVG and the oversized logo", () => {
  const problems = logoProblems({
    "Broncos": "<svg/>",
    "nrl-Text": "hello",
    "afl-Huge": `<svg>${"x".repeat(MAX_SVG_LENGTH)}</svg>`,
  });
  assert.equal(problems.length, 3);
  assert.match(problems[0], /^Broncos: not a team key/);
  assert.match(problems[1], /^nrl-Text: not an SVG/);
  assert.match(problems[2], /^afl-Huge: \d+ characters/);
});

test("coverage lists teams with no logo and logos with no team", () => {
  const result = coverage(
    { "nrl-Broncos": {}, "nrl-Perth Bears": {} },
    { "nrl-Broncos": "<svg/>", "afl-Old": "<svg/>" },
  );
  assert.deepEqual(result, { teamsWithoutLogo: ["nrl-Perth Bears"], logosWithoutTeam: ["afl-Old"] });
});

test("the patch writes each logo under TeamLogos with one timestamp", () => {
  const patch = buildPatch({ "nrl-Broncos": "<svg/>", "afl-Carlton": "<svg/>" }, "2026-11-15T00:00:00.000Z");
  assert.deepEqual(patch, {
    "TeamLogos/nrl-Broncos": { svg: "<svg/>", updatedUtc: "2026-11-15T00:00:00.000Z" },
    "TeamLogos/afl-Carlton": { svg: "<svg/>", updatedUtc: "2026-11-15T00:00:00.000Z" },
  });
});
