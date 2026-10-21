#!/usr/bin/env bash
# Applies the reviewed identity backfill patch (DESIGN-database-rules-phase4.md, M4a). Owner-run.
# Check first, act second, verify last, in the style of the other owner-run scripts.
#
#   scripts/apply-identity-backfill.sh --patch <reviewed-patch.json> \
#       [--decisions <decisions.json>] [--allowlist <file>]               # check only
#   scripts/apply-identity-backfill.sh ... --apply                         # check, apply, verify
#
# What it guards:
#  * the patch you reviewed was planned from earlier exports. NOW it reads the live database AND the live
#    Firebase Auth accounts again (a fresh `firebase auth:export`, reduced at once to uid, email and verified
#    flag; the full export, which holds password hashes, exists only in a private temporary folder and is
#    deleted immediately), plans again, and writes nothing unless the result is byte-identical to the reviewed
#    patch. An account created or deleted, or a record changed, since your review therefore stops it;
#  * the five identity nodes and the tipper list are read before planning and again just before the write, and
#    any difference stops it. That narrows the window in which something could change under it to the time of
#    one read. It cannot be zero: the Firebase CLI offers no conditional write. What remains is small, because
#    no client or function can write the identity nodes today (the rules do not name them), so the only place a
#    concurrent writer could be overwritten is the `authuid` of a link you approved;
#  * the planner refuses to produce a patch while a blocking finding remains, so none is ever applied;
#  * the project is named explicitly, and --disable-triggers stops the badge and scoring functions reacting;
#  * afterwards the live database is read again and the planner's --check must find nothing left to do. That
#    check says the backfill is in place. It does NOT say the identities are ready for R2: its output lists
#    any "cutover" findings that remain (duplicates and ambiguities), and the cutover check is --strict.
# The patch holds personal data: keep it under /test/data/ (git-ignored).
set -euo pipefail

PROJECT="dau-footy-tipping-f8a42"
FIREBASE="${FIREBASE_BIN:-firebase}"
DART="${DART_BIN:-dart}"
NODE="${NODE_BIN:-node}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
IDENTITY_ROOTS=(AllTippers TipperPrivate AuthIndex AliasIndex LogonIndex Placeholders)

PATCH=""
DECISIONS=""
ALLOWLIST=""
APPLY=false

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}" >&2
  exit 64
}

absolute() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch) PATCH="${2:-}"; shift 2 ;;
    --decisions) DECISIONS="${2:-}"; shift 2 ;;
    --allowlist) ALLOWLIST="${2:-}"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    *) usage ;;
  esac
done
[[ -n "${PATCH}" ]] || usage
[[ -f "${PATCH}" ]] || { echo "STOP: ${PATCH} does not exist." >&2; exit 1; }
PATCH="$(absolute "${PATCH}")"
[[ -z "${DECISIONS}" ]] || DECISIONS="$(absolute "${DECISIONS}")"
[[ -z "${ALLOWLIST}" ]] || ALLOWLIST="$(absolute "${ALLOWLIST}")"

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

planner() {
  local database="$1"
  shift
  local args=(--file "${database}" --auth-accounts "${WORK}/auth.json")
  [[ -z "${DECISIONS}" ]] || args+=(--decisions "${DECISIONS}")
  [[ -z "${ALLOWLIST}" ]] || args+=(--allowlist "${ALLOWLIST}")
  (cd "${REPO}/functions_dart" && "${DART}" run bin/identity_backfill.dart "${args[@]}" "$@")
}

snapshot_roots() {
  local dir="$1" root
  mkdir -p "${dir}"
  for root in "${IDENTITY_ROOTS[@]}"; do
    "${FIREBASE}" database:get "/${root}" --project "${PROJECT}" -o "${dir}/${root}.json" >/dev/null
  done
}

same_file() {
  if [[ ! -e "$1" && ! -e "$2" ]]; then return 0; fi
  cmp -s "$1" "$2"
}

echo "Project: ${PROJECT}"
echo "Reading the live Firebase Auth accounts (the full export is deleted at once)..."
"${FIREBASE}" auth:export "${WORK}/auth-full.json" --project "${PROJECT}" >/dev/null
"${NODE}" "${HERE}/slim_auth_export.mjs" "${WORK}/auth-full.json" "${WORK}/auth.json" --delete-input >/dev/null

echo "Reading the live database..."
snapshot_roots "${WORK}/snapshot-a"
"${FIREBASE}" database:get / --project "${PROJECT}" -o "${WORK}/live.json" >/dev/null

echo "Planning again from the live data..."
if ! planner "${WORK}/live.json" --patch-out "${WORK}/fresh-patch.json" >"${WORK}/plan.txt"; then
  cat "${WORK}/plan.txt" >&2
  echo "STOP: the planner reported a problem. Nothing was written." >&2
  exit 1
fi
if [[ ! -f "${WORK}/fresh-patch.json" ]] || ! cmp -s "${WORK}/fresh-patch.json" "${PATCH}"; then
  echo "STOP: the live data no longer produces the patch you reviewed. Nothing was written." >&2
  echo "Plan it again, review the new patch, and re-run." >&2
  exit 1
fi
echo "The live database and Auth accounts still produce exactly the reviewed patch."

if [[ "${APPLY}" != true ]]; then
  echo "Check only. Run again with --apply to write it."
  exit 0
fi

echo "Re-reading the identity nodes just before the write..."
snapshot_roots "${WORK}/snapshot-b"
for root in "${IDENTITY_ROOTS[@]}"; do
  if ! same_file "${WORK}/snapshot-a/${root}.json" "${WORK}/snapshot-b/${root}.json"; then
    echo "STOP: /${root} changed while the patch was being checked. Nothing was written. Re-run." >&2
    exit 1
  fi
done

"${FIREBASE}" database:update / "${PATCH}" --project "${PROJECT}" --force --disable-triggers

echo "Verifying..."
"${FIREBASE}" database:get / --project "${PROJECT}" -o "${WORK}/after.json" >/dev/null
if ! planner "${WORK}/after.json" --check >"${WORK}/verify.txt"; then
  cat "${WORK}/verify.txt" >&2
  echo "PROBLEM: the database does not match the plan after the write. Do not continue; tell Claude." >&2
  exit 1
fi
cat "${WORK}/verify.txt"
echo "Done: the backfill is in place. The cutover check is separate (planner --strict); see the lines above."
