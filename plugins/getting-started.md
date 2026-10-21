# Getting started: the delivery plugins in a new project

This guide takes a project that has never used the delivery plugins to its first route run. It uses six plugins from the `agenticdraft` marketplace (`agenticDraft/plugins`):

- `agentic-core` — the route driver and its checks. Names no tracker, SCM, design tool or browser.
- `agentic-eds` — the platform pack for an Edge Delivery project.
- `agentic-jira`, `agentic-github`, `agentic-figma`, `agentic-playwright` — the tracker, SCM, design and browser provider packs.

A project enables every pack it uses. The driver starts each stage as `Skill(<pack>:<skill>)`, and a pack that is not loaded is reported as a contract violation, not worked around.

`agentic-eds` is for an Edge Delivery project. For another platform, `/agentic-core:setup` can generate a platform pack from an interview; that path is not covered here.

## 1. Add the marketplace and the plugins to the project's `settings.json`

Commit this as `.claude/settings.json` at the project root, so every collaborator gets the same plugins:

```json
{
  "extraKnownMarketplaces": {
    "agenticdraft": {
      "source": { "source": "github", "repo": "agenticDraft/plugins", "ref": "<newest tag>" }
    }
  },
  "enabledPlugins": {
    "agentic-core@agenticdraft": true,
    "agentic-eds@agenticdraft": true,
    "agentic-jira@agenticdraft": true,
    "agentic-github@agenticdraft": true,
    "agentic-figma@agenticdraft": true,
    "agentic-playwright@agenticdraft": true
  }
}
```

