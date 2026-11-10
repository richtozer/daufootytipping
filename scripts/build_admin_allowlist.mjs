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
//   config/generated/database.rules.r1-compat.json    R1 plus exactly the two reads the R2 client
//                                                     needs (own AuthIndex entry, own TipperPrivate
//                                                     record, admins read TipperPrivate); no new
//                                                     write permission (DESIGN-database-rules-phase4.md)
//   config/generated/database.rules.freeze.json       R1-compat with every identity-bearing write closed
//                                                     to all clients, admins included (cutover step A1)
//   config/generated/database.rules.r2.json           the final rules, from their own template
//                                                     (config/database.rules.r2.template.json). They do
//                                                     NOT use the allowlist: an admin is the validated
//                                                     private role, checked through AuthIndex both ways.
//
// The functions do NOT use the allowlist: an administrator there is the same validated private role
// the R2 rules use (functions_dart/lib/identity/admin_gate.dart). The list is only for the R1 family of
// rulesets (which stay as the rollback target) and the offline identity backfill.
//
// Modes:
//   (none)                      write all outputs
//   --check                     exit 1 if any output is stale, or the list is empty
//   --check-deploy [--variant]  exit 1 unless database.rules.json (the file `firebase deploy
//                               --only database` ships, per firebase.json) is byte-identical to
//                               the generated rules for the variant, and the list is non-empty
//   --install-rules [--variant] copy the generated rules over database.rules.json
//   --record rules [--variant]  append a line to config/deployments/allowlist-deployments.jsonl
//   --revision                  print the allowlist revision
//   --last-rules-variant        print the variant of the last rules deployment in the deployment log, or
//                               `none`; the deploy script uses it to keep the cutover rulesets in order
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
  r2Template: resolve(repoRoot, "config/database.rules.r2.template.json"),
  rulesOut: resolve(repoRoot, "config/generated/database.rules.r1.json"),
  recoveryOut: resolve(repoRoot, "config/generated/database.rules.r1-recovery.json"),
  compatOut: resolve(repoRoot, "config/generated/database.rules.r1-compat.json"),
  freezeOut: resolve(repoRoot, "config/generated/database.rules.freeze.json"),
  r2Out: resolve(repoRoot, "config/generated/database.rules.r2.json"),
  firebaseJson: resolve(repoRoot, "firebase.json"),
  deployLog: resolve(repoRoot, "config/deployments/allowlist-deployments.jsonl"),
};

export const VARIANTS = ["r1", "r1-recovery", "r1-compat", "freeze", "r2"];

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

/**
 * R1-compat: R1 plus exactly the reads the R2 client needs, and nothing else. It is deployed BEFORE
 * the R2 client so the `root.child` lookups run in production early (DESIGN-database-rules-phase4.md,
 * section 3).
 *
 *  - `AuthIndex/{uid}`: a signed-in (non-anonymous) user may read their own entry only.
 *  - `TipperPrivate/{id}`: a signed-in user may read the record only when the link agrees in BOTH
 *    directions (`AuthIndex[auth.uid] == id` and the record's `authuid == auth.uid`), the R2 owner
 *    rule. Allowlisted admins may read every record.
 *
 * There is no `.write` anywhere in it, so a client can write neither node (default deny; only the
 * functions, with Admin credentials, do), and 1.4.x clients behave exactly as under R1. Every other
 * identity node (`AliasIndex`, `LogonIndex`, `Placeholders`, `ServerConfig`, ...) stays closed.
 */
export function addCompatReads(rules, uids) {
  const out = structuredClone(rules);
  out.rules.AuthIndex = {
    $uid: { ".read": `${SIGNED_IN_EXPR} && auth.uid === $uid` },
  };
  out.rules.TipperPrivate = {
    ".read": isAdminExpr(uids),
    $tipperId: {
      ".read": `${SIGNED_IN_EXPR} && root.child('AuthIndex').child(auth.uid).val() === $tipperId && data.child('authuid').val() === auth.uid`,
    },
  };
  return out;
}

