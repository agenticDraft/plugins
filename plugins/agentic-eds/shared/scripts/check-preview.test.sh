#!/usr/bin/env bash
# Tests for check-preview-config.sh and check-preview-host.sh. Run with:
#   bash plugins/agentic-eds/shared/scripts/check-preview.test.sh
#
# No framework — exits 0 on success, 1 on any failure.
#
# Nothing here reaches a network: `curl` is stubbed on PATH, and `origin` is a
# URL set on a local repository that is never fetched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_CHECK="$SCRIPT_DIR/check-preview-config.sh"
HOST_CHECK="$SCRIPT_DIR/check-preview-host.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-preview.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }
expect() {
  local desc="$1" want="$2" rc="$3" out="$4"
  [[ "$rc" == "$want" ]] && ok "$desc" || bad "$desc" "expected exit=$want, got exit=$rc" "output: $out"
}
has() {
  local desc="$1" needle="$2" out="$3"
  [[ "$out" == *"$needle"* ]] && ok "$desc" || bad "$desc" "expected to contain: $needle" "got: $out"
}

# A `curl` whose answer is chosen by FAKE_CURL (`up` or `down`); every call is
# recorded, so the URL the check asked for can be read back.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'CURL'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CURL_LOG"
[[ "$FAKE_CURL" == up ]] && exit 0
exit 22
CURL
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export FAKE_CURL_LOG="$WORK/curl.log"

# project <dir> <origin URL or empty> <suffix> <max_length>
project() {
  local dir="$WORK/$1"
  git init -q "$dir"
  [[ -n "$2" ]] && git -C "$dir" remote add origin "$2"
  mkdir -p "$dir/.ai"
  cat > "$dir/.ai/project-config.yaml" <<EOF
version: 1
paths:
  spec_dir: ".ai/specs"
branch_name:
  max_length: $4
platform:
  preview_host_suffix: "$3"
EOF
  echo "$dir"
}

echo "=== check-preview-config.sh ==="

P=$(project match git@github.com:Example-Org/Site-Repo.git --site-repo--example-org 39)
OUT=$(cd "$P" && bash "$CONFIG_CHECK" 2>&1); RC=$?
expect "config agrees with the current remote -> exit 0" 0 "$RC" "$OUT"

P=$(project moved git@github.com:New-Owner/Site-Repo.git --site-repo--example-org 39)
OUT=$(cd "$P" && bash "$CONFIG_CHECK" 2>&1); RC=$?
expect "a repository moved to another owner -> exit 1" 1 "$RC" "$OUT"
has "names the stale suffix and the derived one" "platform.preview_host_suffix is '--site-repo--example-org'; the remote derives '--site-repo--new-owner'" "$OUT"

P=$(project limit git@github.com:Example-Org/Site-Repo.git --site-repo--example-org 22)
OUT=$(cd "$P" && bash "$CONFIG_CHECK" 2>&1); RC=$?
expect "a stale branch limit -> exit 1" 1 "$RC" "$OUT"
has "names the stale limit and the derived one" "branch_name.max_length is 22; the remote derives 39" "$OUT"

P=$(project noorigin "" --site-repo--example-org 39)
OUT=$(cd "$P" && bash "$CONFIG_CHECK" 2>&1); RC=$?
expect "no origin remote -> exit 1" 1 "$RC" "$OUT"
has "says there is no origin" "no origin remote" "$OUT"

P=$(project nokey git@github.com:Example-Org/Site-Repo.git --site-repo--example-org 39)
printf 'version: 1\n' > "$P/.ai/project-config.yaml"
OUT=$(cd "$P" && bash "$CONFIG_CHECK" 2>&1); RC=$?
expect "a config without the derived keys -> exit 1" 1 "$RC" "$OUT"
has "names the missing key" "platform.preview_host_suffix" "$OUT"

OUT=$(cd "$WORK" && bash "$CONFIG_CHECK" --config "$WORK/absent.yaml" 2>&1); RC=$?
expect "a config that does not exist -> exit 1" 1 "$RC" "$OUT"

echo "=== check-preview-host.sh ==="

P=$(project host git@github.com:Example-Org/Site-Repo.git --site-repo--example-org 39)
: > "$FAKE_CURL_LOG"
OUT=$(cd "$P" && FAKE_CURL=up bash "$HOST_CHECK" 2>&1); RC=$?
expect "the default branch's preview answers -> exit 0" 0 "$RC" "$OUT"
has "asks the default branch's preview host for a synced code file" "https://main--site-repo--example-org.aem.page/scripts/aem.js" "$(cat "$FAKE_CURL_LOG")"
has "the request is bounded in time" "--max-time" "$(cat "$FAKE_CURL_LOG")"

OUT=$(cd "$P" && FAKE_CURL=down bash "$HOST_CHECK" 2>&1); RC=$?
expect "a preview host that does not answer -> exit 1" 1 "$RC" "$OUT"
has "names the host that did not answer" "main--site-repo--example-org.aem.page" "$OUT"

git -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/Release/Next
: > "$FAKE_CURL_LOG"
OUT=$(cd "$P" && FAKE_CURL=up bash "$HOST_CHECK" 2>&1); RC=$?
expect "a recorded default branch other than main -> exit 0" 0 "$RC" "$OUT"
has "uses that branch, lower case, '/' as '-'" "https://release-next--site-repo--example-org.aem.page/" "$(cat "$FAKE_CURL_LOG")"

P=$(project nosuffix git@github.com:Example-Org/Site-Repo.git --site-repo--example-org 39)
printf 'version: 1\n' > "$P/.ai/project-config.yaml"
: > "$FAKE_CURL_LOG"
OUT=$(cd "$P" && FAKE_CURL=up bash "$HOST_CHECK" 2>&1); RC=$?
expect "no suffix in the config -> exit 1" 1 "$RC" "$OUT"
[[ ! -s "$FAKE_CURL_LOG" ]] && ok "no request is made without a suffix" || bad "no request is made without a suffix" "$(cat "$FAKE_CURL_LOG")"

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
