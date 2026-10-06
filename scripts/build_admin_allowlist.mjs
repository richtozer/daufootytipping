#!/usr/bin/env node
// Generates everything that depends on the R1 admin allowlist from ONE source,
// config/admin-auth-uids.json (DESIGN-database-rules.md, D12), and guards the
// deployment of the artifacts Firebase actually ships.
//
// Outputs (all derived from the one list):
//   config/generated/database.rules.r1.json           the R1 rules
//   config/generated/database.rules.r1-recovery.json  R1 minus its validation strictness and
//                                                     plus legacy-Stats compatibility; every
//                                                     allowlist and identity protection kept
//   functions_dart/bin/admin_allowlist.g.dart         compile-time constant for the Dart
//                                                     admin endpoints
//
// Modes:
//   (none)                      write all outputs
//   --check                     exit 1 if any output is stale, or the list is empty
//   --check-deploy [--variant]  exit 1 unless database.rules.json (the file `firebase deploy
//                               --only database` ships, per firebase.json) is byte-identical to
//                               the generated rules for the variant, and the list is non-empty
//   --install-rules [--variant] copy the generated rules over database.rules.json
//   --record <rules|functions> [--variant]
//                               append a line to config/deployments/allowlist-deployments.jsonl
//   --revision                  print the allowlist revision
//   --allow-empty               only for --check/generation during development; never for deploy
//
// An EMPTY list is refused for anything that could be deployed: with no admins every admin-only
// write is denied, which would lock admins out of production.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..");

export const PATHS = {
  config: resolve(repoRoot, "config/admin-auth-uids.json"),
  template: resolve(repoRoot, "config/database.rules.r1.template.json"),
  rulesOut: resolve(repoRoot, "config/generated/database.rules.r1.json"),
  recoveryOut: resolve(repoRoot, "config/generated/database.rules.r1-recovery.json"),
  dartOut: resolve(repoRoot, "functions_dart/bin/admin_allowlist.g.dart"),
  firebaseJson: resolve(repoRoot, "firebase.json"),
  deployLog: resolve(repoRoot, "config/deployments/allowlist-deployments.jsonl"),
};

export const VARIANTS = ["r1", "r1-recovery"];

// Firebase accepts any UID of 1 to 128 characters (28 alphanumerics is only the format it
// generates), so that is the rule. Control characters are refused; everything else is escaped.
const UID_MAX = 128;
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

export const SIGNED_IN_EXPR =
  "(auth != null && auth.token.firebase.sign_in_provider !== 'anonymous')";

/** Validate and normalise the list. Throws on anything unsafe to inline. */
export function validateUids(uids, { allowEmpty = false } = {}) {
  if (!Array.isArray(uids)) throw new Error("adminAuthUids must be an array");
  const seen = new Set();
  for (const uid of uids) {
    if (typeof uid !== "string" || uid.length < 1 || uid.length > UID_MAX || CONTROL_CHARS.test(uid)) {
      throw new Error(`Not a valid Firebase UID (1 to ${UID_MAX} characters, no control characters): ${JSON.stringify(uid)}`);
    }
    if (seen.has(uid)) throw new Error(`Duplicate UID: ${uid}`);
    seen.add(uid);
  }
  if (uids.length === 0 && !allowEmpty) {
    throw new Error(
      "adminAuthUids is empty. Verify the admin UIDs (scripts/verify_admin_auth_uids.mjs) and add them to config/admin-auth-uids.json.",
    );
  }
  return [...uids];
}

/** A stable identifier for exactly this list, recorded with every deployment. */
export function allowlistRevision(uids) {
  return createHash("sha256").update(JSON.stringify([...uids].sort())).digest("hex").slice(0, 12);
}