/**
 * The freeze ruleset (cutover step A1, DESIGN-database-rules-phase4.md section 8): R1-compat with every
 * identity-bearing write closed to ALL clients, administrators included, so the reconcile reads a state
 * that cannot move under it. Closed: creating and deleting a tipper record (and any whole-node write of
 * `AllTippers`), `name`, `email`, `logon`, `isAnonymous`, and the tipper-level write of `AllTips` (a tip-node
 * merge or delete). `authuid` and `tipperRole` have no leaf write even in R1.
 *
 * Kept, because tippers keep using the app during the freeze: reading, tipping (the game-level tip write),
 * the paid toggle (`compsParticipatedIn`, now a leaf write for administrators, which is all the whole-node
 * write was used for besides identity), photos, login timestamps, and device tokens. Everything outside
 * `AllTippers` and the tipper level of `AllTips` is exactly as in R1-compat.
 */
export function closeIdentityWrites(compatRules, uids) {
  const out = structuredClone(compatRules);

  const tippers = out.rules.AllTippers;
  delete tippers[".write"];
  const tipper = tippers.$tipperId;
  delete tipper[".write"];
  for (const field of ["name", "email", "logon", "isAnonymous"]) delete tipper[field][".write"];
  tipper.compsParticipatedIn[".write"] = isAdminExpr(uids);

  for (const comp of Object.values(out.rules.AllTips)) {
    if (comp && typeof comp === "object") {
      for (const perTipper of Object.values(comp)) {
        if (perTipper && typeof perTipper === "object") delete perTipper[".write"];
      }
    }
  }
  return out;
}

const R2_CALLER = "root.child('AuthIndex').child(auth.uid).val()";
const R2_VALID_CALLER =
  `(${SIGNED_IN_EXPR} && root.child('AuthIndex').child(auth.uid).exists() && ` +
  `root.child('TipperPrivate').child(${R2_CALLER}).child('authuid').val() === auth.uid)`;
const R2_KICKOFF = "root.child('DAUCompsGames').child($comp).child($game).child('DateUtcEpochMs').val()";
const R2_GRACE = "root.child('AppConfig').child('tipGracePeriodSeconds')";
const R2_MACROS = {
  SIGNED_IN: SIGNED_IN_EXPR,
  CALLER: R2_CALLER,
  VALID_CALLER: R2_VALID_CALLER,
  // The caller's tipper, validated both ways: AuthIndex[uid] names a record whose authuid is the uid.
  IS_OWNER: `(${R2_VALID_CALLER} && ${R2_CALLER} === $tipperId)`,
  IS_ADMIN: `(${R2_VALID_CALLER} && root.child('TipperPrivate').child(${R2_CALLER}).child('tipperRole').val() === 'admin')`,
  // Kickoff as a number of milliseconds; a missing or non-numeric one makes every comparison fail closed.
  KICKOFF: R2_KICKOFF,
  VALID_KICKOFF: "root.child('DAUCompsGames').child($comp).child($game).child('DateUtcEpochMs').isNumber()",
  TIP_DEADLINE: `(${R2_KICKOFF} + ((${R2_GRACE}.isNumber() && ${R2_GRACE}.val() >= 0 && ${R2_GRACE}.val() % 1 === 0) ? ${R2_GRACE}.val() : 120) * 1000)`,
  OFFICIAL_SCORE:
    "root.child('DAUCompsGames').child($comp).child($game).child('HomeTeamScore').exists() && " +
    "root.child('DAUCompsGames').child($comp).child($game).child('AwayTeamScore').exists()",
};

/**
 * The R2 (final) rules. They take no allowlist: the R1 allowlist is retired, and an administrator is
 * the validated private role (`TipperPrivate[AuthIndex[uid]].tipperRole === 'admin'` where that record's
 * `authuid` is the uid). A missing index entry, a record naming someone else or a missing record grants
 * nothing; every lookup is guarded with `exists()` so that no outcome depends on a rule error.
 */
export function buildR2Rules(templateText) {
  const asJsonFragment = (text) => JSON.stringify(text).slice(1, -1);
  let text = templateText;
  for (const [name, expression] of Object.entries(R2_MACROS)) {
    text = text.replaceAll(`{{${name}}}`, asJsonFragment(expression));
  }
  if (text.includes("{{")) throw new Error("Unresolved placeholder left in the R2 rules template");
  return JSON.parse(text);
}