- The key under `extraKnownMarketplaces`, the part after `@` in every `enabledPlugins` key, and the catalog's `name` (`agenticdraft`) must match exactly. A mismatch fails silently.
- `ref` pins the marketplace to a tag, so a project does not move when `main` does. One tag pins the core and every pack together. Put the newest tag in place of `<newest tag>`, here and in every block below. This command prints it:

  ```sh
  git ls-remote --tags --refs --sort=-v:refname https://github.com/agenticDraft/plugins 'v*' | head -1 | cut -d/ -f3
  ```

  The list is also at [github.com/agenticDraft/plugins/tags](https://github.com/agenticDraft/plugins/tags). This page names no tag itself, so it cannot point at an old one.
- Leave a pack out of `enabledPlugins` only if the project does not use that role.
- If `~/.claude/settings.json` also declares the `agenticdraft` marketplace with a different `ref`, the CLI refuses to move to another one. Make both files name the same tag.

### Third-party plugins the project also uses

The packs lean on plugins from other marketplaces, and the project that developed them used a few more while building. None of them is an `agenticdraft` plugin, so step 1's block does not turn them on.

#### Plugins a pack needs: commit them

- `figma@claude-plugins-official` — the design tool's MCP server. `agentic-figma` calls it; without it the design stages stop.
- `aem-edge-delivery-services@adobe-skills` — Adobe's skills for writing blocks, styles and scripts. Needed only next to `agentic-eds`.

To commit them for every collaborator, use this as `.claude/settings.json` instead of step 1's block:

```json
{
  "extraKnownMarketplaces": {
    "agenticdraft": {
      "source": { "source": "github", "repo": "agenticDraft/plugins", "ref": "<newest tag>" }
    },
    "adobe-skills": {
      "source": { "source": "github", "repo": "adobe/skills", "ref": "<adobe-skills tag>" }
    }
  },
  "enabledPlugins": {
    "agentic-core@agenticdraft": true,
    "agentic-eds@agenticdraft": true,
    "agentic-jira@agenticdraft": true,
    "agentic-github@agenticdraft": true,
    "agentic-figma@agenticdraft": true,
    "agentic-playwright@agenticdraft": true,

    "figma@claude-plugins-official": true,
    "aem-edge-delivery-services@adobe-skills": true
  }
}
```

JSON allows no comments; the blank line only separates the packs from the plugins they need. Delete `aem-edge-delivery-services` if the project does not use `agentic-eds`, and its marketplace with it.

- **Every marketplace in a committed file carries a `ref`.** A committed file reaches every collaborator and every headless run, so an unpinned marketplace puts its default branch into all of them. A marketplace source takes a branch or a tag in `ref`, not a commit.
- `<adobe-skills tag>`: `adobe/skills` tags each of its components separately, and a tag of any of them fixes the whole repository, catalog included. Use the newest one on [github.com/adobe/skills/tags](https://github.com/adobe/skills/tags), and move it by hand when the project wants a newer one.
- `claude-plugins-official` is not declared under `extraKnownMarketplaces`. Claude Code adds Anthropic's official marketplace by itself the first time an interactive terminal session starts. On a machine that has never run one, such as a fresh CI runner, run `claude plugin marketplace add anthropics/claude-plugins-official` first.
- Step 2's install applies to these two as well: `claude plugin install figma@claude-plugins-official --scope project` and `claude plugin install aem-edge-delivery-services@adobe-skills --scope project`.
- **The plugins here also load into headless route runs.** The runner reads the project's settings, and every plugin `enabledPlugins` turns on that is installed on the machine runs in the session next to the packs (`agentic-core/shared/runner/route-agent.mjs`, `plugin-sources.mjs`). Its startup log lists both sets. A plugin with a `SessionStart` hook adds its text to every route session. If a run behaves differently after you enable one, disable it for that run's settings first.

#### Plugins for working on the project: install them for yourself

- `playwright@claude-plugins-official` — a browser MCP server, for looking at a page by hand. No pack calls it: `agentic-playwright` drives its own Chromium through the `playwright` library.
- `skill-creator@claude-plugins-official` — creates and edits `SKILL.md` files and measures them.
- `superpowers@claude-plugins-official` — brainstorming, planning, test-driven development and debugging workflows. It has a `SessionStart` hook.
- `github@claude-plugins-official` — GitHub's MCP server: issues, pull requests, reviews.
- `code-review@claude-plugins-official` — reviews a pull request or the current diff.
- `commit-commands@claude-plugins-official` — commit, push and open a pull request in one command.
- `claude-md-management@claude-plugins-official` — audits and updates `CLAUDE.md` files.
- `diagram-design@diagram-design` — draws architecture, flow and sequence diagrams as HTML/SVG. Its marketplace (`cathrynlavery/diagram-design`) has no tags, so it cannot be pinned and stays out of the committed file.

None of them is needed by a pack, so they stay out of the committed file and install at user scope, on your machine only. Run in your shell:

```sh
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
claude plugin install playwright@claude-plugins-official
```

and the same `claude plugin install` line for each other plugin you want. With no `--scope`, `install` writes to user scope (`~/.claude/settings.json`). A user-scope plugin also loads into a headless route run on that machine if the runner's settings enable it; the bullet above applies.

## 2. Trust the folder and install the packs

Open Claude Code in the project and accept the trust prompt for the folder. Project settings declare a marketplace and plugins, and Claude Code applies them only for a trusted folder.

Committing `enabledPlugins` turns the packs on but does not install them on anyone's machine ([Install and manage plugins](https://code.claude.com/docs/en/discover-plugins#choose-an-install-scope)). On a machine that already knows the `agenticdraft` marketplace, the session starts with every pack reported `Plugin "agentic-<pack>" not cached at …` in the `/plugin` **Errors** tab, and no `.ai/` folder is written. So each collaborator runs this once, in a shell at the project root:

```sh
claude plugin install agentic-core@agenticdraft --scope project
claude plugin install agentic-eds@agenticdraft --scope project
claude plugin install agentic-jira@agenticdraft --scope project
claude plugin install agentic-github@agenticdraft --scope project
claude plugin install agentic-figma@agenticdraft --scope project
claude plugin install agentic-playwright@agenticdraft --scope project
```

Run one line per pack the settings enable. Each prints `Successfully installed plugin: agentic-<pack>@agenticdraft (scope: project)`.

Check that it worked: every pack has a record whose `projectPath` is this project.

```sh
claude plugin list --json | jq -r --arg p "$(pwd -P)" '.[] | select(.projectPath == $p) | .id'
```

prints one `agentic-<pack>@agenticdraft` line per pack. A record for the same pack with another `projectPath` belongs to another project and does not count. Without `jq`, read the `id`, `scope` and `projectPath` fields in `claude plugin list --json` by eye.

`install --scope project` also rewrites `.claude/settings.json`: it reorders the keys and reformats the file, and the content stays the same. Commit the result or restore the file; either is fine.

**Then start a new session.** Each pack's `SessionStart` hook writes its root into `.ai/run-context/plugin-roots/`, and the core finds the other packs through that folder. In the first session after the install, `ls .ai/run-context/plugin-roots/` lists one file per pack. Run `/agentic-core:setup` from that session on.

In a running session, `/plugin install agentic-core@agenticdraft` does the same as the shell command: it opens the plugin's details, and you choose project scope there.

## 3. Give the provider packs what they need

- `agentic-jira`: the environment variables `JIRA_SITE`, `JIRA_EMAIL` and `JIRA_API_TOKEN`. The route also calls the Jira site's own hostname (`<site>.atlassian.net`); if the sandbox blocks it, add that host to `sandbox.network.allowedDomains`.
- `agentic-github`: `gh` installed and authenticated (`gh auth status`). If a stage reports an authentication failure, set `GH_TOKEN` to a fine-grained personal access token scoped to the one repository; the scopes are in the [`agentic-github` README](agentic-github/README.md).
- `agentic-figma`: the Figma plugin installed and signed in (OAuth) in the same session. Install it as step 1's "Plugins a pack needs" says, then complete its OAuth sign-in in a session (the plugin's own `authenticate` tool opens a browser link).
- `agentic-playwright`: the playwright library and a headless Chromium on the machine. Its [README](agentic-playwright/README.md) gives the exact commands.

Keep tokens in an untracked file such as `.claude/settings.local.json`, in its `env` block, never in a committed one:

```json
{
  "env": {
    "JIRA_SITE": "your-site.atlassian.net",
    "JIRA_EMAIL": "you@example.com",
    "JIRA_API_TOKEN": "your_api_token_here",
    "GH_TOKEN": "your_github_token_here"
  },
  "sandbox": {
    "network": { "allowedDomains": ["your-site.atlassian.net"] }
  }
}
```

## 4. Configure the project once

```text
/agentic-core:setup
```

It detects the project's build, test, lint and serve commands and its git remote, proposes which installed provider pack serves each role, and asks you to confirm every value before it writes `.ai/project-config.yaml`. It does not choose the browser pack; set `packs.browser` by hand.

Then check the environment:

```text
/agentic-core:health
```

`health` reports what is loaded, which pack each role resolves to, and each pack's unmet preconditions with the remedy the pack states.

## 5. Make the first route run

```text
/agentic-core:run-route <work item id or URL>
```

Append `autonomous` to write blockers back to the work item instead of asking. A run ends in exactly one of three states: `delivered`, `blocked` or `failed`.

## Before a headless run

A headless run (the runner, started by CI or a trigger) needs two things a bare project does not have:

- `.ai/route-policy.yaml`, and
- a settings file carrying `sandbox.network.allowedDomains`.

The runner starts nothing without them: it exits `3` when the policy is missing and `6` when the allowlist is missing or unusable. An interactive session in steps 1 to 5 needs neither.

## Letting Claude follow this guide

To have Claude do steps 1 and 2 for you, open Claude Code in the project and paste this into the first session, with the newest tag (step 1 says how to find it) in place of `<tag>`:

```text
Follow https://github.com/agenticDraft/plugins/blob/<tag>/plugins/getting-started.md step by step in this project,
steps 1 and 2 only. Do one step at a time and show me each file before you write it. Never write a token or
a password into a file that git tracks; I will set credentials myself. If a step needs something the guide
does not say, stop and tell me what is missing instead of guessing. When step 2 is done, tell me to start a new session.
```

Then start a second session and paste the same prompt with "steps 3 to 5 only" in place of "steps 1 and 2 only" and without the last sentence.

## What this guide has not verified

This guide was written from the plugins' own READMEs and from the settings form measured in a spike (`extraKnownMarketplaces` with a `ref`, then `enabledPlugins`). Three statements come from the project that developed the plugins and were not re-checked here: the Jira hostname allowlist, the need for `GH_TOKEN` in a sandboxed stage, and the Figma install and sign-in steps. A run from a project that did not build the plugins, following only this page, has not been made yet. The prompts in "Letting Claude follow this guide" have not been run.

Step 2 was measured on a machine that already knew the `agenticdraft` marketplace, in a new project holding step 1's block: before the install the session reported all six packs `not cached`, and no pack record had that project as `projectPath`. After the six `install --scope project` lines there were six such records, and the next session's hooks wrote six roots into `.ai/run-context/plugin-roots/`, each pointing at a directory that exists. Not measured: a machine that has never added the marketplace. The docs say a trusted session clones a declared marketplace the machine lacks; run the install lines after that session either way.

The third-party plugin names were checked against each marketplace's catalog. Not measured: the committed block with the `adobe-skills` `ref`; whether a `~/.claude/settings.json` that declares `adobe-skills` without that `ref` conflicts with it, as step 1 says happens for `agenticdraft`; the user-scope install lines; and a headless route run with those plugins enabled. A step that needs something this page does not say is a defect in the page.
