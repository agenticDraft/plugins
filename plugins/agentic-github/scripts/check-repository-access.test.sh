#!/usr/bin/env bash
# Tests for check-repository-access.sh. Run with:
#   bash plugins/agentic-github/scripts/check-repository-access.test.sh
#
# No framework — exits 0 on success, 1 on any failure.
#
# Nothing here touches GitHub: `gh` is stubbed, and `origin` is a URL set on a
# local repository that is never fetched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-repository-access.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-repository-access.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# A `gh` whose answer is chosen by FAKE_GH: `push` (access, may push), `read`
# (access, may not push), `other-owner` (the repository is not visible to this
# credential, as for a token whose resource owner is another account),
# `logged-out`. Every call is recorded.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
case "${1:-} ${2:-}" in
  "auth status") [[ "$FAKE_GH" == logged-out ]] && exit 1; exit 0 ;;
  "api repos/"*)
    case "$FAKE_GH" in
      push) echo true ;;
      read) echo false ;;
      other-owner) echo '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export FAKE_GH_LOG="$WORK/gh.log"

repo() {
  local dir="$WORK/$1"
  git init -q "$dir"
  [[ -n "$2" ]] && git -C "$dir" remote add origin "$2"
  echo "$dir"
}

check() { : > "$FAKE_GH_LOG"; (cd "$1" && FAKE_GH="$2" bash "$SCRIPT" >/dev/null 2>&1); }

echo "=== check-repository-access.sh tests ==="

R_SSH="$(repo ssh git@github.com:example-owner/example-repo.git)"
R_HTTPS="$(repo https https://github.com/example-owner/example-repo)"
R_NONE="$(repo none '')"

echo "[pass] the credential reaches the repository and may push"
check "$R_SSH" push; ST=$?
[[ $ST -eq 0 ]] && ok "exit 0" || bad "exit 0" "got $ST"
grep -q '^api repos/example-owner/example-repo ' "$FAKE_GH_LOG" && ok "asks about origin's owner/repo (ssh form)" || bad "repo from ssh remote" "$(cat "$FAKE_GH_LOG")"
check "$R_HTTPS" push; ST=$?
[[ $ST -eq 0 ]] && ok "https remote → exit 0" || bad "https remote → exit 0" "got $ST"
grep -q '^api repos/example-owner/example-repo ' "$FAKE_GH_LOG" && ok "asks about origin's owner/repo (https form)" || bad "repo from https remote" "$(cat "$FAKE_GH_LOG")"

echo "[fail] a token scoped to another owner cannot see the repository"
check "$R_SSH" other-owner; ST=$?
[[ $ST -ne 0 ]] && ok "non-zero exit" || bad "non-zero exit" "got $ST"

echo "[fail] access without push"
check "$R_SSH" read; ST=$?
[[ $ST -ne 0 ]] && ok "non-zero exit" || bad "non-zero exit" "got $ST"

echo "[fail] neither a login nor a token"
check "$R_SSH" logged-out; ST=$?
[[ $ST -ne 0 ]] && ok "non-zero exit" || bad "non-zero exit" "got $ST"
grep -q '^api ' "$FAKE_GH_LOG" && bad "no API call when logged out" "$(cat "$FAKE_GH_LOG")" || ok "no API call when logged out"

echo "[fail] no origin, or an origin that is not this host"
check "$R_NONE" push; ST=$?
[[ $ST -ne 0 ]] && ok "no origin → non-zero" || bad "no origin → non-zero" "got $ST"
R_OTHER="$(repo other https://example.invalid/example-owner/example-repo.git)"
check "$R_OTHER" push; ST=$?
[[ $ST -ne 0 ]] && ok "foreign host → non-zero" || bad "foreign host → non-zero" "got $ST"

echo "[quiet] the script prints nothing"
OUT="$(cd "$R_SSH" && FAKE_GH=other-owner bash "$SCRIPT" 2>&1)"
[[ -z "$OUT" ]] && ok "no output" || bad "no output" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
