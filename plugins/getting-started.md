# Getting started: the delivery plugins in a new project

This guide takes a project that has never used the delivery plugins to its first route run: one work item, read from your tracker, turned into a pull request.

## The plugins and which ones you need

All of them come from the `agenticdraft` marketplace (`agenticDraft/plugins`).

- `agentic-core` — **always.** The route driver: it runs the stages in order, checks every result and decides how the run ends. It names no tracker, SCM, design tool or browser.
- `agentic-jira`, `agentic-github`, `agentic-figma`, `agentic-playwright` — **always, all four.** One provider pack per role: tracker, SCM, design and browser. `setup` picks one installed pack for every role and stops when a role has none, so `agentic-figma` must be installed even when no work item has a design. A Figma login is a different matter: see "When the design tool is needed" below.
- `agentic-eds` — **only for an Edge Delivery Services (EDS) project.** It is the platform pack: it knows how such a project serves, lints and is built. For another platform, leave it out; `/agentic-core:setup` then generates a platform pack for your project from an interview. That path is not covered here.

Every plugin the project enables must also be installed. The driver starts each stage from the pack that owns it, and a pack that is not loaded ends the run; it is never worked around.

## How a run works, in short

A run is one command, `/agentic-core:run-route <work item>`, typed by a person or started by CI. It goes through fixed stages in a fixed order:

```text
intake → readiness → extract → conventions → serve → baseline → prototype → verify-design
       → plan → plan-gate → implement → verify → lint → publish-gate → deliver
```

- **intake** reads the work item from the tracker as untrusted text and records its facts.
- **readiness**, **plan-gate** and **publish-gate** are gates: scripts check first, then a reviewing model looks only at what the scripts passed. A gate never changes the project.
- Some stages run only when the item needs them. The conditions are evaluated once, right after intake, and a skipped stage hands over to the next one. With `agentic-eds`: `extract`, `prototype` and `verify-design` run only when the item has a design source or mentions a design; `baseline` runs only when the item names a component.
- The working branch is created right after readiness; `deliver` opens the pull request.

Before the first stage, the driver checks the project config, every pack, the tools and the credentials (pre-flight), and that the working tree has nothing uncommitted. A run ends in exactly one of three states:

- `delivered` — the last stage passed and the pull request exists.
- `blocked` — something is missing: an answer, a login, a tool. The run says what and where.
- `failed` — a stage failed or broke its contract. The run names the stage.

### When the design tool is needed

`agentic-figma` reads designs through the Figma plugin's MCP tools. The driver checks for those tools only when the design stages will run, and an item that never runs them never needs a Figma account or login.

Intake decides this from two facts, by literal word match, never by a model's judgement:

- **design source** — the item carries a design reference, such as a Figma link.
- **design mentioned** — the item's text contains one of the tracker pack's design words (`text_conventions.design_keywords` in its `pack.yaml`; for `agentic-jira` they include common words such as "layout" and "style", and block names such as "hero").

| Design source | Design mentioned | What happens |
| --- | --- | --- |
| no | no | The design stages are skipped. No Figma login is needed. |
| yes | yes or no | The design stages run. Without the Figma tools the run ends `blocked` before any work, with the remedy under `agentic-figma` below. |
| no | yes | Readiness refuses the item: it asks for a visual change and gives nothing to compare against. |

So an item without a design must also avoid those words. You do not need to learn the list: `write-specs` (step 7) runs the same extractor on the draft and names every word that matched.

## Before you start: what to prepare

Do this before step 1, so that `setup` never has to stop and wait for an account you do not have yet.

### What each pack needs

The block below is rendered from the packs' own manifests (`pack.yaml`), not written by hand, and a check fails when it differs from them. It lists, per pack, the variables and logins, the hosts, the tools on your machine and the conditions a run checks before it starts. Skip a pack's section only if the project does not use that pack (in practice: `agentic-eds` on a project that is not EDS).

<!-- guide-declarations:begin — rendered by scripts/render-guide-declarations.sh from the packs' pack.yaml files; refresh it with --write, never edit it by hand -->