/** RTDB rules string literal: single-quoted, with backslash and quote escaped. */
export const ruleLiteral = (uid) => `'${uid.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;
export const unescapeRuleLiteral = (literal) => literal.slice(1, -1).replace(/\\(.)/g, "$1");

/** Dart string literal: single-quoted, with backslash, quote and `$` escaped. */
export const dartLiteral = (uid) => `'${uid.replaceAll("\\", "\\\\").replaceAll("'", "\\'").replaceAll("$", "\\$")}'`;
export const unescapeDartLiteral = unescapeRuleLiteral;

export function isAdminExpr(uids) {
  if (uids.length === 0) return "false";
  return `(auth != null && (${uids.map((uid) => `auth.uid === ${ruleLiteral(uid)}`).join(" || ")}))`;
}

function substitute(templateText, uids) {
  // Substitute through JSON so the expression is escaped for the JSON string it lives in.
  const asJsonFragment = (text) => JSON.stringify(text).slice(1, -1);
  const text = templateText
    .replaceAll("{{IS_ADMIN}}", asJsonFragment(isAdminExpr(uids)))
    .replaceAll("{{SIGNED_IN}}", asJsonFragment(SIGNED_IN_EXPR));
  if (text.includes("{{")) throw new Error("Unresolved placeholder left in the rules template");
  return JSON.parse(text);
}

const LEGACY_STATS_BRANCHES = [
  "game_stats_v3",
  "live_scores_v3",
  "round_stats_v3",
  "scoring_audit_v3",
  "admin_scoring_freshness_probe",
];

/**
 * The recovery ruleset: what to deploy when R1 breaks a COMPATIBILITY path, instead of
 * reopening the database. It relaxes only validation strictness and re-admits the legacy Stats
 * writers of 1.3.x clients. It keeps every protection that matters: allowlisted admins for the
 * admin areas, immutable identity fields, no anonymous writes, no parent wipes, backend-owned
 * Stats branches closed, default deny.
 */
export function relaxForRecovery(rules) {
  const out = structuredClone(rules);
  const dropValidate = (node, keep = []) => {
    for (const key of Object.keys(node)) {
      if (key === ".validate" && !keep.includes(".validate")) delete node[key];
    }
  };

  // Tips: any shape from a signed-in user (still leaf-level, tipper-level delete still admin only).
  const game = out.rules.AllTips.$comp.$tipperId.$game;
  for (const key of Object.keys(game)) if (key !== ".write") delete game[key];

  // Tipper records: keep the required identity children and the identity-field validation;
  // drop the strictness on profile leaves and unknown keys.
  const tipper = out.rules.AllTippers.$tipperId;
  for (const field of ["name", "email", "logon", "photoURL", "isAnonymous", "acctCreatedUTC", "acctLoggedOnUTC"]) {
    dropValidate(tipper[field]);
  }
  delete tipper.$other;

  // Live scores: no shape check.
  const live = out.rules.Stats.$comp.live_scores_backend_v1.$game;
  dropValidate(live.current);
  dropValidate(live.history.$key);

  // Legacy 1.3.x Stats writers, signed-in only.
  for (const branch of LEGACY_STATS_BRANCHES) {
    out.rules.Stats.$comp[branch] = { ".write": SIGNED_IN_EXPR };
  }
  return out;
}

/** Substitute the allowlist into the template. Returns a rules object for the variant. */
export function buildRules(templateText, uids, { variant = "r1" } = {}) {
  if (!VARIANTS.includes(variant)) throw new Error(`Unknown variant: ${variant}`);
  const rules = substitute(templateText, uids);
  return variant === "r1-recovery" ? relaxForRecovery(rules) : rules;
}

export function renderRulesFile(templateText, uids, options = {}) {
  return `${JSON.stringify(buildRules(templateText, uids, options), null, 2)}\n`;
}

export function renderDartAllowlist(uids) {
  const items = uids.map((uid) => `  ${dartLiteral(uid)},`).join("\n");
  return `// GENERATED by scripts/build_admin_allowlist.mjs from config/admin-auth-uids.json.
// Do not edit. Temporary R1 admin allowlist (DESIGN-database-rules.md D12);
// deleted when the bidirectional AuthIndex check goes live (R2).

/// Identifies exactly this allowlist; recorded with every deployment.
const String adminAllowlistRevision = '${allowlistRevision(uids)}';

