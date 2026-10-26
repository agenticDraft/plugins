#!/usr/bin/env bash
# Run: bash scripts/check-getting-started.sh [--root <repo>] [--names-only]
#
# check-getting-started.sh [--root <repo>] [--names-only]
#
# Checks plugins/getting-started.md against what the shipped packs declare:
#   1. the generated block between the guide's markers equals a fresh render of every
#      plugins/agentic-*/pack.yaml (render-guide-declarations.sh), so no value a pack owns is
#      typed into the guide by hand;
#   2. every variable (`env`) and host (`hosts`) a pack declares appears somewhere in the guide.
#      This reads the manifests by its own, plainer route than the renderer, so a declaration the
#      renderer failed to pick up is still caught.
#
#   --root        the repository to check (default: this one)
#   --names-only  skip check 1
#
# Reads and never writes. Deterministic, no model involved.
#
# Output (stdout): `valid: getting-started (<n> packs, <n> variables, <n> hosts)`, or one
#   `stale:` line and/or one `missing: variable <NAME>` / `missing: host <host>` line per problem.
# Exit codes: 0 — valid; 1 — stale or missing; 2 — usage error, no guide, or a guide without
#   both markers.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$SCRIPT_DIR/render-guide-declarations.sh"
BEGIN='<!-- guide-declarations:begin'
END='<!-- guide-declarations:end -->'

usage() {
  echo "usage: check-getting-started.sh [--root <repo>] [--names-only]" >&2
  exit 2
}

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMES_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)       [[ $# -ge 2 ]] || usage; ROOT="$2"; shift 2 ;;
    --names-only) NAMES_ONLY=1; shift ;;
    *) usage ;;
  esac
done

GUIDE="$ROOT/plugins/getting-started.md"
[[ -f "$GUIDE" ]] || { echo "refused: $GUIDE does not exist" >&2; exit 2; }
grep -q "^$BEGIN" "$GUIDE" && grep -qF "$END" "$GUIDE" \
  || { echo "refused: $GUIDE does not hold both guide-declarations markers" >&2; exit 2; }

PROBLEMS=0

if [[ "$NAMES_ONLY" -eq 0 ]]; then
  if ! FRESH=$(bash "$RENDER" --root "$ROOT"); then
    exit 1
  fi
  CURRENT=$(awk -v begin="$BEGIN" -v end="$END" '
    index($0, begin) == 1 { inside = 1 }
    inside { print }
    inside && index($0, end) == 1 { exit }
  ' "$GUIDE")
  if [[ "$FRESH" != "$CURRENT" ]]; then
    echo "stale: the generated block differs from the packs' declarations — run: bash scripts/render-guide-declarations.sh --write plugins/getting-started.md"
    PROBLEMS=1
  fi
fi

N_PACKS=0 VARS="" HOSTS=""
for manifest in "$ROOT"/plugins/agentic-*/pack.yaml; do
  [[ -f "$manifest" ]] || continue
  N_PACKS=$((N_PACKS + 1))
  VARS+=$(awk '
    /^[A-Za-z_]+:/ { inside = ($0 == "env:") ; next }
    inside && /^  - name: / { sub(/^  - name: */, ""); print }
  ' "$manifest")$'\n'
  hosts=$(sed -n 's/^hosts: \[\(.*\)\]$/\1/p' "$manifest")
  HOSTS+=$(grep -oE '"[^"]*"' <<< "$hosts" | sed 's/^"//; s/"$//')$'\n'
done

N_VARS=0 N_HOSTS=0
while IFS= read -r v; do
  [[ -n "$v" ]] || continue
  N_VARS=$((N_VARS + 1))
  grep -qF -- "$v" "$GUIDE" || { echo "missing: variable $v"; PROBLEMS=1; }
done < <(printf '%s' "$VARS" | sort -u)
while IFS= read -r h; do
  [[ -n "$h" ]] || continue
  N_HOSTS=$((N_HOSTS + 1))
  grep -qF -- "$h" "$GUIDE" || { echo "missing: host $h"; PROBLEMS=1; }
done < <(printf '%s' "$HOSTS" | sort -u)

[[ "$PROBLEMS" -eq 0 ]] || exit 1
echo "valid: getting-started ($N_PACKS packs, $N_VARS variables, $N_HOSTS hosts)"
exit 0
