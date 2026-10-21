# agenticDraft plugins — a delivery route and the behaviours around it

Eight Claude Code plugins in one marketplace. Six of them form a delivery system that takes a work item from a tracker to a pull request. Two are small, always-available behaviours for how Claude answers.

Short presentation: https://agenticdraft.github.io/aem-eds-ai-workflow-demo/ 

**Everything here is checked by a script where a script can check it, and the limits are written next to the features.**

## The problem it solves

Two kinds of instruction get retyped in every session.

The first is how Claude should answer: do not make things up, say when you are unsure, slow down on a decision. These live in a global `CLAUDE.md` or in the first message, and they drop out when you switch machines, share a repo, or the context is compacted. Nothing tells you they are gone.

The second is how a piece of work gets delivered: read the ticket, plan, build, check it renders, lint, open the pull request, write back to the ticket. Done by hand it is a checklist. Done by a single long prompt it drifts: the driver re-does part of a step, reads files it should not, and branches on prose.

## How it handles it

1. **Behaviour that must hold on every turn is a hook.** `no-hallucinations` injects its rules at `SessionStart` and a one-line reminder on every prompt. A skill alone cannot do that: only its description stays in context, and the body loads when it is invoked.
2. **Behaviour that needs your attention is a skill.** `made-decision` runs a six-step interview when you ask for it, and stays out of the way otherwise.
3. **The delivery route is split into a driver and packs.** `agentic-core` runs the stages and names no product. A *platform pack* (`agentic-eds`) says what each stage means for an Edge Delivery project. Four *provider packs* fill the roles the stages call: tracker (`agentic-jira`), SCM (`agentic-github`), design (`agentic-figma`) and browser (`agentic-playwright`).
4. **Every stage returns one shape.** The last thing a stage emits is a result envelope: `verdict: pass | warn | fail | question`, a one-line summary, the artifacts it wrote. The driver reads that and nothing else, so it cannot drift into re-doing a stage's work.
5. **A run ends in exactly one of three states:** `delivered`, `blocked` or `failed`. `warn` is never terminal.
6. **Decisions that can be scripts are scripts.** Validators, branch-name checks, readiness checks and gates run a script first; a model reviews only what the script cannot judge. Each script has a `.test.sh` beside it.

## The plugins

| Plugin | Role | What it does | README |
|---|---|---|---|
| **no-hallucinations** | behaviour | Truthfulness rules for every response, through two hooks and a skill | [README](no-hallucinations/README.md) |
| **made-decision** | behaviour | A six-step decision interview (Outcomes, Options, Consequences, Evaluate, Mitigate, Resolve) | [README](made-decision/README.md) |
| **agentic-core** | driver | Runs the route, validates each result, ends in a terminal state. Skills `setup`, `health`, `run-route` | [README](agentic-core/README.md) |
| **agentic-eds** | platform | Binds the fifteen route stages to an Edge Delivery project | [README](agentic-eds/README.md) |
| **agentic-jira** | tracker | Fetch, comment on, attach to, list, update and create Jira work items | [README](agentic-jira/README.md) |
| **agentic-github** | scm | Create a branch, publish a pull request, read its checks | [README](agentic-github/README.md) |
| **agentic-figma** | design | Fetch a Figma node's values, assets and a reference screenshot | [README](agentic-figma/README.md) |
| **agentic-playwright** | browser | Render, capture, measure and interact with a page in headless Chromium | [README](agentic-playwright/README.md) |

The core knows four roles by name (`tracker`, `scm`, `design`, `browser`) and never learns which product fills one. The project's `.ai/project-config.yaml` maps each role to a plugin. Swapping Jira for another tracker means a new provider pack, not a change to the core.

## How the plugins find each other

An installed plugin lives in its own versioned folder, such as `~/.claude/plugins/cache/agenticdraft/agentic-jira/0.2.4/`. The path changes with every version, and `..` from one plugin does not reach another. So no plugin knows where another one is. **Each plugin says where it is, and the others ask by name.**

