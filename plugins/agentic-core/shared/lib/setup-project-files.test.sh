#!/usr/bin/env bash
# The project-files half of setup, end to end, in a fixture project (D139):
# collect the configured packs' declarations, write the credentials
# placeholders, the host allowlist and the ignore rules, run it all a second
# time, commit what setup names, and ask the run's own fresh-start guard.
# Run with:
#   bash plugins/agentic-core/shared/lib/setup-project-files.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every value below is a
# made-up test string.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    must not contain: $needle"; echo "    got: $haystack"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/setup-project-files-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
# No global ignore file may hide the credentials file for the fixture.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$WORK/xdg"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test

# A project cloned from a bare origin, so origin/HEAD exists as on a real clone.
git init -q --bare "$WORK/origin.git"
git init -q "$WORK/seed"
echo "# fixture" > "$WORK/seed/README.md"
git -C "$WORK/seed" add README.md && git -C "$WORK/seed" commit -q -m init
git -C "$WORK/seed" push -q "$WORK/origin.git" HEAD:refs/heads/main
git -C "$WORK/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$WORK/origin.git" "$WORK/project"
P="$WORK/project"

# Five packs registered as their SessionStart hooks would; a sixth installed but not chosen.
mkdir -p "$P/.ai/run-context/plugin-roots" "$WORK/plugins"
install_pack() {
  local name="$1" fixture="$2" tail="$3" root="$WORK/plugins/$1"
  cp -R "$FIXDIR/$fixture" "$root"
  [[ -n "$tail" ]] && printf '%s\n' "$tail" >> "$root/pack.yaml"
  (cd "$root" && pwd -P) > "$P/.ai/run-context/plugin-roots/$name"
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
hosts: ["api.example-scm.test"]
ignore_paths: [".ai/example-scm/"]'
install_pack example-browser provider-valid 'ignore_paths: [".ai/example-browser/"]'
install_pack example-unchosen provider-valid 'env:
  - name: UNCHOSEN_TOKEN
    source: "a token for a pack this project did not choose"'

cat > "$P/.ai/project-config.yaml" <<'EOF'
version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser
EOF
# The install step left a committed settings file behind, as it does on a real project.
mkdir -p "$P/.claude"
printf '{\n  "enabledPlugins": {\n    "example-platform@example": true\n  }\n}\n' > "$P/.claude/settings.json"
git -C "$P" add .claude/settings.json && git -C "$P" commit -q -m "install" && git -C "$P" push -q origin HEAD

# The project-files step of setup, in the order the skill runs it.
DECL=".ai/run-context/pack-declarations.txt"
run_setup_files() {
  (
    cd "$P" || exit 1
    bash "$SCRIPT_DIR/collect-pack-declarations.sh" .ai/project-config.yaml > "$DECL" || exit 1
    bash "$SCRIPT_DIR/write-credential-placeholders.sh" "$DECL"
    bash "$SCRIPT_DIR/write-sandbox-hosts.sh" "$DECL"
    bash "$SCRIPT_DIR/write-ignore-rules.sh" "$DECL"
  )
}

echo "[first run] the credentials file appears with placeholders only and git ignores it"
OUT=$(run_setup_files 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
CRED="$P/.claude/settings.local.json"
assert_eq "the credentials file exists" "yes" "$([[ -f "$CRED" ]] && echo yes || echo no)"
assert_eq "every value is a placeholder" "true" "$(jq '[.env[] | startswith("FILL-IN: ")] | all' "$CRED")"
assert_eq "the configured packs' variables, and only those" "EXAMPLE_API_TOKEN,EXAMPLE_SITE" \
  "$(jq -r '.env | keys | join(",")' "$CRED")"
(cd "$P" && git check-ignore -q -- .claude/settings.local.json); assert_eq "git ignores the credentials file" 0 $?
assert_not_contains "git status never lists it" "settings.local" "$(git -C "$P" status --porcelain --untracked-files=all)"
assert_eq "the hosts are in the committed settings" \
  '["*.example-preview.test","*.example-tracker.test","api.example-scm.test"]' \
  "$(jq -c '.sandbox.network.allowedDomains' "$P/.claude/settings.json")"
assert_eq "the install's own setting is kept" "true" "$(jq '.enabledPlugins["example-platform@example"]' "$P/.claude/settings.json")"

echo "[second run] filled keys, existing hosts and existing ignore lines are untouched"
jq '.env.EXAMPLE_SITE = "test-value-site-123"' "$CRED" > "$WORK/c" && cat "$WORK/c" > "$CRED"
jq '.sandbox.network.allowedDomains += ["hand-added.example.test"]' "$P/.claude/settings.json" > "$WORK/s" \
  && cat "$WORK/s" > "$P/.claude/settings.json"
echo "hand-added-line/" >> "$P/.gitignore"
for f in .claude/settings.local.json .claude/settings.json .gitignore; do cp "$P/$f" "$WORK/before.${f//\//_}"; done
OUT=$(run_setup_files 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
for f in .claude/settings.local.json .claude/settings.json .gitignore; do
  cmp -s "$P/$f" "$WORK/before.${f//\//_}"; assert_eq "$f byte-identical" 0 $?
done
assert_not_contains "no value printed" "test-value-site-123" "$OUT"

echo "[commit] after committing the files setup names, a fresh run's clean-tree check passes"
NAMED=$(cd "$P" && bash "$SCRIPT_DIR/name-files-to-commit.sh" "$DECL")
assert_eq "names the config, the ignore file and the settings" "commit: .ai/project-config.yaml
commit: .gitignore
commit: .claude/settings.json" "$NAMED"
(cd "$P" && sed -n 's/^commit: //p' <<< "$NAMED" | xargs git add -- && git commit -q -m "setup" && git push -q origin HEAD)
OUT=$(bash "$SCRIPT_DIR/check-tree-clean.sh" "$P" 2>&1); ST=$?
assert_eq "check-tree-clean exit 0" 0 "$ST"
assert_eq "clean" "clean: no change and no untracked path" "$OUT"
assert_not_contains "the credentials file never reached a commit" "settings.local" "$(git -C "$P" log --all --name-only --format=)"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
