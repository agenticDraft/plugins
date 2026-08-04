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

There is no test runner in this repo. Each plugin that ships one keeps scripted scenarios in
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

## Known gotchas (learned the hard way in this repo)

- **Marketplace-name changes are not migrated automatically.** Renaming the GitHub repo is
  safe (GitHub redirects, and the marketplace's `name` field is unrelated to the repo name),
  but changing `marketplace.json`'s top-level `name` breaks every existing
  `/plugin install ...@<old-name>` for users who already added it — there's no equivalent of
  the per-plugin `renames` map for the marketplace name itself.
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
example-project/                     # reference for project-scoped install via committed .claude/settings.json
```

`example-project/.claude/settings.json` demonstrates the `extraKnownMarketplaces` +
`enabledPlugins` pattern for auto-installing a plugin for every collaborator who trusts the
repo folder. The key in `extraKnownMarketplaces`, the part after `@` in `enabledPlugins`, and
`marketplace.json`'s `name` field must all match exactly, or the plugin silently fails to
resolve.
