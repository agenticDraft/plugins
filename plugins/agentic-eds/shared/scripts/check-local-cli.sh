#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/check-local-cli.sh
#
# This pack's `requires:` probe for the platform CLI. Run in the project's
# checkout. Both servers this pack starts — the project's own serve command and
# the draft server — run the project's own install of the CLI, so this asks
# only whether that install exists and can run. A copy found elsewhere on the
# machine does not count: the draft server never looks for one. Offline.
#
# Exit codes: 0 — present; 1 — absent.

[[ -x node_modules/.bin/aem ]]