#### agentic-eds (platform)

Hosts, added to the committed `.claude/settings.json` under `sandbox.network.allowedDomains`: `*.aem.page`

Tools on your machine:

- `aem-cli` — `setup` can install it with `npm install --save-dev @adobe/aem-cli`. If you do it yourself: add the CLI to the project's own dev dependencies before the run (npm install --save-dev @adobe/aem-cli), then commit package.json and the lock file

Checked before every run:

- `preview-config` — the repository's owner or name changed since setup: run agentic-core:setup again and choose re-detect
- `preview-host` — install the AEM Code Sync app (github.com/apps/aem-code-sync) on this repository's owner with this repository included, then push to the default branch

#### agentic-jira (tracker)

Variables, kept in `.claude/settings.local.json` under `env`:

- `JIRA_SITE` — the host name of your Jira Cloud site: the \<site\>.atlassian.net part of its address, without https://
- `JIRA_EMAIL` — the email address of the Atlassian account the API token belongs to
- `JIRA_API_TOKEN` — an Atlassian API token for that account: id.atlassian.com/manage-profile/security/api-tokens

Hosts, added to the committed `.claude/settings.json` under `sandbox.network.allowedDomains`: `*.atlassian.net`

#### agentic-github (scm)

Variables, kept in `.claude/settings.local.json` under `env`:

- `GH_TOKEN` — a GitHub fine-grained personal access token whose resource owner owns this repository, with access to it and Pull requests: read and write (github.com/settings/personal-access-tokens); set it only where nobody can log in, because gh prefers it to a login. A login replaces it: `gh auth login`

Hosts, added to the committed `.claude/settings.json` under `sandbox.network.allowedDomains`: `api.github.com`

Checked before every run:

- `repository-access` — run gh auth login, or give GH_TOKEN this repository's owner as resource owner, access to this repository, and Contents and Pull requests: read and write (github.com/settings/personal-access-tokens)

#### agentic-figma (design)

Session tools, which the plugin that serves them must provide before a run:

- `mcp__plugin_figma_figma__get_design_context`, `mcp__plugin_figma_figma__get_metadata`, `mcp__plugin_figma_figma__get_variable_defs`, `mcp__plugin_figma_figma__get_screenshot` — Plugin disabled: run /plugin, enable figma, restart the session. Enabled but not authenticated: run /mcp, select the figma server, Authenticate, finish sign-in in the browser.

#### agentic-playwright (browser)

Tools on your machine:

- `playwright` — reinstall or update this plugin so the host installs the playwright version its package.json pins; loaded by path, run npm ci in this plugin's root
- `chromium` — npx playwright@1.63.0 install chromium

#### Files in your repository

Kept out of git; `setup` adds each to `.gitignore`, never removing a line: `.claude/settings.local.json`, `.ai/run-context/`, `.ai/logs/`, `.ai/run-state.json`, `.ai/progress.md`, `.ai/route-progress.txt`, `drafts/`, `.ai/tracker/`, `.ai/scm/`, `.ai/figma/`, `.ai/playwright/`

Committed on purpose; `setup` names the ones it wrote for you to commit before the first run: `.ai/project-config.yaml`, `.ai/project-conventions.yaml`, `.ai/route-policy.yaml`, `.ai/specs/`, `.ai/design/`, `.ai/packs/`

<!-- guide-declarations:end -->

In plain words, for the two `agentic-playwright` tools: `setup` does not offer to install them, because the pack declares no install. If `health` (step 5) reports `playwright` missing, run `npm ci` in the installed plugin's own folder (the `installPath` that `claude plugin list --json` shows for `agentic-playwright`). If it reports `chromium` missing, run the `npx` line above from anywhere.

### What no pack declares

