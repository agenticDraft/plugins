#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/run-declared-install.sh <pack.yaml> <tool>
#
# run-declared-install.sh <path-to-pack.yaml> <tool>
#
# Runs the `install` argv a pack declares for one `requires:` entry (see
# shared/pack-manifest.md), then asks the entry's own probe again, and names
# every file the install changed. The one script in the core that changes the
# machine. Its only caller is the core setup step, and only after the human
# answered "Install now" for this tool in this session; every other reader of
# `requires:` skips the `install` line unread.
#
# Runs in the project root (the git top level of the current directory), so a
# probe and an install that name project-relative paths answer about the
# project wherever this was called from. The argv runs exactly as declared,
# with no shell between; an argument prefixed `<pack>/` resolves against the
# directory holding the manifest. It runs at most once per call and is never
# retried. Nothing is staged or committed: the changed files are named for the
# human to commit.
#
# What changed is read from git, before and after: every path the status
# lists, with a fingerprint of its content. A path whose fingerprint differs,
# or that is listed on one side only, is named. A change made before the
# install is not named unless the install changed it again. Ignored paths are
# never listed, so an install's own download directory stays out of the list.
# A path holding a newline is not supported.
#
# Output (stdout); the install's own output goes to stderr unchanged:
#   present: <tool> — nothing run       the probe already passes
#   installed: <tool>                   the install ran and the probe passes
#   failed: <tool> — <reason>           the install exited non-zero, or the
#                                        probe still fails after it
#   changed: <path>                     one per changed file, sorted, after
#                                        `installed:` or `failed:`
#   no-install: <tool>                  the entry declares no `install`
#   remedy: <remedy>                    after `failed:` and `no-install:`
#
# Exit codes:
#   0 — installed, or already present
#   1 — failed
#   2 — usage error: wrong arguments, manifest not found, the tool not
#       declared, a malformed entry, or not inside a git work tree
#   3 — the entry declares no `install`; nothing was run

set -uo pipefail

usage() {
  echo "usage: run-declared-install.sh <path-to-pack.yaml> <tool>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
FILE="$1"
TOOL="$2"
[[ -f "$FILE" ]] || { echo "invalid: file not found: $FILE" >&2; exit 2; }
PACK_ROOT="$(cd "$(dirname "$FILE")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "invalid: not inside a git work tree: $(pwd)" >&2; exit 2; }
cd "$ROOT" || exit 2

malformed() {
  echo "invalid: malformed 'requires.$TOOL' entry — $1" >&2
  exit 2
}

# Read the file the way the manifest validator does: line at a time, blank
# lines and full-line comments dropped.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}

start=-1
for ((i = 0; i < n; i++)); do
  [[ "${LINES[i]}" == "requires:" ]] && { start=$i; break; }
done
(( start >= 0 )) || { echo "invalid: the manifest declares no 'requires:'" >&2; exit 2; }

