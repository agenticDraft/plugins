#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-credentials.sh <label>=<pack.yaml> ...
#
# check-credentials.sh <label>=<pack.yaml> [...]
#
# Runs each pack's declared `credential_checks:` (shared/pack-manifest.md):
# per entry a `probe` given as argv, judged by its exit status alone. The
# probe's output is discarded, so nothing it prints — a token, an account —
# can reach this report; only the check's name and the pack's own `proves`
# or `remedy` text are printed. A pass is reported as what `proves` says and
# nothing more. A pack declaring no check is reported as unproven, never as
# passing. Names no pack. Deterministic given the probes; no model involved.
# Writes nothing. A probe argument prefixed `<pack>/` resolves against the
# directory holding the manifest. Probes run in the caller's directory, which
# is the project the checks are about.
#
# Two callers: the `health` diagnostic, and the route driver after pre-flight
# and before intake, which ends the run `blocked` on exit 1 with the remedy.
#
# Output (stdout), one line per check:
#   ok: <label> <check> — proves only: <proves>
#   failed: <label> <check> — <remedy>
#   none: <label> declares no credential check — nothing proves its credential works
#
# Exit codes:
#   0 — every declared check passed, or none is declared
#   1 — at least one check failed
#   2 — usage error, a manifest that does not exist, or a malformed block

set -uo pipefail

usage() {
  echo "usage: check-credentials.sh <label>=<pack.yaml> [...]" >&2
  exit 2
}

(( $# > 0 )) || usage
for arg in "$@"; do [[ "$arg" == *=* ]] || usage; done

malformed() {
  echo "invalid: malformed 'credential_checks:' block in $1 — $2; run validate-pack-manifest.sh on it" >&2
  exit 2
}

STATUS=0
for arg in "$@"; do
  label="${arg%%=*}"
  manifest="${arg#*=}"
  [[ -f "$manifest" ]] || { echo "refused: $manifest does not exist" >&2; exit 2; }
  pack_root="$(cd "$(dirname "$manifest")" && pwd)"

  LINES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    LINES+=("$line")
  done < "$manifest"
  n=${#LINES[@]}

  start=-1
  for ((i = 0; i < n; i++)); do
    [[ "${LINES[i]}" == "credential_checks:" ]] && { start=$i; break; }
  done
  if (( start < 0 )); then
    echo "none: $label declares no credential check — nothing proves its credential works"
    continue
  fi

  checked=0
  i=$((start + 1))
  while (( i < n )); do
    [[ "${LINES[i]}" =~ ^\ \ -\ check:\ (.+)$ ]] || break
    check="${BASH_REMATCH[1]}"; i=$((i + 1))
    [[ "${LINES[i]:-}" =~ ^\ \ \ \ probe:\ \[(.*)\]$ ]] || malformed "$manifest" "'$check' has no 'probe:' list"
    probe_raw="${BASH_REMATCH[1]}"; i=$((i + 1))
    [[ "${LINES[i]:-}" =~ ^\ \ \ \ proves:\ \"(.*)\"$ ]] || malformed "$manifest" "'$check' has no 'proves:'"
    proves="${BASH_REMATCH[1]}"; i=$((i + 1))
    [[ "${LINES[i]:-}" =~ ^\ \ \ \ remedy:\ \"(.*)\"$ ]] || malformed "$manifest" "'$check' has no 'remedy:'"
    remedy="${BASH_REMATCH[1]}"; i=$((i + 1))

    ARGV=()
    IFS=',' read -ra RAW <<< "$probe_raw"
    for a in "${RAW[@]:-}"; do
      a="${a#"${a%%[![:space:]]*}"}"
      a="${a%"${a##*[![:space:]]}"}"
      [[ -z "$a" ]] && continue
      [[ "$a" == "<pack>/"* ]] && a="$pack_root/${a#<pack>/}"
      ARGV+=("$a")
    done
    (( ${#ARGV[@]} > 0 )) || malformed "$manifest" "'$check' declares an empty probe"

    checked=$((checked + 1))
    if "${ARGV[@]}" >/dev/null 2>&1 </dev/null; then
      echo "ok: $label $check — proves only: $proves"
    else
      echo "failed: $label $check — $remedy"
      STATUS=1
    fi
  done
  (( checked > 0 )) || malformed "$manifest" "it declares no entries"
done

exit "$STATUS"