- **The tracker project** the work items live in, with the issue types you will use. With `agentic-eds`, the readiness gate knows three types: a `Story` and a `Task` need a description and acceptance criteria; a `Bug` needs a description, a reproduction URL and reproduction steps. Every page an item points at must exist for the whole run. An item of any other type is refused.
- **The tracker account id of everyone who may start a run from a tracker comment.** `setup` writes a placeholder for it in `.ai/project-config.yaml`, under `trigger.allowed_identities`, and you fill it by hand in step 4. Only the comment-triggered path (a token comment on the work item starts a headless run) compares it with the comment's author; a run you type in Claude Code does not read it. `setup` still checks that no placeholder is left, so fill it even if you never use that path. Use the form your tracker gives a comment's author; no pack states that form yet, so read it from your tracker rather than guessing.
- **Admin rights on the repository's owner.** The platform pack's code-sync step is done in the browser on the owner, and only an owner administrator can finish it.
- **Write access to the project's `.claude/` folder and to the plugin cache**, and a session that may leave the sandbox for the install lines in step 2. See "The sandbox" below.
- **A headless run only:** the model credential the runner reads, `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`), in the CI secret store. See "Before a headless run".

### The sandbox

If Claude Code runs with its sandbox on, a host is reachable only when it is allowed. The `/sandbox` command sets the mode, not hosts. Hosts are allowed by `sandbox.network.allowedDomains` in the settings, and a host you have not allowed fails with an error that looks like a bad credential (`gh` reports "Failed to log in" with a valid token).

You do not write this list: `setup` appends the hosts listed above to the committed `.claude/settings.json`, adding missing entries only. The setting is read when a session starts, so open a new session afterwards.

Two things stay outside the list on purpose. The package registry is not on it; `setup` runs a pack's declared install for one tool outside the sandbox, on your yes. And step 2's `install` lines write into `.claude/` and the plugin cache, which the sandbox refuses (`EPERM` on `.claude/.cc-writes`): run them outside it.

## 1. Add the marketplaces and the plugins to the project's `settings.json`

Write this as `.claude/settings.json` at the project root. You commit it in step 6, together with what `setup` writes, so every collaborator gets the same plugins:

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

JSON allows no comments; the blank line only separates the packs from the plugins they need.

**Not an EDS project?** Delete three things: the `agentic-eds@agenticdraft` line, the `aem-edge-delivery-services@adobe-skills` line and the whole `adobe-skills` marketplace. Keep every other line: `setup` needs a pack for each of the four provider roles.

- The key under `extraKnownMarketplaces`, the part after `@` in every `enabledPlugins` key, and the catalog's `name` (`agenticdraft`) must match exactly. A mismatch fails silently.
- `ref` pins the marketplace to a tag, so a project does not move when `main` does. One tag pins the core and every pack together. Put the newest tag in place of `<newest tag>`. This command prints it:

  ```sh
  git ls-remote --tags --refs --sort=-v:refname https://github.com/agenticDraft/plugins 'v*' | head -1 | cut -d/ -f3
  ```

  The list is also at [github.com/agenticDraft/plugins/tags](https://github.com/agenticDraft/plugins/tags). This page names no tag itself, so it cannot point at an old one.
- If `~/.claude/settings.json` also declares the `agenticdraft` marketplace with a different `ref`, the CLI refuses to move to another one. Make both files name the same tag.

### The two plugins from other marketplaces

- `figma@claude-plugins-official` — the Figma MCP server that `agentic-figma` calls. Enable it even if no item has a design yet; you sign in only when one does (see "When the design tool is needed").
- `aem-edge-delivery-services@adobe-skills` — Adobe's skills for writing blocks, styles and scripts. EDS projects only.

Notes on both:

- **Every marketplace in a committed file carries a `ref`.** A committed file reaches every collaborator and every headless run, so an unpinned marketplace puts its default branch into all of them. A marketplace source takes a branch or a tag in `ref`, not a commit.
- `<adobe-skills tag>`: `adobe/skills` tags each of its components separately (`web-cli-v2.0.0`), and a tag of any of them fixes the whole repository, catalog included. The tags page lists the newest component tag first, which is not what you want. Print the newest repository-wide tag instead, and move it by hand when the project wants a newer one:

  ```sh
  git ls-remote --tags --refs --sort=-v:refname https://github.com/adobe/skills 'v*' | head -1 | cut -d/ -f3
  ```
- `claude-plugins-official` is not declared under `extraKnownMarketplaces`. Claude Code adds Anthropic's official marketplace by itself the first time an interactive terminal session starts. On a machine that has never run one, such as a fresh CI runner, run `claude plugin marketplace add anthropics/claude-plugins-official` first.
- **Every enabled plugin also loads into headless route runs.** The runner reads the project's settings, and every plugin `enabledPlugins` turns on that is installed on the machine runs in the session next to the packs (`agentic-core/shared/runner/route-agent.mjs`, `plugin-sources.mjs`). Its startup log lists both sets. A plugin with a `SessionStart` hook adds its text to every route session. If a run behaves differently after you enable one, disable it for that run's settings first.

Other plugins that help while you work on the project, but that no pack needs, are listed at the end of this page.

## 2. Trust the folder and install the plugins

Open Claude Code in the project and accept the trust prompt for the folder. Project settings declare a marketplace and plugins, and Claude Code applies them only for a trusted folder.

Committing `enabledPlugins` turns the plugins on but does not install them on anyone's machine ([Install and manage plugins](https://code.claude.com/docs/en/discover-plugins#choose-an-install-scope)). On a machine that already knows the `agenticdraft` marketplace, the session starts with every pack reported `Plugin "agentic-<pack>" not cached at …` in the `/plugin` **Errors** tab, and no `.ai/` folder is written. So each collaborator runs this once, in a shell at the project root, outside the sandbox (the lines write into the project's `.claude/` and the plugin cache):

