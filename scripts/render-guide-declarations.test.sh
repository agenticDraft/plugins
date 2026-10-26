#!/usr/bin/env bash
# Tests for render-guide-declarations.sh. Run with:
#   bash scripts/render-guide-declarations.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$SCRIPT_DIR/render-guide-declarations.sh"
FIX="$REPO/plugins/agentic-core/shared/fixtures"
VALIDATE="$REPO/plugins/agentic-core/shared/lib/validate-pack-manifest.sh"

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
WORK="$(mktemp -d "$TMPDIR/render-guide-declarations-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# A repository root holding five packs copied from the core's valid manifest fixtures, each
# followed by the declarations under test.
ROOT="$WORK/repo"
mkdir -p "$ROOT/plugins"

install_pack() {
  local name="$1" fixture="$2" tail="$3" root="$ROOT/plugins/$1"
  cp -R "$FIX/$fixture" "$root"
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  : > "$root/scripts/probe.sh"
  printf '%s\n' "$tail" >> "$root/pack.yaml"
}

# The core itself: only its run-paths file is read.
mkdir -p "$ROOT/plugins/agentic-core/shared"
cp "$REPO/plugins/agentic-core/shared/run-paths.txt" "$ROOT/plugins/agentic-core/shared/run-paths.txt"

install_pack agentic-eds pack-manifest/platform-valid 'requires:
  - tool: example-cli
    probe: [bash, <pack>/scripts/probe.sh]
    install: [example-pm, add, --dev, example-cli]
    remedy: "add example-cli to the dev dependencies"
hosts: ["*.example-preview.test"]
ignore_paths: ["example-drafts/"]
credential_checks:
  - check: preview-host
    probe: [bash, <pack>/scripts/probe.sh]
    proves: "the preview host serves the code"
    remedy: "install the example sync app on the owner"'
install_pack agentic-jira pack-manifest/provider-valid 'env:
  - name: EXAMPLE_SITE
    source: "the host of your <site> tracker"
  - name: EXAMPLE_TOKEN
    source: "a token for that account"
hosts: ["*.example-tracker.test"]
ignore_paths: [".ai/example-tracker/"]'
install_pack agentic-github pre-flight/providers/scm-valid 'env:
  - name: EXAMPLE_SCM_TOKEN
    source: "a code-host token with write access"
    login_alternative: "example-scm login"
hosts: ["api.example-scm.test"]'
install_pack agentic-figma pre-flight/providers/design-valid 'session_tools:
  - tool: mcp__example__one
    remedy: "enable the example plugin, then sign in"
  - tool: mcp__example__two
    remedy: "enable the example plugin, then sign in"'
install_pack agentic-playwright pre-flight/providers/browser-valid 'requires:
  - tool: example-browser
    probe: [bash, <pack>/scripts/probe.sh]
    remedy: "install the example browser"'

for p in "$ROOT"/plugins/agentic-*/pack.yaml; do
  [[ "$p" == *agentic-core* ]] && continue
  v=$(bash "$VALIDATE" "$p" 2>&1) || { echo "fixture invalid: $p: $v" >&2; exit 1; }
done

