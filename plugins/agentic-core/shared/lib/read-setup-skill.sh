#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/read-setup-skill.sh <platform pack.yaml>
#
# Prints the skill a platform pack declares under `setup_skill:`
# (shared/pack-manifest.md), which the core's setup invokes as its last step
# as `<platform pack name>:<skill>`. Reads the manifest only; names no pack.
# The skill's existence is the manifest validator's question (validator 29).
#
# Output (stdout), one line:
#   setup_skill: <name>                                  exit 0
#   none: the platform pack declares no setup skill      exit 3
#   refused: <reason>                                    exit 1 — not a platform
#                                                        pack, or a malformed value
# Exit 2 — usage error or a missing file.

set -uo pipefail

FILE="${1:-}"
[[ -n "$FILE" ]] || { echo "usage: read-setup-skill.sh <platform pack.yaml>"; exit 2; }
[[ -f "$FILE" ]] || { echo "refused: $FILE does not exist"; exit 2; }

grep -qx 'kind: platform' "$FILE" || { echo "refused: $FILE is not a platform pack"; exit 1; }

line="$(grep -E '^setup_skill:' "$FILE" | head -1)"
[[ -n "$line" ]] || { echo "none: the platform pack declares no setup skill"; exit 3; }

if [[ "$line" =~ ^setup_skill:\ \"([a-z][a-z0-9-]*)\"$ ]]; then
  echo "setup_skill: ${BASH_REMATCH[1]}"
  exit 0
fi
echo "refused: setup_skill is malformed; run validate-pack-manifest.sh on $FILE"
exit 1