1. **Role to name: project config.** `packs:` in `.ai/project-config.yaml` maps each role to a plugin name. The core gets every name from there and holds none of its own.
2. **Name to folder: the root registry.** At `SessionStart`, every plugin's own hook runs [`register-plugin-root.sh`](agentic-core/shared/lib/register-plugin-root.sh). It writes that plugin's `${CLAUDE_PLUGIN_ROOT}` to `.ai/run-context/plugin-roots/<name>`, one file per plugin with one line in it. The name comes from the plugin's `plugin.json`, not from its folder, because the folder is called `0.2.4`. The file is written to a temp name and then moved into place, so a reader never sees half a line. The hook prints nothing, because a `SessionStart` hook's stdout becomes session context.
3. **Lookup: one reader.** [`resolve-plugin-root.sh <name>`](agentic-core/shared/lib/resolve-plugin-root.sh) is the only script that reads the registry. The driver's pre-flight, `setup`, `health`, the branch-name check and every stage that needs another pack all go through it.
4. **Pack to core: the `core` link.** A pack does not use the registry to reach the core. In the source tree each pack holds `core`, a symlink to `../agentic-core/shared`. In a copy installed from the git marketplace that link arrives as a real folder of files. Either way a pack reaches the core's contracts and scripts as `${CLAUDE_PLUGIN_ROOT}/core/<path>`.

```text
session start
  ├── agentic-core hook ──→ .ai/run-context/plugin-roots/agentic-core
  ├── agentic-eds hook  ──→ .ai/run-context/plugin-roots/agentic-eds
  └── … one file per enabled plugin
                                   ↓
stage needs the tracker
  → project config: packs.tracker = agentic-jira
  → resolve-plugin-root.sh agentic-jira
      1. entry names a folder that exists   → print it, exit 0
      2. entry names anything else          → refused, exit 3
      3. no entry → sibling folder beside the core (only when loaded by path from one tree)
      4. otherwise                          → not resolved, exit 1
  → caller runs the pack's skill or script; what comes back is still a result envelope
```

The edge that matters is step 2. A broken entry is refused. The resolver never falls back to the sibling guess when an entry exists. A caller that gets a non-zero exit stops. It never builds a path itself and never treats the pack as optional.

**The three outcomes, run on 2026-10-20** (paths shortened):

```text
$ resolve-plugin-root.sh agentic-jira
~/.claude/plugins/cache/agenticdraft/agentic-jira/0.2.3
exit 0

$ resolve-plugin-root.sh agentic-jira        # entry names /nope/agentic-jira/0.2.9
refused: agentic-jira — registry entry <project>/.ai/run-context/plugin-roots/agentic-jira names '/nope/agentic-jira/0.2.9', not a directory
exit 3

$ resolve-plugin-root.sh agentic-zzz
not resolved: agentic-zzz — no registry entry at <project>/.ai/run-context/plugin-roots/agentic-zzz, no folder at ~/.claude/plugins/cache/agenticdraft/agentic-core/agentic-zzz
exit 1
```