echo "[render] one section per pack, platform first, then the roles in order, then the core's paths"
OUT=$(bash "$RENDER" --root "$ROOT" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "begins with the marker" "<!-- guide-declarations:begin" "$OUT"
assert_contains "ends with the marker" "<!-- guide-declarations:end -->" "$OUT"
ORDER=$(grep -E '^#### ' <<< "$OUT" | tr '\n' '|')
assert_eq "section order" "#### agentic-eds (platform)|#### agentic-jira (tracker)|#### agentic-github (scm)|#### agentic-figma (design)|#### agentic-playwright (browser)|#### Files in your repository|" "$ORDER"

echo "[render] variables, a login alternative, hosts"
assert_contains "a variable with its source" '`EXAMPLE_SITE` — the host of your \<site\> tracker' "$OUT"
assert_contains "angle brackets in a source are escaped" '\<site\>' "$OUT"
assert_contains "a second variable" '`EXAMPLE_TOKEN` — a token for that account' "$OUT"
assert_contains "a variable a login replaces names the login" '`EXAMPLE_SCM_TOKEN` — a code-host token with write access. A login replaces it: `example-scm login`' "$OUT"
assert_contains "a host" '`*.example-tracker.test`' "$OUT"
assert_contains "the platform host" '`*.example-preview.test`' "$OUT"
assert_contains "the scm host" '`api.example-scm.test`' "$OUT"

echo "[render] local tools, checks before a run, session tools"
assert_contains "a tool with a declared install" '`example-cli` — `setup` can install it with `example-pm add --dev example-cli`. If you do it yourself: add example-cli to the dev dependencies' "$OUT"
assert_contains "a tool with no install" '`example-browser` — install the example browser' "$OUT"
assert_contains "a credential check" '`preview-host` — install the example sync app on the owner' "$OUT"
assert_contains "session tools of one remedy are one entry" '`mcp__example__one`, `mcp__example__two` — enable the example plugin, then sign in' "$OUT"
assert_not_contains "a probe argv is never printed" "probe.sh" "$OUT"

echo "[render] working files and committed files come from the declarations"
assert_contains "a pack ignore path" '`.ai/example-tracker/`' "$OUT"
assert_contains "the platform ignore path" '`example-drafts/`' "$OUT"
while read -r kind path; do
  case "$kind" in
    ignore|commit) assert_contains "run-paths $kind line $path" "\`$path\`" "$OUT" ;;
  esac
done < "$ROOT/plugins/agentic-core/shared/run-paths.txt"

echo "[render] deterministic"
OUT2=$(bash "$RENDER" --root "$ROOT" 2>&1)
assert_eq "two renders are identical" "$OUT" "$OUT2"

echo "[render] a pack outside plugins/agentic-* adds nothing"
cp -R "$FIX/pack-manifest/provider-valid" "$ROOT/plugins/other-pack"
printf 'env:\n  - name: OTHER_TOKEN\n    source: "x"\n' >> "$ROOT/plugins/other-pack/pack.yaml"
OUT=$(bash "$RENDER" --root "$ROOT" 2>&1)
assert_not_contains "its variable is absent" "OTHER_TOKEN" "$OUT"
rm -rf "$ROOT/plugins/other-pack"

echo "[write] replaces only the block between the markers"
GUIDE="$WORK/guide.md"
printf '# Guide\n\nbefore\n\n<!-- guide-declarations:begin old -->\nstale text\n<!-- guide-declarations:end -->\n\nafter\n' > "$GUIDE"
OUT=$(bash "$RENDER" --root "$ROOT" --write "$GUIDE" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
BODY=$(cat "$GUIDE")
assert_contains "the text before is kept" $'# Guide\n\nbefore\n' "$BODY"
assert_contains "the text after is kept" $'\nafter' "$BODY"
assert_not_contains "the old block is gone" "stale text" "$BODY"
assert_contains "the new block is in" '`EXAMPLE_SITE`' "$BODY"
bash "$RENDER" --root "$ROOT" --write "$GUIDE" >/dev/null 2>&1
assert_eq "writing twice changes nothing" "$BODY" "$(cat "$GUIDE")"

echo "[write] a guide without the markers is refused and left alone"
printf '# Guide\nno block here\n' > "$GUIDE"
OUT=$(bash "$RENDER" --root "$ROOT" --write "$GUIDE" 2>&1); ST=$?
assert_eq "exit 2" 2 "$ST"
assert_eq "file untouched" $'# Guide\nno block here' "$(cat "$GUIDE")"

echo "[refused] an invalid manifest stops the render and prints nothing"
printf 'env:\n  - name: lower_case\n    source: "x"\n' >> "$ROOT/plugins/agentic-jira/pack.yaml"
OUT=$(bash "$RENDER" --root "$ROOT" 2>/dev/null); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_eq "no stdout" "" "$OUT"

echo "[usage] an unknown argument"
bash "$RENDER" --bogus >/dev/null 2>&1; ST=$?
assert_eq "exit 2" 2 "$ST"

echo
echo "pass=$PASS fail=$FAIL"
[[ "$FAIL" -eq 0 ]]