```sh
claude plugin install agentic-core@agenticdraft --scope project
claude plugin install agentic-eds@agenticdraft --scope project
claude plugin install agentic-jira@agenticdraft --scope project
claude plugin install agentic-github@agenticdraft --scope project
claude plugin install agentic-figma@agenticdraft --scope project
claude plugin install agentic-playwright@agenticdraft --scope project
claude plugin install figma@claude-plugins-official --scope project
claude plugin install aem-edge-delivery-services@adobe-skills --scope project
```

Run one line per plugin the settings enable; on a project that is not EDS, leave out the `agentic-eds` and `aem-edge-delivery-services` lines. Each prints `Successfully installed plugin: <plugin> (scope: project)`.

Check that it worked: every pack has a record whose `projectPath` is this project.

```sh
claude plugin list --json | jq -r --arg p "$(pwd -P)" '.[] | select(.projectPath == $p) | .id'
```

prints one line per installed plugin. A record for the same plugin with another `projectPath` belongs to another project and does not count. Without `jq`, read the `id`, `scope` and `projectPath` fields in `claude plugin list --json` by eye.

`install --scope project` also rewrites `.claude/settings.json`: it reorders the keys and reformats the file, and the content stays the same. Commit the result in step 6.

**Then start a new session.** Each pack's `SessionStart` hook writes its root into `.ai/run-context/plugin-roots/`, and the core finds the other packs through that folder. In the first session after the install, `ls .ai/run-context/plugin-roots/` lists one file per pack. Run `/agentic-core:setup` from that session on.

In a running session, `/plugin install agentic-core@agenticdraft` does the same as the shell command: it opens the plugin's details, and you choose project scope there.

## 3. Configure the project once

```text
/agentic-core:setup
```

`setup` writes `.ai/project-config.yaml` and everything the packs declared above that the project needs. It asks only what nothing in the project can answer, and shows everything it will write before it writes it.

**What it asks:**

- With a config already there: keep it, re-detect, or edit named keys.
- The local preview URL, when nothing in the project shows it.
- Which pack to use for a role, only when two installed packs serve it.
- **Accept** or **Change**, once, on the whole set of values it will write.
- **Filled** or **Later**, after it names the placeholders you fill by hand (step 4).
- For each missing tool whose pack declares an install: **Install now** or **I'll do it myself**. Install now runs the declared command once, outside the sandbox, after you approve it a second time in Claude Code's permission prompt; it may change tracked files (for the platform pack, `package.json` and the lock file), which it names and never commits.
- The platform pack's own setup: **Done** or **Later** for the code-sync step, and the URL where the site's content is authored (or **Skip**).

