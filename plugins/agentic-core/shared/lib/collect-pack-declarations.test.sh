#!/usr/bin/env bash
# Tests for collect-pack-declarations.sh. Run with:
#   bash plugins/agentic-core/shared/lib/collect-pack-declarations.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-pack-declarations.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"
RUN_PATHS="$SCRIPT_DIR/../run-paths.txt"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    got:      $actual"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected to contain: $needle"; echo "    got: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    must not contain: $needle"; echo "    got: $haystack"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/collect-pack-declarations-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT/.ai/run-context/plugin-roots"

# Copies a valid manifest fixture to a plugin root, appends the given
# declarations, and registers it under <name>.
install_pack() {
  local name="$1" fixture="$2" tail="$3" root="$WORK/plugins/$1"
  mkdir -p "$WORK/plugins"
  cp -R "$FIXDIR/$fixture" "$root"
  mkdir -p "$root/.claude-plugin"
  [[ -n "$tail" ]] && printf '%s\n' "$tail" >> "$root/pack.yaml"
  (cd "$root" && pwd -P) > "$PROJECT/.ai/run-context/plugin-roots/$name"
}

install_pack example-platform platform-valid 'hosts: ["*.example-preview.test"]
ignore_paths: ["example-drafts/"]'
install_pack example-tracker provider-valid 'env:
  - name: EXAMPLE_SITE
    source: "the host name of your example tracker site"
  - name: EXAMPLE_API_TOKEN
    source: "example account settings, API tokens"
hosts: ["*.example-tracker.test"]
ignore_paths: [".ai/example-tracker/"]'
install_pack example-scm provider-valid 'env:
  - name: EXAMPLE_SCM_TOKEN
    source: "an access token for the example code host"
    login_alternative: "example-cli auth login"
hosts: ["api.example-scm.test", "*.example-tracker.test"]
ignore_paths: [".ai/example-scm/"]'
install_pack example-browser provider-valid ''
install_pack example-unchosen provider-valid 'env:
  - name: UNCHOSEN_TOKEN
    source: "a token for a pack this project did not choose"
hosts: ["api.unchosen.test"]'

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

echo "[collect] the configured packs' declarations, then the core's own paths"
OUT=$(bash "$COLLECT" "$CONFIG" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
TAB=$'\t'
assert_contains "a variable: role, name and source" "env${TAB}example-tracker${TAB}EXAMPLE_SITE${TAB}the host name of your example tracker site" "$OUT"
assert_contains "a second variable of the same pack" "env${TAB}example-tracker${TAB}EXAMPLE_API_TOKEN${TAB}example account settings, API tokens" "$OUT"
assert_contains "a variable a login replaces is a login line" "login${TAB}example-scm${TAB}EXAMPLE_SCM_TOKEN${TAB}example-cli auth login" "$OUT"
assert_not_contains "a variable a login replaces is never an env line" "env${TAB}example-scm${TAB}EXAMPLE_SCM_TOKEN" "$OUT"
assert_contains "a platform host" "host${TAB}example-platform${TAB}*.example-preview.test" "$OUT"
assert_contains "a provider host" "host${TAB}example-scm${TAB}api.example-scm.test" "$OUT"
assert_contains "a platform ignore path" "ignore${TAB}example-platform${TAB}example-drafts/" "$OUT"
assert_contains "a provider ignore path" "ignore${TAB}example-tracker${TAB}.ai/example-tracker/" "$OUT"
assert_not_contains "a pack that was not chosen adds nothing" "unchosen" "$OUT"
assert_not_contains "design: none is not a pack" "${TAB}none${TAB}" "$OUT"

N_IGNORE=$(grep -c '^ignore ' "$RUN_PATHS")
N_COMMIT=$(grep -c '^commit ' "$RUN_PATHS")
assert_eq "every run-paths ignore line, as core" "$N_IGNORE" "$(grep -c "^ignore${TAB}core${TAB}" <<< "$OUT")"
assert_eq "every run-paths commit line, as core" "$N_COMMIT" "$(grep -c "^commit${TAB}core${TAB}" <<< "$OUT")"
assert_contains "the credentials file is a core ignore path (D139)" "ignore${TAB}core${TAB}.claude/settings.local.json" "$OUT"
assert_eq "a host two packs declare appears once per pack, not merged here" 2 "$(grep -c "^host${TAB}.*${TAB}\*\.example-tracker\.test$" <<< "$OUT")"

echo "[unresolved] a configured pack the registry does not know is reported, the rest collected"
sed -i.bak 's/^  browser: example-browser$/  browser: example-missing/' "$CONFIG"
OUT=$(bash "$COLLECT" "$CONFIG" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "names the pack" "unresolved${TAB}example-missing${TAB}" "$OUT"
assert_contains "still collects the others" "env${TAB}example-tracker${TAB}EXAMPLE_SITE" "$OUT"
mv "$CONFIG.bak" "$CONFIG"

echo "[refused] a configured pack whose manifest is invalid stops the whole collection"
printf 'env:\n  - name: lower_case\n    source: "x"\n' >> "$WORK/plugins/example-browser/pack.yaml"
OUT=$(bash "$COLLECT" "$CONFIG" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "names the pack" "refused: example-browser" "$OUT"
assert_not_contains "prints no declaration" "env${TAB}" "$OUT"

echo "[refused] no config, or a config with no packs block"
OUT=$(bash "$COLLECT" "$WORK/absent.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "absent config: exit 1" 1 "$ST"
printf 'version: 1\n' > "$WORK/no-packs.yaml"
OUT=$(bash "$COLLECT" "$WORK/no-packs.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "no packs block: exit 1" 1 "$ST"
assert_contains "says why" "no packs: block" "$OUT"

echo "[usage]"
bash "$COLLECT" >/dev/null 2>&1; ST=$?
assert_eq "no argument: exit 2" 2 "$ST"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
