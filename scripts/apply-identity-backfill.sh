#!/usr/bin/env bash
# Applies the reviewed identity backfill patch (DESIGN-database-rules-phase4.md, M4a). Owner-run.
# Check first, act second, verify last, in the style of the other owner-run scripts.
#
#   scripts/apply-identity-backfill.sh --patch <reviewed-patch.json> --auth-export <auth.json> \
#       [--approved-links <links.json>] [--allowlist <file>]              # check only
#   scripts/apply-identity-backfill.sh ... --apply                         # check, apply, verify
#
# Safety:
#  * the patch you reviewed was planned from an earlier export. The live database is read again NOW and
#    planned again; unless that gives a patch that is byte-identical to the reviewed one, nothing is written
#    (a record, a claim or an Auth account changed in between, so the plan is not the one you reviewed);
#  * the planner refuses to produce a patch while a blocking finding remains, so none is ever applied;
#  * the project is named explicitly;
#  * --disable-triggers stops the app-badge and scoring functions reacting to the writes;
#  * afterwards the live database is read again and the planner's --check must find nothing left to do.
# The patch and the Auth export hold personal data: keep them under /test/data/ (git-ignored) and delete
# the Auth export (it holds password hashes) when you are done.
set -euo pipefail

PROJECT="dau-footy-tipping-f8a42"
FIREBASE="${FIREBASE_BIN:-firebase}"
DART="${DART_BIN:-dart}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"

PATCH=""
AUTH_EXPORT=""
APPROVED_LINKS=""
ALLOWLIST=""
APPLY=false

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

absolute() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch) PATCH="${2:-}"; shift 2 ;;
    --auth-export) AUTH_EXPORT="${2:-}"; shift 2 ;;
    --approved-links) APPROVED_LINKS="${2:-}"; shift 2 ;;
    --allowlist) ALLOWLIST="${2:-}"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    *) usage ;;
  esac
done
[[ -n "${PATCH}" && -n "${AUTH_EXPORT}" ]] || usage
[[ -f "${PATCH}" ]] || { echo "STOP: ${PATCH} does not exist." >&2; exit 1; }
[[ -f "${AUTH_EXPORT}" ]] || { echo "STOP: ${AUTH_EXPORT} does not exist." >&2; exit 1; }
PATCH="$(absolute "${PATCH}")"
AUTH_EXPORT="$(absolute "${AUTH_EXPORT}")"
[[ -z "${APPROVED_LINKS}" ]] || APPROVED_LINKS="$(absolute "${APPROVED_LINKS}")"
[[ -z "${ALLOWLIST}" ]] || ALLOWLIST="$(absolute "${ALLOWLIST}")"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

planner() {
  local database="$1"
  shift
  local args=(--file "${database}" --auth-export "${AUTH_EXPORT}")
  [[ -z "${APPROVED_LINKS}" ]] || args+=(--approved-links "${APPROVED_LINKS}")
  [[ -z "${ALLOWLIST}" ]] || args+=(--allowlist "${ALLOWLIST}")
  (cd "${REPO}/functions_dart" && "${DART}" run bin/identity_backfill.dart "${args[@]}" "$@")
}

echo "Project: ${PROJECT}"
echo "Reading the live database..."
"${FIREBASE}" database:get / --project "${PROJECT}" -o "${WORK}/live.json" >/dev/null

echo "Planning again from the live data..."
if ! planner "${WORK}/live.json" --patch-out "${WORK}/fresh-patch.json" >"${WORK}/plan.txt"; then
  cat "${WORK}/plan.txt" >&2
  echo "STOP: the planner reported a problem. Nothing was written." >&2
  exit 1
fi
if [[ ! -f "${WORK}/fresh-patch.json" ]] || ! cmp -s "${WORK}/fresh-patch.json" "${PATCH}"; then
  echo "STOP: the live database no longer produces the patch you reviewed. Nothing was written." >&2
  echo "Plan it again, review the new patch, and re-run." >&2
  exit 1
fi
echo "The live database still produces exactly the reviewed patch."

if [[ "${APPLY}" != true ]]; then
  echo "Check only. Run again with --apply to write it."
  exit 0
fi

"${FIREBASE}" database:update / "${PATCH}" --project "${PROJECT}" --force --disable-triggers

echo "Verifying..."
"${FIREBASE}" database:get / --project "${PROJECT}" -o "${WORK}/after.json" >/dev/null
if ! planner "${WORK}/after.json" --check >"${WORK}/verify.txt"; then
  cat "${WORK}/verify.txt" >&2
  echo "PROBLEM: the database does not match the plan after the write. Do not continue; tell Claude." >&2
  exit 1
fi
echo "Done: every entry is in place and the check finds nothing left to do."