**What it never asks:** a token, a password, an account id, the spec directory (always `.ai/specs`), or anything it derives from the git remote, such as the branch-name limit and the preview host suffix.

**When it stops:** a role with no installed pack. It never writes a role as empty for you; install the missing pack (step 2) and run it again.

**What it writes**, always adding and never removing or overwriting what you filled: the config; one placeholder per variable listed above in `.claude/settings.local.json`; the hosts in the committed `.claude/settings.json`; the working-file paths in `.gitignore`; and, for the platform pack, the site's links in the project README. It flags host names in the project's instruction files that no longer match the repository, and does not edit them.

It ends with a report: the lines to fill, the files to commit, and that a new session is needed.

## 4. Fill in the placeholders and sign in

`setup` names each file and line. Each placeholder is the marker `FILL-IN:` followed by what goes there. Replace it with the value yourself, in the file; never paste a token into chat. There are two files:

- `.claude/settings.local.json` — one entry under `env` per variable listed above. For a variable that a login replaces, either fill it or log in (for `GH_TOKEN`: `gh auth login`).
- `.ai/project-config.yaml` — `trigger.allowed_identities` (see "What no pack declares").

Then answer **Filled**: `setup` checks both files again and names any placeholder still left. If you answered **Later**, the files are not checked yet: when you are done, run `/agentic-core:setup` again and choose **re-detect**. It keeps what you filled and checks the placeholders again (**keep** stops without checking anything).

Sign in to Figma (through `/mcp`, as the `agentic-figma` entry says) only when a work item has a design.

Then **start a new session**: the credentials and the sandbox allowlist are read once, when a session starts.

## 5. Check the environment

```text
/agentic-core:health
```

`health` only reads and reports; it never installs, fixes or blocks anything. It lists what is loaded, whether the config validates, which pack each role resolves to, each pack's preconditions with their remedies, each variable and host, and each pack's session tools (those are checked by the run itself, not here). Its last result line is **green** or **not green**: green only when the config validates, every role resolves, and nothing is missing, unfilled, blocked or failed. On not green, do what the named remedy says and run `health` again before step 6.

## 6. Commit and push the files `setup` named

A run starts only on a working tree with nothing uncommitted. `setup`'s report lists the files to commit (the config, the committed settings, `.gitignore`, and whatever an install changed); commit them and push them to the default branch before the first run. A commit that is not on the remote's default branch still counts as a change, and the run refuses to start. Do not ignore `.ai/` as a whole: some of what is in it is meant to be committed, and the block above says which.

## 7. Write the work item

A run reads its work item from the tracker, with fixed patterns, and the readiness gate accepts or refuses it before any work starts. Write the item with:

```text
/agentic-core:write-specs
```

Describe what should change, and name the item's key if it already exists. `write-specs` writes a draft to `.ai/specs/<ITEM-KEY>/draft.md`, runs its checker on it until it passes, writes the item to the tracker through the tracker pack, and runs the checker again on the live item. It ends with the item's key and URL. If the tracker pack cannot write the item, it says why first and hands you the summary and description to paste into the tracker yourself.

The item lives in the tracker project named under "What no pack declares", so that project and its issue types must exist first. An item with no design must not mention one (see "When the design tool is needed"); the checker names the words that matched.

Before the run, commit the draft and push it to the default branch. `.ai/specs/` is committed on purpose, and a run starts only when nothing differs from the default branch on the remote: a draft that is untracked, or committed but not pushed, makes it refuse to start (`refused: … changed: .ai/specs/<ITEM-KEY>/draft.md`).

## 8. Make the first route run

```text
/agentic-core:run-route <work item id or URL>
```

