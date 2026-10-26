#!/usr/bin/env bash
# Tests for commit-change.sh. Run with:
#   bash plugins/agentic-core/shared/lib/commit-change.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every case builds its
# own throwaway repository; nothing here reaches a remote.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMIT="$SCRIPT_DIR/commit-change.sh"

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
WORK="$(mktemp -d "$TMPDIR/commit-change-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

printf '%s\n' 'example-drafts/' '.ai/run-state.json' > "$WORK/paths.txt"

# fresh <name> — a repository with one commit, on a working branch. Echoes its path.
fresh() {
  local repo="$WORK/$1"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  printf 'base\n' > "$repo/tracked.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m base
  git -C "$repo" switch -q -c work
  echo "$repo"
}

committed_files() { git -C "$1" show --name-only --format= HEAD | sort; }

echo "=== commit-change.sh tests ==="

echo "[exclude] a working path is left out of the commit and stays in the tree"
R="$(fresh exclude)"
printf 'changed\n' > "$R/tracked.txt"
mkdir -p "$R/blocks/cards" "$R/example-drafts" "$R/.ai"
printf 'x\n' > "$R/blocks/cards/cards.css"
printf '<div></div>\n' > "$R/example-drafts/EX-1.plain.html"
printf '{}\n' > "$R/.ai/run-state.json"
OUT="$(bash "$COMMIT" "$R" "EX-1 a title" --exclude-file "$WORK/paths.txt" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "the commit holds only the change" 'blocks/cards/cards.css
tracked.txt' "$(committed_files "$R")"
check "the message is the one given" "EX-1 a title" "$(git -C "$R" log -1 --format=%s)"
check "first line names the commit and its file count" "committed: $(git -C "$R" rev-parse --short HEAD) (2 files)" "$(printf '%s\n' "$OUT" | head -1)"
check "each excluded path is named" 'left-out: .ai/run-state.json
left-out: example-drafts/EX-1.plain.html' "$(printf '%s\n' "$OUT" | grep '^left-out: ' | sort)"
check "the fixture is still on disk, untracked" "?? example-drafts/" "$(git -C "$R" status --porcelain -- example-drafts/)"

echo "[pre-staged] a working path someone already staged is still left out"
R="$(fresh prestaged)"
mkdir -p "$R/example-drafts"
printf '<div></div>\n' > "$R/example-drafts/EX-2.plain.html"
printf 'changed\n' > "$R/tracked.txt"
git -C "$R" add -A
OUT="$(bash "$COMMIT" "$R" "EX-2 title" --exclude-file "$WORK/paths.txt" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "the commit holds only tracked.txt" "tracked.txt" "$(committed_files "$R")"

echo "[tracked working path] a change to an already-tracked working path is not committed either"
R="$(fresh tracked-draft)"
mkdir -p "$R/example-drafts"
printf 'old\n' > "$R/example-drafts/old.plain.html"
git -C "$R" add -A && git -C "$R" commit -q -m "a draft committed earlier"
printf 'new\n' > "$R/example-drafts/old.plain.html"
printf 'changed\n' > "$R/tracked.txt"
OUT="$(bash "$COMMIT" "$R" "EX-3 title" --exclude-file "$WORK/paths.txt" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "the commit holds only tracked.txt" "tracked.txt" "$(committed_files "$R")"
check "the draft edit stays uncommitted" " M example-drafts/old.plain.html" "$(git -C "$R" status --porcelain -- example-drafts/)"

echo "[nothing] only working paths changed — nothing to commit is not an error"
R="$(fresh nothing)"
mkdir -p "$R/example-drafts"
printf '<div></div>\n' > "$R/example-drafts/EX-4.plain.html"
HEAD_BEFORE="$(git -C "$R" rev-parse HEAD)"
OUT="$(bash "$COMMIT" "$R" "EX-4 title" --exclude-file "$WORK/paths.txt" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "says nothing was committed" "nothing: no change to commit outside the working paths" "$(printf '%s\n' "$OUT" | head -1)"
check "HEAD did not move" "$HEAD_BEFORE" "$(git -C "$R" rev-parse HEAD)"

echo "[no exclude file] an absent file excludes nothing — the previous behaviour"
R="$(fresh no-file)"
mkdir -p "$R/example-drafts"
printf '<div></div>\n' > "$R/example-drafts/EX-5.plain.html"
OUT="$(bash "$COMMIT" "$R" "EX-5 title" --exclude-file "$WORK/absent.txt" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "the draft is committed" "example-drafts/EX-5.plain.html" "$(committed_files "$R")"

echo "[git failure] a commit git refuses is exit 1 with git's reason"
R="$(fresh hook)"
printf '#!/bin/sh\necho "hook refused" >&2\nexit 1\n' > "$R/.git/hooks/pre-commit"
chmod +x "$R/.git/hooks/pre-commit"
printf 'changed\n' > "$R/tracked.txt"
OUT="$(bash "$COMMIT" "$R" "EX-6 title" --exclude-file "$WORK/paths.txt" 2>&1)"; ST=$?
check "exit 1" 1 "$ST"
check "git's own stderr is passed through" "yes" "$([[ "$OUT" == *"hook refused"* ]] && echo yes || echo no)"

echo "[usage] missing message; not a repository"
bash "$COMMIT" "$WORK/exclude" >/dev/null 2>&1; ST=$?
check "missing message → exit 2" 2 "$ST"
mkdir -p "$WORK/plain"
bash "$COMMIT" "$WORK/plain" "title" >/dev/null 2>&1; ST=$?
check "not a repository → exit 2" 2 "$ST"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
