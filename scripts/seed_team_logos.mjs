#!/usr/bin/env node
// Builds the /TeamLogos seed from team_logos/<teamKey>.svg, one file per team, named by the
// team's key under /Teams (for example "nrl-Broncos.svg").
//
// Like the other production scripts, this only READS and WRITES A FILE. It cannot write to the
// database. Review the patch, then apply it at the root with the Firebase CLI:
//
//   firebase database:update / team-logos-patch.json --project <id>
//
// The /TeamLogos rules must be deployed first (config/database.rules.*.template.json).
//
// Usage:
//   node scripts/seed_team_logos.mjs --patch-out team-logos-patch.json
//   node scripts/seed_team_logos.mjs --file test/data/db.json --patch-out patch.json  # also check coverage
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const LOGO_DIR = resolve(repoRoot, "team_logos");
/** The largest logo the database rules accept, in characters (maxTeamLogoSvgLength in the app). */
export const MAX_SVG_LENGTH = 65536;

/** Every logo in [dir] as { teamKey: svgText }. */
export function readLogos(dir = LOGO_DIR) {
  const logos = {};
  for (const name of readdirSync(dir).filter((file) => file.endsWith(".svg")).sort()) {
    logos[name.slice(0, -".svg".length)] = readFileSync(resolve(dir, name), "utf8").trim();
  }
  return logos;
}

/** Problems that would make the rules refuse a logo, as readable strings. */
export function logoProblems(logos) {
  const problems = [];
  for (const [teamKey, svg] of Object.entries(logos)) {
    if (!/^(afl|nrl)-.+/.test(teamKey)) problems.push(`${teamKey}: not a team key`);
    if (!svg.includes("<svg")) problems.push(`${teamKey}: not an SVG`);
    if (svg.length === 0 || svg.length > MAX_SVG_LENGTH) {
      problems.push(`${teamKey}: ${svg.length} characters, limit ${MAX_SVG_LENGTH}`);
    }
  }
  return problems;
}

/** Which teams in a database export have no logo file, and which files match no team. */
export function coverage(teams, logos) {
  const teamKeys = Object.keys(teams ?? {});
  const logoKeys = new Set(Object.keys(logos));
  return {
    teamsWithoutLogo: teamKeys.filter((key) => !logoKeys.has(key)).sort(),
    logosWithoutTeam: [...logoKeys].filter((key) => !teamKeys.includes(key)).sort(),
  };
}

/** A root-level update writing each logo to /TeamLogos/<teamKey>. */
export function buildPatch(logos, updatedUtc = new Date().toISOString()) {
  return Object.fromEntries(
    Object.entries(logos).map(([teamKey, svg]) => [`TeamLogos/${teamKey}`, { svg, updatedUtc }]),
  );
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--file") args.file = argv[++i];
    else if (argv[i] === "--patch-out") args.patchOut = argv[++i];
    else throw new Error(`Unknown argument: ${argv[i]}`);
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const logos = readLogos();
  const problems = logoProblems(logos);
  if (problems.length > 0) {
    console.error(problems.join("\n"));
    process.exit(1);
  }
  const total = Object.values(logos).reduce((sum, svg) => sum + svg.length, 0);
  console.log(`${Object.keys(logos).length} logos, ${(total / 1024).toFixed(1)} KiB in all`);

  if (args.file) {
    const db = JSON.parse(readFileSync(args.file, "utf8"));
    const { teamsWithoutLogo, logosWithoutTeam } = coverage(db.Teams, logos);
    console.log(`teams without a logo (they show initials): ${teamsWithoutLogo.join(", ") || "none"}`);
    console.log(`logo files with no team in the export: ${logosWithoutTeam.join(", ") || "none"}`);
  }

  if (args.patchOut) {
    writeFileSync(args.patchOut, `${JSON.stringify(buildPatch(logos), null, 2)}\n`);
    console.log(`wrote ${args.patchOut}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
