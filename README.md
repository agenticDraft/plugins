# agenticDraft/plugins — Claude Code plugins

A small Claude Code plugin marketplace. Each plugin takes an instruction you would otherwise repeat in every session and turns it into something you install once, and that travels between machines and teammates.

The point of them is behaviour you can rely on, not behaviour you have to remember to ask for.

## The problem they solve

The instructions that matter most to how you work with Claude usually live in a global `CLAUDE.md` or get retyped at the start of a conversation. Telling it not to make things up. Telling it to say when it is unsure. Or asking it to slow down and walk you through a decision instead of handing you an opinion.

That works until you switch machines, share a repo with someone, or the context gets compacted and the instruction quietly drops out. Nothing tells you it is gone. The answers just drift back to confident and agreeable.

## How they handle it

Each plugin picks the Claude Code mechanism that matches how often its behaviour needs to apply:

1. **Always on: hooks.** `no-hallucinations` injects its rules with a `SessionStart` hook and repeats a one-line reminder on every prompt with a `UserPromptSubmit` hook, so the rules survive compaction. A skill alone can't do this: only a skill's description stays in context, and the body loads when the skill is invoked.
2. **On demand: a skill.** `made-decision` is a skill that runs a structured interview when you ask for it, or when you describe a dilemma in conversation. It stays out of the way the rest of the time.

Each plugin keeps a single source of truth. In `no-hallucinations`, the hook and the skill print the same `SKILL.md`, so the two can't drift apart.

## The plugins

| Plugin | What it does | How it runs | Details |
|---|---|---|---|
| **no-hallucinations** | Truthfulness rules for every response: no made-up facts or sources, uncertainty stated with the claim, no reflexive agreement | `SessionStart` + `UserPromptSubmit` hooks, plus the `be-honest` skill | [README](plugins/no-hallucinations/README.md) |
| **made-decision** | A six-step decision interview using OOCEMR: Outcomes, Options, Consequences, Evaluate, Mitigate, Resolve. One question at a time, and its own verdict only at the end | `decision-making` skill, invoked explicitly or triggered by a described dilemma | [README](plugins/made-decision/README.md) |

## The flow

```
.claude-plugin/marketplace.json   ── catalog "agenticdraft"
        ↓  /plugin marketplace add agenticDraft/plugins
        ↓  /plugin install <plugin>@agenticdraft
Claude Code session
        ├── no-hallucinations
        │     SessionStart      → full rules, once per session
        │     UserPromptSubmit  → one-line reminder, every prompt
        │     /no-hallucinations:be-honest → rules on demand
        └── made-decision
              /made-decision:decision-making <dilemma>
              or a described dilemma → six steps, one question per turn → summary + verdict
```

## What it looks like

**no-hallucinations, on every prompt**

This line is added to the context each time you send a message:

```
no-hallucinations: the communication rules injected at the start of this session apply to this
response too -- state uncertainty with the claim, do not invent sources, do not claim something
works unless you ran it, and disagree when I am wrong.
```

**made-decision, the first turn**

The skill and its evals require every message to open with a step marker, so you always know where you are:

```
**Step 1/6 — OUTCOMES**
```

## Running it yourself

1. Add the marketplace:

   ```bash
   /plugin marketplace add agenticDraft/plugins
   ```

2. Install what you want:

   ```bash
   /plugin install no-hallucinations@agenticdraft
   /plugin install made-decision@agenticdraft
   ```

3. Restart the session.
4. Check it: `/plugin` lists the plugin as enabled. `claude --debug` shows whether a hook fired and what it printed.

To enable a plugin for one repository only, and for everyone who opens it, commit a `.claude/settings.json` instead. [`example-project/`](example-project/) shows how. The marketplace key and the part after `@` must both be `agenticdraft`, or the plugin silently fails to resolve.

## Honest caveats

- A hook adds text as conversation context. A global `CLAUDE.md` goes into the system instructions. The docs don't say the two carry equal weight, and it hasn't been measured. That is why `no-hallucinations` repeats a reminder on every prompt.
- A skill's `model:` setting only applies to the turn that invokes it. For a long `made-decision` interview on Opus, pick the model with `/model` before you start. The Opus recommendation comes from the shape of the task and hasn't been benchmarked.
- `made-decision` ships scripted scenarios in `evals/evals.json`. They describe the expected behaviour; nothing in this repo runs them automatically.

## Why they are built this way

Every plugin here follows the same rule: put the behaviour where it will actually apply, and say plainly where it might not. Rules that must hold on every turn go in hooks, because a skill's body is only read on demand. A workflow that needs your attention goes in a skill, because it shouldn't run when you didn't ask for it.

A plugin that claims more than it can guarantee is worse than no plugin. So each README states its limits next to its features.

## Develop

```bash
git clone git@github.com:agenticDraft/plugins.git
cd plugins

# validate the catalog and every plugin it points to
claude plugin validate .

# validate one plugin (--strict turns unknown-field warnings into errors)
claude plugin validate ./plugins/<plugin-name> --strict

# try a plugin without installing it
claude --plugin-dir ./plugins/<plugin-name> -p "/<plugin-name>:<skill-name> <test prompt>"

# install from the local checkout
/plugin marketplace add ./
/plugin install <plugin-name>@agenticdraft
```

Adding a plugin: create `plugins/<name>/.claude-plugin/plugin.json` and `plugins/<name>/skills/<skill>/SKILL.md`, add an entry to `.claude-plugin/marketplace.json`, then run both validate commands. [`CLAUDE.md`](CLAUDE.md) lists the details and the known gotchas.

## Layout

```text
.claude-plugin/marketplace.json          # the catalog, one entry per plugin
plugins/
├── no-hallucinations/                   # always-on truthfulness rules (hooks + skill)
└── made-decision/                       # on-demand OOCEMR decision interview (skill + evals)
example-project/                         # per-project install via committed .claude/settings.json
```

## License

MIT — see [LICENSE](LICENSE).

---

Zoran Markovic · [linkedin.com/in/zoranzokimarkovic](https://www.linkedin.com/in/zoranzokimarkovic/)

Source: [github.com/agenticDraft/plugins](https://github.com/agenticDraft/plugins)
