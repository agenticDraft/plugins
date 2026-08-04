#!/bin/sh
# SessionStart hook: print the rules into the session context.
#
# The rules live in exactly one place -- the body of skills/be-honest/SKILL.md.
# This script strips the YAML frontmatter and prints the rest, so the hook and
# the /be-honest skill can never drift apart.
#
# A SessionStart hook that exits 0 has its plain stdout added to the context,
# so no JSON wrapper and no jq dependency is needed.

set -eu

SKILL="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}/skills/be-honest/SKILL.md"

if [ ! -r "$SKILL" ]; then
  echo "no-hallucinations: cannot read $SKILL" >&2
  exit 1
fi

echo "The following communication rules are active for this entire session, in every"
echo "project. They come from the no-hallucinations plugin and outrank the urge to sound"
echo "helpful or agreeable."
echo

# Print everything after the closing '---' of the frontmatter.
awk 'BEGIN { n = 0 }
     /^---$/ && n < 2 { n++; next }
     n >= 2' "$SKILL"
