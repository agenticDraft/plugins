#!/usr/bin/env bash
# Tests for write-working-paths.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-working-paths.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$SCRIPT_DIR/write-working-paths.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"
RUN_PATHS="$SCRIPT_DIR/../run-paths.txt"

PASS=0
FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/write-working-paths-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT/.ai/run-context/plugin-roots"

install_pack() {
  local name="$1" fixture="$2" tail="$3" root="$WORK/plugins/$1"
  mkdir -p "$WORK/plugins"
  cp -R "$FIXDIR/$fixture" "$root"
  mkdir -p "$root/.claude-plugin"
  [[ -n "$tail" ]] && printf '%s\n' "$tail" >> "$root/pack.yaml"
  (cd "$root" && pwd -P) > "$PROJECT/.ai/run-context/plugin-roots/$name"
}

install_pack example-platform platform-valid 'ignore_paths: ["example-drafts/"]'
install_pack example-tracker provider-valid 'ignore_paths: [".ai/example-tracker/"]'
install_pack example-scm provider-valid 'ignore_paths: [".ai/example-scm/", ".ai/example-tracker/"]'
install_pack example-browser provider-valid ''

CONFIG="$PROJECT/.ai/project-config.yaml"
cat > "$CONFIG" <<'EOF'
version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser

commands:
  lint: ""
EOF

CORE_IGNORE="$(awk '$1 == "ignore" { print $2 }' "$RUN_PATHS")"
EXPECTED="$(printf '%s\n' 'example-drafts/' '.ai/example-tracker/' '.ai/example-scm/' $CORE_IGNORE | sort -u)"

echo "=== write-working-paths.sh tests ==="

echo "[write] every configured pack's ignore_paths and the core's ignore lines, once each, sorted"
OUT_FILE="$PROJECT/.ai/run-context/working-paths.txt"
OUT="$(bash "$WRITE" "$CONFIG" "$OUT_FILE" --project-dir "$PROJECT" 2>&1)"; ST=$?
N="$(printf '%s\n' "$EXPECTED" | grep -c .)"
check "exit 0" 0 "$ST"
check "one line naming the file and the count" "written: $OUT_FILE ($N paths)" "$OUT"
check "the file holds exactly the expected paths" "$EXPECTED" "$(cat "$OUT_FILE")"

echo "[rewrite] a second call replaces the file, never appends"
bash "$WRITE" "$CONFIG" "$OUT_FILE" --project-dir "$PROJECT" >/dev/null 2>&1
check "same content after a second call" "$EXPECTED" "$(cat "$OUT_FILE")"

echo "[refused] a config with no packs: block writes nothing"
printf 'version: 1\n' > "$WORK/no-packs.yaml"
rm -f "$WORK/none.txt"
OUT="$(bash "$WRITE" "$WORK/no-packs.yaml" "$WORK/none.txt" --project-dir "$PROJECT" 2>&1)"; ST=$?
check "exit 1" 1 "$ST"
check "the collector's reason, passed through" "refused: $WORK/no-packs.yaml has no packs: block" "$OUT"
check "no file written" "absent" "$([[ -e "$WORK/none.txt" ]] && echo present || echo absent)"

echo "[usage] one argument"
bash "$WRITE" "$CONFIG" >/dev/null 2>&1; ST=$?
check "exit 2" 2 "$ST"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