The first result shows the registry's limit. The pin was already `0.2.4`, but the entry still named `0.2.3`. That entry was last written five days earlier. It resolved because the `0.2.3` folder was still in the cache. **The registry holds whatever the last hook that ran wrote, and the resolver checks only that the folder exists, not its version.** The full rule, and what was measured before it was adopted, is item 8 under "How it handles it" in [the core's README](agentic-core/README.md#how-it-handles-it).

## The flow

```text
/agentic-core:setup ──→ .ai/project-config.yaml   (packs, commands, paths, limits)

/agentic-core:run-route <work item>
  ↓  pre-flight: config and every pack manifest valid
  ↓
intake ──→ readiness ──→ [extract] ──→ conventions ──→ serve ──→ [baseline]
                                          ↓
  ──→ [prototype] ──→ [verify-design] ──→ plan ──→ plan-gate ──→ implement
  ──→ verify ──→ lint ──→ publish-gate ──→ deliver
                                          ↓
                       delivered | blocked | failed

[extract] [prototype] [verify-design]   only when the item has a design reference
[baseline]                               only when the project already has components
```

Each stage is a skill the platform pack provides, run isolated; the stages that touch a tracker, a repository, a design file or a browser call the provider pack for that role. The non-obvious edge: a stage is never told which stages ran before it. It reads the fact record and its own inputs at fixed paths, and only the driver knows the shape of the run.

## What it looks like

**A stage's result, as the driver sees it** (the shape `agentic-core` validates):

```text
## Result
verdict: pass
summary: Fetched the work item.
artifacts:
  - .ai/run-context/fact-record.yaml
next_action: none
```

**The tests, run from the six installed `0.2.3` copies in a plugin cache and from the source clone, 2026-10-14:**

```text
$ bash scripts/run-tests.sh ~/.claude/plugins/cache/agenticdraft/*/0.2.3
files=585 fail=0
$ bash scripts/run-tests.sh
files=141 fail=0
```

Of the 585 files, 445 are the five packs' copies of the core's own tests. Some cases skip themselves when run from an installed copy (they need the source layout); the skips do not fail the run.

## Running it yourself

For a project that wants the delivery route, follow the [getting-started guide](getting-started.md): the `settings.json` that adds the marketplace at a tag, the credentials each provider pack needs, `/agentic-core:setup`, `/agentic-core:health`, then `/agentic-core:run-route <work item>`.

For the two behaviour plugins:

1. Add the marketplace and install what you want:

   ```text
   /plugin marketplace add agenticDraft/plugins
   /plugin install no-hallucinations@agenticdraft
   /plugin install made-decision@agenticdraft
   ```

2. Restart the session.
3. Check it: `/plugin` lists the plugin as enabled. `claude --debug` shows whether a hook fired and what it printed.

To enable a plugin for one repository, and for everyone who opens it, commit a `.claude/settings.json` instead. [`../example-project/`](../example-project/) shows how. The marketplace key and the part after `@` must both be `agenticdraft`, or the plugin silently fails to resolve.

## Limits you should know

- **A route needs every pack its config names.** The core ships no stage and no operation. An unloaded pack is reported as a contract violation, not worked around.
- **A run from a project that did not build the plugins has not been made yet.** The tests pass from installed copies; the guide has been written, not followed end to end by someone starting from nothing.
- **Committing the settings does not install the packs.** Each collaborator runs `claude plugin install <pack>@agenticdraft --scope project` once per pack; the plugin-root registry is written by the first session after that. [The guide](getting-started.md)'s step 2 has the commands and the check.
- **`setup` does not choose the browser pack.** Set `packs.browser` by hand.
- **Pre-flight reads declarations only.** A tool missing from the machine is found by `health` or by the operation that needs it, not before the run starts.
- **A hook adds text as conversation context.** A global `CLAUDE.md` goes into the system instructions. The docs do not say the two carry equal weight, and it has not been measured. That is why `no-hallucinations` repeats a reminder on every prompt.
- **`made-decision` ships scripted scenarios in `evals/evals.json`.** They describe the expected behaviour; nothing in this repository runs them automatically.

## Why it is built this way

Put the behaviour where it will actually apply, and say plainly where it might not. Rules that must hold on every turn go in hooks. A workflow that needs your attention goes in a skill. A delivery step that a script can decide is a script.

The delivery core is a small instance of one rule: what the driver cannot see, it cannot drift into re-doing. A pack can be swapped only because the core never learned its name. A plugin that claims more than it can guarantee is worse than no plugin, so each README states its limits next to its features.

## Develop

[`../CLAUDE.md`](../CLAUDE.md) lists the commands, the versioning rule (a plugin whose files changed carries a new `version` in its `plugin.json` and in the catalog) and the known gotchas. The catalog is [`../.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json). The licence is MIT: [`../LICENSE`](../LICENSE).

---

Zoran Markovic · [linkedin.com/in/zoranzokimarkovic](https://www.linkedin.com/in/zoranzokimarkovic/)

Source: [github.com/agenticDraft/plugins](https://github.com/agenticDraft/plugins)
