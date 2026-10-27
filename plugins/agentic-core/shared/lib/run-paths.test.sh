#!/usr/bin/env bash
# Tests for shared/run-paths.txt, the core's own run paths (D137). Run with:
#   bash plugins/agentic-core/shared/lib/run-paths.test.sh
#
# Checks the file's shape, and that every `.ai/` path the core's own code
# names is listed in it, so a new run file cannot appear without its line.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIST_FILE="$CORE_ROOT/shared/run-paths.txt"

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== run-paths.txt tests ==="

if [[ "$(basename "$(cd "$SCRIPT_DIR/.." && pwd -P)")" != shared ]]; then
  echo "  skipped: a pack's copy of the core; the core's own copy runs these checks"
  echo "=== $PASS passed, $FAIL failed ==="
  exit 0
fi

echo "[shape] the file exists, and every line is a comment, blank, or '<ignore|commit> <path>'"
if [[ ! -f "$LIST_FILE" ]]; then
  bad "shared/run-paths.txt exists"
  echo "=== $PASS passed, $FAIL failed ==="
  exit 1
fi
ok "shared/run-paths.txt exists"

IGNORE=()
COMMIT=()
seen=" "
shape_ok=1
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ "$line" =~ ^(ignore|commit)\ ([A-Za-z0-9._/-]+)$ ]]; then
    kind="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    case "/$path/" in */../*) bad "no '..' segment: $path"; shape_ok=0 ;; esac
    [[ "$path" == /* ]] && { bad "relative, not absolute: $path"; shape_ok=0; }
    [[ "$seen" == *" $path "* ]] && { bad "listed once: $path"; shape_ok=0; }
    seen+="$path "
    if [[ "$kind" == ignore ]]; then IGNORE+=("$path"); else COMMIT+=("$path"); fi
  else
    bad "a well-formed line: '$line'"
    shape_ok=0
  fi
done < "$LIST_FILE"
(( shape_ok )) && ok "every line well-formed, relative, listed once"
(( ${#IGNORE[@]} > 0 )) && ok "lists at least one ignored path" || bad "lists at least one ignored path"
(( ${#COMMIT[@]} > 0 )) && ok "lists at least one committed path" || bad "lists at least one committed path"

listed() {
  local p="$1" entry
  for entry in "${IGNORE[@]}" "${COMMIT[@]}"; do
    [[ "$p" == "$entry" || "$p/" == "$entry" ]] && return 0
    [[ "$entry" == */ && "$p" == "$entry"* ]] && return 0
  done
  return 1
}

echo "[drift] every .ai/ path the core's own code names is listed"
drift_ok=1
while IFS= read -r p; do
  if listed "$p"; then :; else bad "listed: $p"; drift_ok=0; fi
done < <(
  find "$CORE_ROOT" \( -name node_modules -o -name fixtures \) -prune -o -type f \
    \( -name '*.sh' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' \) \
    ! -name '*.test.*' -print0 \
  | xargs -0 grep -hoE '\.ai/[A-Za-z0-9_.-]+/?' \
  | sort -u
)
(( drift_ok )) && ok "no unlisted .ai/ path in the core's code"

echo "[split] the run's working files are ignored, the project's own files committed"
for p in .ai/run-context/ .ai/logs/ .ai/run-state.json; do
  [[ " ${IGNORE[*]} " == *" $p "* ]] && ok "ignore $p" || bad "ignore $p"
done
for p in .ai/project-config.yaml .ai/specs/; do
  [[ " ${COMMIT[*]} " == *" $p "* ]] && ok "commit $p" || bad "commit $p"
done

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
