# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`agenticDraft/plugins` is a **Claude Code plugin marketplace**: a single `.claude-plugin/marketplace.json`
catalog plus one directory per plugin under `plugins/`. It has no application code, build step,
or package manager — everything here is Markdown (skill instructions), JSON (manifests, hooks,
evals), and small shell scripts.

The marketplace's public identifier is **`agenticdraft`** (the `name` field in
`.claude-plugin/marketplace.json`), independent of the GitHub repo name. Users install with
`/plugin install <plugin-name>@agenticdraft`.

## Commands

Run these from the repository root unless noted otherwise.

```bash
# Validate the marketplace catalog (checks marketplace.json schema, duplicate names,
# path traversal, and re-validates every plugin's plugin.json it can reach)
claude plugin validate .

# Validate a single plugin's manifest and skill/hook/agent frontmatter.
# --strict turns unknown-field warnings into errors.
claude plugin validate ./plugins/<plugin-name> --strict

# Smoke-test a plugin locally without installing it (loads only that plugin for the run)
claude --plugin-dir ./plugins/<plugin-name> -p "/<plugin-name>:<skill-name> <test prompt>"

# Install from a local checkout inside a running Claude Code session
/plugin marketplace add ./
/plugin install <plugin-name>@agenticdraft

# Confirm a hook fired and inspect what it printed
claude --debug
```

The delivery plugins (`agentic-*`) ship offline tests, run together by `scripts/run-tests.sh`:

```bash
(cd plugins/agentic-core/shared/runner && npm ci)   # once
bash scripts/run-tests.sh [dir ...]                 # every *.test.sh and *.test.mjs; prints files=<n> fail=<n>
bash scripts/check-plugin-versions.sh origin/main   # rule below, as CI runs it on a pull request
```

```bash
bash scripts/run-tests.sh plugins/agentic-core              # one plugin's suites (what CI runs)
bash plugins/agentic-core/shared/lib/<name>.test.sh         # a single shell suite
node --test plugins/agentic-core/shared/runner/<name>.test.mjs   # a single runner suite
```

A file that cannot run counts as a failure; do not skip a suite to make a run green. On macOS the
`resolve-plugin-root` test needs a `TMPDIR` under `/private/tmp`.

**A plugin whose files changed carries a new `version` in its `plugin.json`, and the catalog entry
in `marketplace.json` carries the same one.** CI (`check-plugin-versions.yaml`) fails a pull request
otherwise.

### Release tag

- A change to any file under `plugins/agentic-*` ships as a release: bump `version` in the
  changed plugins' `plugin.json` and `marketplace.json` (existing rule), and after the pull
  request is merged, tag the merge commit on `main` as `v<MAJOR>.<MINOR>.<PATCH>`.
- The tag equals the bumped `version` (the agentic-* plugins move together, so one tag per
  release). Format is exactly `vX.Y.Z`; no suffixes, no other prefixes.
- Consumers pin the marketplace to this tag (`extraKnownMarketplaces` ref and the `_plugins`
  checkout ref in aem-eds-ai-workflow-demo) and find the newest release by listing `v*` tags.
  A merged change without a tag is invisible to them.
- Creating and pushing a tag is outward-facing: propose the number, and create it only after
  the human says yes. Never move or delete an existing tag; a fix is a new patch version.
- The pull request description states the proposed tag.

`no-hallucinations` and `made-decision` have no test runner: they keep scripted scenarios in
`plugins/<plugin-name>/evals/evals.json` (query + expected-behavior checklist per scenario) —
treat these as the spec to check a skill's behavior against when editing it, not as something
invoked by a command in this repo.

## Adding a new plugin or skill

**Check the official docs before starting, every time — do not rely on memory or on this
file for exact schema/behavior.** This ecosystem is versioned aggressively; the docs below
are full of `Requires Claude Code vX.Y.Z` gates on individual fields and behaviors, so
something that worked last month may have gained a new required field or a new default.

- Plugin structure and authoring: https://code.claude.com/docs/en/plugins
- Marketplace/manifest schema: https://code.claude.com/docs/en/plugin-marketplaces
- Skill frontmatter reference (all fields, not just the ones used in this repo so far):
  https://code.claude.com/docs/en/skills

1. Create `plugins/<name>/.claude-plugin/plugin.json` (`name`, `description`, `version`,
   `author`, `homepage`/`repository` both set to `https://github.com/agenticDraft/plugins`,
   `license`, `keywords`).
2. Add skill(s) at `plugins/<name>/skills/<skill-name>/SKILL.md` — always the namespaced
   subdirectory form (`skills/<skill-name>/SKILL.md`), not a bare `skills/SKILL.md`, so the
   plugin can grow additional skills later.
3. Append an entry for the plugin to the `plugins` array in the root
   `.claude-plugin/marketplace.json`, mirroring the fields already there (`source` as a
   relative `./plugins/<name>` path, matching `homepage`/`repository` URLs).
4. Run both validate commands above before committing.

## The no-hallucinations plugin's hook/skill pattern

`plugins/no-hallucinations/` injects its rules two ways — a `SessionStart` hook (full rules,
once per session) and a `UserPromptSubmit` hook (one-line reminder every turn, to survive
context compaction) — plus an on-demand `skills/be-honest/SKILL.md`. All three must say the
same thing, so **`skills/be-honest/SKILL.md` is the single source of truth**:
`scripts/inject-rules.sh` strips its YAML frontmatter and prints the body verbatim for the
`SessionStart` hook (see `hooks/hooks.json`). When changing the rules, edit the skill file
only — never hand-edit the hook's injected text separately, or the two will drift apart.

