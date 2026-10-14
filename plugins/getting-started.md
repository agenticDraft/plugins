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
      "source": { "source": "github", "repo": "agenticDraft/plugins", "ref": "v0.2.3" }
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
- `ref` pins the marketplace to a tag, so a project does not move when `main` does. One tag pins the core and every pack together. `v0.2.3` is the newest tag at the time of writing; the list is at [github.com/agenticDraft/plugins/tags](https://github.com/agenticDraft/plugins/tags).
- Leave a pack out of `enabledPlugins` only if the project does not use that role.
- If `~/.claude/settings.json` also declares the `agenticdraft` marketplace with a different `ref`, the CLI refuses to move to another one. Make both files name the same tag.

## 2. Trust the folder, then start a second session

Open Claude Code in the project and accept the trust prompt for the folder. Project settings declare a marketplace and plugins, and Claude Code applies them only for a trusted folder. On the first session after the trust, Claude Code fetches the marketplace and installs the declared plugins in the background; start a new session if they are not listed yet.

**The first session of a fresh project does not run the plugins' hooks.** Each plugin's `SessionStart` hook writes its root into `.ai/run-context/plugin-roots/`, and the core finds other plugins through that folder. After the first session it is empty, so run `/agentic-core:setup` from the second session on.

To install by hand instead:

```text
/plugin marketplace add agenticDraft/plugins
/plugin install agentic-core@agenticdraft
```

and the same for each other pack.

## 3. Give the provider packs what they need

- `agentic-jira`: the environment variables `JIRA_SITE`, `JIRA_EMAIL` and `JIRA_API_TOKEN`. The route also calls the Jira site's own hostname (`<site>.atlassian.net`); if the sandbox blocks it, add that host to `sandbox.network.allowedDomains`.
- `agentic-github`: `gh` installed and authenticated (`gh auth status`). If a stage reports an authentication failure, set `GH_TOKEN` to a fine-grained personal access token scoped to the one repository; the scopes are in the [`agentic-github` README](agentic-github/README.md).
- `agentic-figma`: the Figma plugin installed and signed in (OAuth) in the same session. Install it once with `claude plugin install figma@claude-plugins-official`, then complete its OAuth sign-in in a session (the plugin's own `authenticate` tool opens a browser link).
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

## What this guide has not verified

This guide was written from the plugins' own READMEs and from the settings form measured in a spike (`extraKnownMarketplaces` with a `ref`, then `enabledPlugins`). Three statements come from the project that developed the plugins and were not re-checked here: the Jira hostname allowlist, the need for `GH_TOKEN` in a sandboxed stage, and the Figma install and sign-in steps. A run from a project that did not build the plugins, following only this page, has not been made yet. A step that needs something this page does not say is a defect in the page.