Only a person can start it: a model cannot call this command on its own. When a stage needs an answer, the run asks you; append `autonomous` to write blockers back to the work item instead of asking. The run ends in exactly one of `delivered`, `blocked` or `failed` (see "How a run works, in short"). A run that needs something this guide listed and you skipped ends `blocked` before it starts, with the pack's remedy. After `blocked` or `failed`, the run's state stays in `.ai/` for you to read; started again, a run younger than two hours resumes, and an older one asks whether to resume or start fresh.

## Before a headless run

A headless run (the runner, started by CI or a trigger) needs three things a bare project does not have:

- `.ai/route-policy.yaml`,
- a settings file carrying `sandbox.network.allowedDomains`, and
- the model credential in the runner's environment (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`).

The runner starts nothing without the first two: it exits `3` when the policy is missing and `6` when the allowlist is missing or unusable. An interactive session in steps 1 to 8 needs none of them.

## Letting Claude follow this guide

To have Claude do steps 1 and 2 for you, open Claude Code in the project and paste this into the first session, with the newest tag (step 1 says how to find it) in place of `<tag>`:

```text
Follow https://github.com/agenticDraft/plugins/blob/<tag>/plugins/getting-started.md step by step in this project,
steps 1 and 2 only. Do one step at a time and show me each file before you write it. Never write a token or
a password into a file that git tracks; I will set credentials myself. If a step needs something the guide
does not say, stop and tell me what is missing instead of guessing. When step 2 is done, tell me to start a new session.
```

Then start a second session and paste the same prompt with "step 3 only" in place of "steps 1 and 2 only" and without the last sentence. Fill in the placeholders yourself (step 4), open a third session, and continue with steps 5 to 8.

## Optional: plugins for working on the project

None of these is needed by a pack, so they stay out of the committed file and install at user scope, on your machine only:

- `playwright@claude-plugins-official` — a browser MCP server, for looking at a page by hand. No pack calls it: `agentic-playwright` drives its own Chromium through the `playwright` library.
- `skill-creator@claude-plugins-official` — creates and edits `SKILL.md` files and measures them.
- `superpowers@claude-plugins-official` — brainstorming, planning, test-driven development and debugging workflows. It has a `SessionStart` hook.
- `github@claude-plugins-official` — GitHub's MCP server: issues, pull requests, reviews.
- `code-review@claude-plugins-official` — reviews a pull request or the current diff.
- `commit-commands@claude-plugins-official` — commit, push and open a pull request in one command.
- `claude-md-management@claude-plugins-official` — audits and updates `CLAUDE.md` files.
- `diagram-design@diagram-design` — draws architecture, flow and sequence diagrams as HTML/SVG. Its marketplace (`cathrynlavery/diagram-design`) has no tags, so it cannot be pinned and stays out of the committed file.

Run in your shell:

```sh
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
claude plugin install playwright@claude-plugins-official
```

and the same `claude plugin install` line for each other plugin you want. With no `--scope`, `install` writes to user scope (`~/.claude/settings.json`). A user-scope plugin also loads into a headless route run on that machine if the runner's settings enable it (see "Every enabled plugin also loads into headless route runs" in step 1).

## What this guide has not verified

The block under "What each pack needs" is checked against the manifests by `scripts/check-getting-started.sh`. The text around it is not: it describes `setup`'s questions and writes, `health`'s report, `write-specs`' steps and how a run proceeds, from reading their skills and the pack manifests, not from a run. A run from a project that did not build the plugins, following only this page, has not been made yet. A step that needs something this page does not say is a defect in the page.

Measured earlier: step 2 on a machine that already knew the `agenticdraft` marketplace (before the install every pack was reported `not cached`; after the six `install --scope project` lines there were six records for the project, and the next session wrote six roots into `.ai/run-context/plugin-roots/`). Not measured: a machine that has never added the marketplace; the two `install` lines for `figma` and `aem-edge-delivery-services` inside step 2's block; the committed block with the `adobe-skills` `ref`; whether a `~/.claude/settings.json` that declares `adobe-skills` without that `ref` conflicts with it, as step 1 says happens for `agenticdraft`; the user-scope install lines; a headless route run with those plugins enabled; a project without `agentic-eds`; and `github.com` as an allowed host for a project whose git remote is HTTPS.
