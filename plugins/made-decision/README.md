# made-decision

A Claude Code plugin that runs a structured, six-step interview to help you think through a
decision — the **OOCEMR** framework: Outcomes, Options, Consequences, Evaluate, Mitigate,
Resolve. Instead of a quick opinion, it asks one question at a time, pushes back when an
answer is too thin, and only gives its own analysis at the end — including telling you
directly if that analysis doesn't support the option you picked.

## Install

```bash
/plugin marketplace add agenticDraft/plugins
/plugin install made-decision@agenticdraft
```

## Use

```text
/made-decision:decision-making <describe your dilemma>
```

Or just describe a dilemma in conversation ("should I take this job offer...", "choosing
between two apartments") — the skill can trigger automatically without the explicit command.

## Model recommendation

**Sonnet** is the default and handles most of the interview well. Running the six steps is
mostly disciplined instruction-following — one question per turn, step markers, catching
thin or vague answers — not deep reasoning.

Consider switching to **Opus** for higher-stakes decisions (career changes, large purchases,
irreversible commitments). The final RESOLVE summary is the hardest part of the flow: it has
to cross-reference all six steps, spot contradictions between them, and give an honest
verdict even when it disagrees with the choice you made. That's where Opus's extra reasoning
depth helps most.

**Caveat — how to actually get Opus for this**: this skill deliberately does **not** set
`model:` in its frontmatter. That field only pins the model for the turn that invokes the
skill; the session model resumes on your very next message. Since this interview runs across
dozens of turns, a frontmatter override wouldn't cover the conversation — it would only
affect the first question. If you want Opus for the whole interview, select it yourself with
`/model` *before* starting, so it persists for the session.

This recommendation follows from the shape of the task (structured protocol vs. open-ended
synthesis at the end), not a measured Opus-vs-Sonnet comparison on this specific skill — that
hasn't been benchmarked.

## Layout

```text
plugins/made-decision/
├── .claude-plugin/plugin.json           # manifest
├── skills/decision-making/SKILL.md      # the OOCEMR interview
└── evals/evals.json                     # scripted test scenarios
```

## License

MIT — see [LICENSE](../../LICENSE).