## The agentic-* delivery core (big picture)

- **The core names roles, never products.** `agentic-core` defines four roles (`tracker`, `scm`,
  `design`, `browser`) and fifteen stage ids; platform and provider packs bind them to their own
  skills. Product names live only in packs.
- **Every stage returns one result envelope** (`shared/result-envelope.md`: `verdict`, `summary`,
  `artifacts`, `next_action`). The driver, `skills/run-route`, reads only that envelope, never
  the files under `artifacts:`, and never retries a stage. A `PreToolUse` hook on `Read`
  (`skills/run-route/scripts/check-driver-read.sh`) enforces it while a run is live.
- **A run ends in exactly one of `delivered`, `blocked`, `failed`.** `warn` is never terminal.
  Questions are asked at stage boundaries only (`verdict: question`).
- **Configuration is one file**, `.ai/project-config.yaml`, written by the `setup` skill and read
  by every pack.
- **Logic that can be a script is a script**: `shared/lib/*.sh` holds the validators and writers
  the driver and packs call, each with a `.test.sh` beside it. A new script there needs one.
- **CI-enforced guards on shipped files**: `shared/lib/validate-naming-rule.sh` scans the core for
  a product-name denylist; `shared/lib/check-no-narrative.sh` rejects a path this repository does
  not publish (resolved with `git check-ignore`) and any provenance/rationale section heading.
  A README or skill that cites a planning document fails both CI and the local suite.

## Known gotchas (learned the hard way in this repo)

- **Marketplace-name changes are not migrated automatically.** Renaming the GitHub repo is
  safe (GitHub redirects, and the marketplace's `name` field is unrelated to the repo name),
  but changing `marketplace.json`'s top-level `name` breaks every existing
  `/plugin install ...@<old-name>` for users who already added it — there's no equivalent of
  the per-plugin `renames` map for the marketplace name itself.
- **A `directory`-source marketplace hardcodes an absolute path — renaming or moving the
  checkout breaks it**, with a `Marketplace file not found at <old path>` warning on every
  startup. The declaration lives in `~/.claude/settings.json` under
  `extraKnownMarketplaces.<name>.source.path`; `~/.claude/plugins/known_marketplaces.json` is
  only a cache derived from it, so patching the cache alone is silently overwritten. There is
  no "repoint" command — run `claude plugin marketplace remove <name>`, then
  `claude plugin marketplace add <absolute-path> --scope user`. Note that `remove` also
  uninstalls that marketplace's plugins and drops them from `enabledPlugins`, so reinstall each
  one afterwards. The `github`-source form used in `example-project/.claude/settings.json` is
  immune. The upside of a directory source: plugins load live from the working tree (hooks
  included, not from `~/.claude/plugins/cache/`), so edits apply on the next session with no
  reinstall.
- **Don't verify hooks from a sandboxed shell.** A nested `claude -p` run inside Claude Code's
  Bash sandbox cannot write under `~/.claude/`, so every plugin hook dies with
  `EPERM: operation not permitted, mkdir '.../plugins/data/<plugin>-<marketplace>'` and the
  session looks exactly as if the plugin never loaded. The plugin is fine; the test harness
  isn't. Check `~/.claude/debug/latest` for those EPERM lines before concluding a hook is
  broken, and re-run the check outside the sandbox.
- **`claude plugin validate` only understands plugin/marketplace manifest directories** — it
  is not a general JSON/settings validator. Don't point it at an arbitrary `settings.json`.
- **A skill's `model:` frontmatter field only pins the model for the turn that invokes the
  skill.** The session model resumes on the very next message. It cannot be used to force an
  entire multi-turn conversation (e.g. `made-decision`'s six-step interview) onto one model —
  document a manual `/model` recommendation in the plugin's README instead.

## Repository layout

```text
.claude-plugin/marketplace.json      # the catalog — one entry per plugin, source paths relative to repo root
plugins/
  no-hallucinations/                 # hook-driven, always-on truthfulness rules (see pattern above)
  made-decision/                     # on-demand OOCEMR decision-making interview skill
  agentic-core/                      # delivery route driver; agentic-eds/jira/github/figma/playwright
  agentic-eds/ agentic-jira/ ...     #   are its platform and provider packs (see plugins/getting-started.md)
scripts/                             # run-tests.sh, check-plugin-versions.sh
.github/workflows/                   # validate-* per plugin group, check-plugin-versions
plugins/getting-started.md           # new-project guide; plugins/README.md describes the whole project
example-project/                     # reference for project-scoped install via committed .claude/settings.json
```

`example-project/.claude/settings.json` demonstrates the `extraKnownMarketplaces` +
`enabledPlugins` pattern for auto-installing a plugin for every collaborator who trusts the
repo folder. The key in `extraKnownMarketplaces`, the part after `@` in `enabledPlugins`, and
`marketplace.json`'s `name` field must all match exactly, or the plugin silently fails to
resolve.

Each `agentic-*` pack resolves its siblings by plugin `name` through `agentic-core`'s resolver, never by
folder path, and `plugins/agentic-eds/core` is a symlink to `../agentic-core/shared`. Skills are
invoked as `agentic-<pack>:<skill>`; the official Figma plugin's `figma:figma-design-to-code` is not ours
and keeps its name.