# Walk the entries until this tool's; take its probe, install and remedy.
probe_raw="" install_raw="" remedy="" found=0 has_install=0
i=$((start + 1))
while (( i < n )); do
  [[ "${LINES[i]}" =~ ^\ \ -\ tool:\ (.+)$ ]] || break
  entry_tool="${BASH_REMATCH[1]}"
  i=$((i + 1))
  [[ "${LINES[i]:-}" =~ ^\ \ \ \ probe:\ \[(.*)\]$ ]] || { [[ "$entry_tool" == "$TOOL" ]] && malformed "no 'probe:' list"; break; }
  entry_probe="${BASH_REMATCH[1]}"
  i=$((i + 1))
  entry_install="" entry_has_install=0
  if [[ "${LINES[i]:-}" =~ ^\ \ \ \ install: ]]; then
    [[ "${LINES[i]}" =~ ^\ \ \ \ install:\ \[(.*)\]$ ]] || { [[ "$entry_tool" == "$TOOL" ]] && malformed "'install' is not a list"; break; }
    entry_install="${BASH_REMATCH[1]}"
    entry_has_install=1
    i=$((i + 1))
  fi
  [[ "${LINES[i]:-}" =~ ^\ \ \ \ remedy:\ \"(.*)\"$ ]] || { [[ "$entry_tool" == "$TOOL" ]] && malformed "no 'remedy:'"; break; }
  entry_remedy="${BASH_REMATCH[1]}"
  i=$((i + 1))
  if [[ "$entry_tool" == "$TOOL" ]]; then
    found=1 probe_raw="$entry_probe" install_raw="$entry_install"
    has_install=$entry_has_install remedy="$entry_remedy"
    break
  fi
done
(( found == 1 )) || { echo "invalid: the manifest declares no tool '$TOOL' under 'requires:'" >&2; exit 2; }

# Split a declared list into ARGV: on commas, each argument trimmed, the
# `<pack>/` prefix resolved against the pack root — the same reading
# check-requires.sh gives a probe.
split_argv() {
  local raw="$1" arg
  ARGV=()
  IFS=',' read -ra RAW <<< "$raw"
  for arg in "${RAW[@]:-}"; do
    arg="${arg#"${arg%%[![:space:]]*}"}"
    arg="${arg%"${arg##*[![:space:]]}"}"
    [[ -z "$arg" ]] && continue
    [[ "$arg" == "<pack>/"* ]] && arg="$PACK_ROOT/${arg#<pack>/}"
    ARGV+=("$arg")
  done
}

probe_passes() {
  split_argv "$probe_raw"
  (( ${#ARGV[@]} > 0 )) || malformed "an empty probe"
  "${ARGV[@]}" >/dev/null 2>&1
}

if (( has_install == 0 )); then
  echo "no-install: $TOOL"
  echo "remedy: $remedy"
  exit 3
fi

if probe_passes; then
  echo "present: $TOOL — nothing run"
  exit 0
fi

# One line per path the status lists: "<path><TAB><fingerprint>". A file's
# fingerprint is its content hash, a deleted one's is "deleted", an untracked
# directory's is the hash of its files' hashes.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/run-declared-install.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

snapshot() {
  local out="$1" entry code path fp
  : > "$out.raw"
  git status --porcelain=v1 -z --untracked-files=normal > "$WORK/status" || exit 2
  while IFS= read -r -d '' entry; do
    code="${entry:0:2}" path="${entry:3}"
    # A rename or copy carries its original path in the next field.
    [[ "$code" == R* || "$code" == C* ]] && IFS= read -r -d '' _
    if [[ -d "$path" ]]; then
      fp="$(find "$path" -type f -print0 | sort -z | xargs -0 git hash-object -- 2>/dev/null | git hash-object --stdin)"
    elif [[ -e "$path" ]]; then
      fp="$(git hash-object -- "$path")"
    else
      fp="deleted"
    fi
    printf '%s\t%s\n' "${path%/}" "$fp" >> "$out.raw"
  done < "$WORK/status"
  LC_ALL=C sort "$out.raw" > "$out"
}

snapshot "$WORK/before"

split_argv "$install_raw"
(( ${#ARGV[@]} > 0 )) || malformed "an empty install"
"${ARGV[@]}" >&2 </dev/null
install_rc=$?

snapshot "$WORK/after"

status=1
if (( install_rc != 0 )); then
  echo "failed: $TOOL — the install exited $install_rc"
elif probe_passes; then
  echo "installed: $TOOL"
  status=0
else
  echo "failed: $TOOL — the probe still fails after the install"
fi
# A line only in one snapshot is a path whose fingerprint changed, or that
# appeared or disappeared; comm indents the second column's lines by a tab.
LC_ALL=C comm -3 "$WORK/before" "$WORK/after" \
  | awk -F'\t' '{ print ($1 == "" ? $2 : $1) }' | LC_ALL=C sort -u \
  | while IFS= read -r path; do echo "changed: $path"; done

(( status == 0 )) || echo "remedy: $remedy"
exit "$status"