/// Firebase Auth UIDs allowed to call the admin endpoints during R1.
const Set<String> adminAuthUids = <String>{${items ? `\n${items}\n` : ""}};
`;
}

export function loadConfig(path = PATHS.config) {
  return JSON.parse(readFileSync(path, "utf8")).adminAuthUids;
}

const outputFor = (variant) => (variant === "r1-recovery" ? PATHS.recoveryOut : PATHS.rulesOut);

/** The rules file Firebase deploys, per firebase.json. */
export function deployedRulesPath() {
  const config = JSON.parse(readFileSync(PATHS.firebaseJson, "utf8"));
  const rules = config.database?.rules;
  if (typeof rules !== "string") throw new Error("firebase.json has no database.rules entry");
  return resolve(repoRoot, rules);
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

function git(...args) {
  try {
    return execFileSync("git", args, { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
}

function parseArgs(argv) {
  const flags = new Set();
  const values = {};
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (["--variant", "--record"].includes(a)) values[a] = argv[(i += 1)];
    else flags.add(a);
  }
  return { flags, values };
}

function main() {
  const { flags, values } = parseArgs(process.argv.slice(2));
  const variant = values["--variant"] ?? "r1";
  if (!VARIANTS.includes(variant)) throw new Error(`--variant must be one of: ${VARIANTS.join(", ")}`);

  const deployMode = flags.has("--check-deploy") || flags.has("--install-rules") || values["--record"] !== undefined;
  // The empty-list escape hatch never applies to anything that could be deployed.
  const allowEmpty = flags.has("--allow-empty") && !deployMode;
  const uids = validateUids(loadConfig(), { allowEmpty });
  const revision = allowlistRevision(uids);
  const template = readFileSync(PATHS.template, "utf8");

  if (flags.has("--revision")) {
    console.log(revision);
    return;
  }

  if (flags.has("--check-deploy")) {
    const target = deployedRulesPath();
    const expected = renderRulesFile(template, uids, { variant });
    const actual = existsSync(target) ? readFileSync(target, "utf8") : null;
    if (actual !== expected) {
      throw new Error(
        `${target} is not the generated ${variant} rules for the current allowlist, so \`firebase deploy --only database\` would ship something else. Run: node scripts/build_admin_allowlist.mjs --install-rules --variant ${variant}`,
      );
    }
    console.log(`database rules check passed: ${variant}, allowlist revision ${revision} (${uids.length} admin UID(s)), rules sha256 ${sha256(expected).slice(0, 12)}`);
    return;
  }

  if (flags.has("--install-rules")) {
    const target = deployedRulesPath();
    writeFileSync(target, renderRulesFile(template, uids, { variant }));
    console.log(`installed ${variant} rules (allowlist revision ${revision}) at ${target}`);
    return;
  }

  if (values["--record"] !== undefined) {
    const kind = values["--record"];
    if (!["rules", "functions"].includes(kind)) throw new Error("--record must be 'rules' or 'functions'");
    const rulesText = renderRulesFile(template, uids, { variant });
    const entry = {
      at: new Date().toISOString(),
      kind,
      variant: kind === "rules" ? variant : null,
      project: JSON.parse(readFileSync(resolve(repoRoot, ".firebaserc"), "utf8")).projects?.default ?? null,
      commit: git("rev-parse", "HEAD") || null,
      branch: git("rev-parse", "--abbrev-ref", "HEAD") || null,
      dirty: git("status", "--porcelain") !== "",
      allowlistRevision: revision,
      adminUidCount: uids.length,
      rulesSha256: kind === "rules" ? sha256(rulesText) : null,
    };
    mkdirSync(dirname(PATHS.deployLog), { recursive: true });
    appendFileSync(PATHS.deployLog, `${JSON.stringify(entry)}\n`);
    console.log(`recorded ${kind} deployment with allowlist revision ${revision} in ${PATHS.deployLog}`);
    return;
  }

  const outputs = [
    [PATHS.rulesOut, renderRulesFile(template, uids, { variant: "r1" })],
    [PATHS.recoveryOut, renderRulesFile(template, uids, { variant: "r1-recovery" })],
    [PATHS.dartOut, renderDartAllowlist(uids)],
  ];

  const check = flags.has("--check");
  let stale = false;
  for (const [path, content] of outputs) {
    const current = existsSync(path) ? readFileSync(path, "utf8") : null;
    if (check) {
      if (current !== content) {
        console.error(`STALE: ${path} does not match config/admin-auth-uids.json`);
        stale = true;
      }
    } else {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, content);
      console.log(`wrote ${path}`);
    }
  }
  if (check) {
    if (stale) process.exit(1);
    console.log(`allowlist outputs are up to date: revision ${revision} (${uids.length} admin UID(s))`);
  } else {
    console.log(`allowlist revision ${revision}`);
  }
}

// Compare real paths: invoked through a symlink, argv[1] and import.meta.url differ
// textually, and silently doing nothing (exit 0) would let the deploy guard pass.
function isEntryPoint() {
  if (!process.argv[1]) return false;
  try {
    return import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  try {
    main();
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  }
}
