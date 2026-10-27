#!/usr/bin/env bash
# Sourced by test suites: . "$SCRIPT_DIR/register-source-tree.sh"
#
# register_source_tree <project dir>
#
# Registers every plugin of the source tree this core sits in, into
# <project dir>/.ai/run-context/plugin-roots/, through register-plugin-root.sh
# exactly as each plugin's SessionStart hook would. The roots come from
# resolve-plugin-root.sh --list --siblings, so a suite reaches the shipped
# plugins without building a path to them. Afterwards
# `resolve-plugin-root.sh --list --project-dir <project dir>` lists them.
#
# Returns non-zero, with the reason on stderr, when the tree lists no plugin
# or any registration is refused.
#
# in_source_tree
#
# Returns 0 only when this file is the core's own copy inside a source tree:
# its folder is `shared/lib` of a plugin whose folder is named as its
# plugin.json says. An installed copy sits in a version-named folder, and a
# pack's copy of the core sits under the pack's `core/`, so both return 1.
# There the other plugins are not this core's siblings, and a suite that
# needs them reports `skipped:` instead.

in_source_tree() {
  local lib root name
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  [[ "$(basename "$(dirname "$lib")")" == shared ]] || return 1
  root="$(dirname "$(dirname "$lib")")"
  [[ -f "$root/.claude-plugin/plugin.json" ]] || return 1
  name="$(sed -n 's/^  "name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)"
  [[ -n "$name" && "$name" == "$(basename "$root")" ]]
}

register_source_tree() {
  local project="$1" lib listed name root
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  mkdir -p "$project" || return 1
  listed=$(bash "$lib/resolve-plugin-root.sh" --list --siblings --project-dir "$project") || return 1
  while IFS=$'\t' read -r name root; do
    [ -n "$root" ] || continue
    CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$project" \
      bash "$lib/register-plugin-root.sh" || return 1
  done <<< "$listed"
}
