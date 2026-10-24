#!/usr/bin/env bash
# write-provider-packs.sh — Mechanical merge of the five `packs:` values —
# platform, tracker, scm, design, browser — into a project config file (see
# shared/project-config.md). No judgment involved: the caller has already
# detected and confirmed the values with a human; this script only places
# them in the fixed shape.
#
# The five are written together, as one block, because the block is replaced
# wholesale rather than edited line by line. A caller with a value for only
# some of them has not finished detecting; it either carries the others
# forward from the file it is updating, or it has nothing to write yet.
#
# Usage:
#   write-provider-packs.sh <config-path> <platform> <tracker> <scm> <design> <browser>
#
# Behavior:
#   - <config-path> does not exist: creates its parent directory if needed,
#     then creates it with `version: 1` plus the `packs:` block.
#   - <config-path> exists and already has a `packs:` block in a shape this
#     script wrote — the five roles, or the tracker/scm[/design] block an
#     earlier version wrote — the whole block is replaced; every other line in
#     the file is left untouched.
#   - <config-path> exists, has a `version:` line, but no `packs:` block yet
#     (the shape write-detected-config.sh alone produces): a `packs:` block
#     is inserted immediately after `version:` (and the blank line that
#     follows it, if any); every other line is left untouched.
#
# Unlike commands/paths values, a pack name is written unquoted — see
# shared/project-config.md's own example (`platform: example-platform`).
#
# Exit codes:
#   0 — success; "written: <path>" or "updated: <path>" on stdout
#   1 — contract violation: an empty value, a value containing a
#       double quote (would corrupt the line), an existing `packs:` block
#       not in the shape this script wrote, or no `version:` line to anchor
#       an insertion against
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: write-provider-packs.sh <config-path> <platform> <tracker> <scm> <design> <browser>" >&2
  exit 2
fi

CONFIG_PATH="$1"
PLATFORM="$2"
TRACKER="$3"
SCM="$4"
DESIGN="$5"
BROWSER="$6"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for pair in "platform:$PLATFORM" "tracker:$TRACKER" "scm:$SCM" "design:$DESIGN" "browser:$BROWSER"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ -z "$value" ]] && fail "packs.${key} is empty"
  [[ "$value" == *'"'* ]] && fail "packs.${key} value contains a double quote, which would corrupt the line"
done

# Sub-key order is the config schema's own: platform, tracker, scm, design,
# browser.
packs_block() {
  cat <<EOF
packs:
  platform: $PLATFORM
  tracker: $TRACKER
  scm: $SCM
  design: $DESIGN
  browser: $BROWSER
EOF
}

if [[ ! -f "$CONFIG_PATH" ]]; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  {
    echo "version: 1"
    echo
    packs_block
  } > "$CONFIG_PATH"
  echo "written: $CONFIG_PATH"
  exit 0
fi

# --- update/insert path: splice into an existing file ----------------------
# Read line-by-line into an array rather than a single builtin call, for
# portability across installed shell versions (the same reason
# validate-project-config.sh reads this way).
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$CONFIG_PATH"
n=${#LINES[@]}

find_line() {
  local pattern="$1"
  local i
  for ((i = 0; i < n; i++)); do
    [[ "${LINES[i]}" == "$pattern" ]] && { echo "$i"; return 0; }
  done
  return 1
}

if packs_idx=$(find_line "packs:"); then
  # Three shapes are recognised, because a file written by an earlier version
  # of this script is still a file it owns: the five roles (6 lines), or the
  # header plus tracker/scm (3 lines), optionally then design (4 lines). Each
  # is replaced wholesale by the current block; anything else is a block this
  # script did not write and must not rewrite blind.
  SHAPE="'packs:' followed by platform/tracker/scm/design/browser, or by tracker/scm optionally then design"
  first=$((packs_idx + 1))
  if [[ "${LINES[packs_idx + 1]:-}" =~ ^\ \ platform:\  ]]; then
    first=$((packs_idx + 2))
  fi
  [[ "${LINES[first]:-}" =~ ^\ \ tracker:\  ]] || fail "existing 'packs:' block is not in the expected shape ($SHAPE)"
  [[ "${LINES[first + 1]:-}" =~ ^\ \ scm:\  ]] || fail "existing 'packs:' block is not in the expected shape ($SHAPE)"
  packs_block_len=$((first + 2 - packs_idx))
  if [[ "${LINES[first + 2]:-}" =~ ^\ \ design:\  ]]; then
    packs_block_len=$((packs_block_len + 1))
  fi
  if (( first == packs_idx + 2 )); then
    [[ "${LINES[packs_idx + packs_block_len]:-}" =~ ^\ \ browser:\  ]] \
      || fail "existing 'packs:' block is not in the expected shape ($SHAPE)"
    packs_block_len=$((packs_block_len + 1))
  fi

  OUT=()
  i=0
  while ((i < n)); do
    if ((i == packs_idx)); then
      while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
      i=$((i + packs_block_len))
      continue
    fi
    OUT+=("${LINES[i]}")
    i=$((i + 1))
  done

  printf '%s\n' "${OUT[@]}" > "$CONFIG_PATH"
  echo "updated: $CONFIG_PATH"
  exit 0
fi

version_idx=$(find_line "version: 1") || {
  # version's integer isn't fixed at 1 forever — fall back to a pattern match
  # for any "version: <int>" line before failing.
  for ((i = 0; i < n; i++)); do
    [[ "${LINES[i]}" =~ ^version:\ [0-9]+$ ]] && { version_idx=$i; break; }
  done
  [[ -z "${version_idx:-}" ]] && fail "no 'version:' line found to insert a 'packs:' block after"
}

insert_at=$((version_idx + 1))
if [[ "${LINES[insert_at]:-}" == "" ]]; then
  insert_at=$((insert_at + 1))
fi

OUT=()
i=0
while ((i < n)); do
  if ((i == insert_at)); then
    while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
    OUT+=("")
  fi
  OUT+=("${LINES[i]}")
  i=$((i + 1))
done
if ((insert_at == n)); then
  OUT+=("")
  while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
fi

printf '%s\n' "${OUT[@]}" > "$CONFIG_PATH"
echo "updated: $CONFIG_PATH"
exit 0
