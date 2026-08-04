# no-hallucinations

A Claude Code plugin that keeps a short set of truthfulness rules in context **for every
response, in every project** — no made-up facts or sources, uncertainty stated with the claim,
and no reflexive agreement.

It's the "how to talk to me" section people usually paste into their global `CLAUDE.md`, turned
into something installable that travels between machines and teammates.

## The rules

> These rules apply in every response, in every project. They take precedence over the urge to
> sound helpful, confident, or agreeable at the expense of accuracy.

- **If you don't know, say so.** "I don't know" is a good answer.
- **Don't invent sources, citations, statistics, or study titles.**
- **Mark what you saw versus what you inferred.**
- **Uncertainty goes with the claim, not in a footnote at the end.**
- **"It works" means you ran it and saw it.** A skipped or failed step gets reported, not shown as done.
- **Say when something may have changed since your training.**
- **Don't just agree with me.** If the logic is off, say so and why.
- **If something isn't going to work, say so before we waste time.**
- **If the question is unclear, ask before answering.**

The full text lives in one place: [`skills/be-honest/SKILL.md`](plugins/no-hallucinations/skills/be-honest/SKILL.md).

## Install

```bash
/plugin marketplace add agenticDraft/plugins
/plugin install no-hallucinations@agenticdraft
```

Restart the session. To scope it to a single repo instead of your whole machine, commit a
`.claude/settings.json` — see [`example-project/`](example-project/).

## Why a hook and not just a skill

This is the part that isn't obvious, so it's worth spelling out.

A skill **cannot** replace `CLAUDE.md`. Per the
[skills docs](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill), only a skill's
`description` sits in context permanently; the body loads *when the skill is invoked*. And the
[plugins reference](https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout)
states it directly:

> A `CLAUDE.md` file at the plugin root is not loaded as project context. Plugins contribute
> context through skills, agents, and hooks.

So the plugin ships all three mechanisms it actually needs:

| Component | Fires | Purpose |
| --- | --- | --- |
| `SessionStart` hook | once per session | injects the full rules |
| `UserPromptSubmit` hook | every turn | one-line reminder, survives compaction |
| `be-honest` skill | on demand | `/no-hallucinations:be-honest` |

Both hooks and the skill read from the *same* `SKILL.md`: `scripts/inject-rules.sh` strips the
YAML frontmatter and prints the body, so the two can never drift apart. No `jq`, no runtime
dependencies — a `SessionStart` hook that exits 0 has its plain stdout added to the context.

### Honest caveats

- A hook injects text as **conversation context**; a global `CLAUDE.md` goes into the system
  instructions. The docs don't state that these two carry equal weight, and I haven't measured
  it — assume `CLAUDE.md` is somewhat stronger. That's why the per-turn reminder exists.
- Auto-compaction can drop older context. The `UserPromptSubmit` line is the insurance.
- If you're migrating off a global `CLAUDE.md`, keep both for a few days before deleting the
  original.

## Layout

```text
.claude-plugin/marketplace.json          # the catalog
plugins/no-hallucinations/
├── .claude-plugin/plugin.json           # manifest
├── hooks/hooks.json                     # SessionStart + UserPromptSubmit
├── scripts/inject-rules.sh              # strips frontmatter, prints the rules
└── skills/be-honest/SKILL.md            # single source of truth
example-project/                         # per-project install example
```

## Develop

```bash
git clone git@github.com:agenticDraft/plugins.git
cd plugins

# validate the manifest (--strict turns unknown-field warnings into errors)
claude plugin validate ./plugins/no-hallucinations --strict

# check what the hook will inject
CLAUDE_PLUGIN_ROOT="$PWD/plugins/no-hallucinations" \
  sh plugins/no-hallucinations/scripts/inject-rules.sh

# install from the local checkout
/plugin marketplace add ./
/plugin install no-hallucinations@agenticdraft
```

Use `claude --debug` to confirm the hook fired and see its output.

## License

MIT — see [LICENSE](LICENSE).