/**
 * Substitute the allowlist into the template. Returns a rules object for the variant. The template is
 * the R1 template for every variant except `r2`, which has its own and ignores the allowlist.
 */
export function buildRules(templateText, uids, { variant = "r1" } = {}) {
  if (!VARIANTS.includes(variant)) throw new Error(`Unknown variant: ${variant}`);
  if (variant === "r2") return buildR2Rules(templateText);
  const rules = substitute(templateText, uids);
  if (variant === "r1-recovery") return relaxForRecovery(rules);
  if (variant === "r1-compat") return addCompatReads(rules, uids);
  if (variant === "freeze") return closeIdentityWrites(addCompatReads(rules, uids), uids);
  return rules;
}

export function renderRulesFile(templateText, uids, options = {}) {
  return `${JSON.stringify(buildRules(templateText, uids, options), null, 2)}\n`;
}

/** The template text a variant is generated from. */
export function templateFor(variant) {
  return readFileSync(variant === "r2" ? PATHS.r2Template : PATHS.template, "utf8");
}

export function loadConfig(path = PATHS.config) {
  return JSON.parse(readFileSync(path, "utf8")).adminAuthUids;
}

const outputFor = (variant) =>
  ({
    "r1-recovery": PATHS.recoveryOut,
    "r1-compat": PATHS.compatOut,
    freeze: PATHS.freezeOut,
    r2: PATHS.r2Out,
  })[variant] ?? PATHS.rulesOut;

/** The rules file Firebase deploys, per firebase.json. */
export function deployedRulesPath() {
  const config = JSON.parse(readFileSync(PATHS.firebaseJson, "utf8"));
  const rules = config.database?.rules;
  if (typeof rules !== "string") throw new Error("firebase.json has no database.rules entry");
  return resolve(repoRoot, rules);
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

/** The variant of the most recent rules deployment in the log, or "none". */
export function lastRulesVariant(logPath = PATHS.deployLog) {
  if (!existsSync(logPath)) return "none";
  let last = "none";
  for (const line of readFileSync(logPath, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    const entry = JSON.parse(line);
    if (entry.kind === "rules" && typeof entry.variant === "string") last = entry.variant;
  }
  return last;
}

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

  if (flags.has("--revision")) {
    console.log(revision);
    return;
  }

  if (flags.has("--last-rules-variant")) {
    console.log(lastRulesVariant());
    return;
  }

  if (flags.has("--check-deploy")) {
    const target = deployedRulesPath();
    const expected = renderRulesFile(templateFor(variant), uids, { variant });
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
    writeFileSync(target, renderRulesFile(templateFor(variant), uids, { variant }));
    console.log(`installed ${variant} rules (allowlist revision ${revision}) at ${target}`);
    return;
  }

  if (values["--record"] !== undefined) {
    const kind = values["--record"];
    if (kind !== "rules") throw new Error("--record must be 'rules' (the functions no longer use the allowlist)");
    const rulesText = renderRulesFile(templateFor(variant), uids, { variant });
    const entry = {
      at: new Date().toISOString(),
      kind,
      variant,
      project: JSON.parse(readFileSync(resolve(repoRoot, ".firebaserc"), "utf8")).projects?.default ?? null,
      commit: git("rev-parse", "HEAD") || null,
      branch: git("rev-parse", "--abbrev-ref", "HEAD") || null,
      dirty: git("status", "--porcelain") !== "",
      allowlistRevision: revision,
      adminUidCount: uids.length,
      rulesSha256: sha256(rulesText),
    };
    mkdirSync(dirname(PATHS.deployLog), { recursive: true });
    appendFileSync(PATHS.deployLog, `${JSON.stringify(entry)}\n`);
    console.log(`recorded ${kind} deployment with allowlist revision ${revision} in ${PATHS.deployLog}`);
    return;
  }

  const outputs = [
    ...VARIANTS.map((v) => [outputFor(v), renderRulesFile(templateFor(v), uids, { variant: v })]),
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
