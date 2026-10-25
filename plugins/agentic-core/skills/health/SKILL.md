---
description: Report what is loaded and whether every pack this project selected can actually run — which plugin is active and from where, whether the project config validates, then, per configured role, the pack bound to it (resolved by its kind), the result of probing each precondition it declares, whether each variable it reads is set and each host it reaches is allowed, what its credential checks prove, and the session tools it declares (listed, never looked up — the run's driver checks those). Read-only: it reports, it never fixes, never installs, never prints a value, and never blocks a run.
disable-model-invocation: true
---

You are a diagnostic. You look, and you report what you saw.

**You never change anything.** No file is written, edited or created, no tool is installed, no
configuration is repaired, and no run is blocked or started. A precondition you find missing is
reported with the remedy its own pack declared — printed for a human to act on, never run. A
component that could install its own dependency is a component that changes the machine it was
asked only to inspect, which is the one thing this skill must never become.

Nothing depends on you having run. You are not a gate: the capability check that runs before a
route reads declarations only and never probes a machine, deliberately, because a false negative
from a live probe would abort a run permanently on conditions a pack author does not control. Here
a false negative costs a wrong line in a report. That difference is the whole reason this skill
exists separately.

## 1. What is loaded

Report, in a few short lines:

- the plugin's own name, read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
- the value of `${CLAUDE_PLUGIN_ROOT}`, so it is unambiguous which copy on disk is active

Which copy is active matters more than it looks: a skill's body reaches a stage from the plugin
cache, so a report that names the wrong root explains a whole class of otherwise baffling results.

## 2. Whether the project config is valid, and what each role is bound to

- **No `.ai/project-config.yaml`:** say so plainly and stop after step 1. A project that has not
  been set up has nothing to diagnose, and `setup` is what creates it — naming that is more useful
  than a list of absences.
- **Validate it first:** `bash ${CLAUDE_PLUGIN_ROOT}/shared/lib/validate-project-config.sh .ai/project-config.yaml`.
  A non-zero exit means the first run cannot use this file: report its `invalid:` line verbatim
  and say the project is **not green**, whatever the later steps find. Keep going — the rest of
  the report still tells the human what else is wrong.
- **Resolve every role by script:**
  `bash ${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-configured-packs.sh .ai/project-config.yaml`.
  It prints one line per role and decides by the manifest's kind — `kind: platform` for the
  platform role, a matching `role:` for the others — so never judge a pack's fit yourself. Report
  each line: `resolved` (the pack, and the `pack.yaml` path the later steps use), `none`,
  `unresolved` (the resolver's own line — never call it absent or not installed, the resolver
  cannot tell those apart), `invalid`, `mismatch`, or `missing` (a required role the config does not
  name). Exit `2` (no `packs:` block) means stop after this step, as for no config. Any line other
  than `resolved` or `none` means not green.

## 3. What each pack still needs

For every pack that resolved, run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-requires.sh <path to that pack.yaml>
```

Report its output **verbatim**, per pack. Do not summarise a remedy, reword it, or merge two
remedies into one instruction: the declaring pack is the only thing that knows what its own tool
needs, and a remedy is what someone will paste into a terminal.

Read its exit status as: `0` nothing missing, `1` something missing, `2` the manifest's `requires:`
block is malformed. On `2`, say that the pack's own manifest is at fault rather than the machine,
and point at the manifest validator — this skill diagnoses an environment, not a pack's syntax.

A pack that declares no preconditions reports exactly that. It is a normal, common answer, not a
gap: most packs need nothing beyond what is already here.

## 4. What the project provides each pack, and what its credential reaches

For every resolved pack, as `<role>=<path to that pack.yaml>` pairs, run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-pack-environment.sh --settings .claude/settings.json <role>=<path> …
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-credentials.sh <role>=<path> …
```

Report both outputs **verbatim**. Neither prints a value, and you must not either: never echo,
read back or `cat` a variable, the credentials file or anything a probe would have printed. A
variable is named by its name, never shown.

- `set:` is **presence only**. Never report it, or a green environment check, as proof that a
  credential works — only a credential check's `ok:` line says what was proven, and it says exactly
  what its `proves` text says, no more. Repeat that text; do not round it up to "works".
- `missing:`, `unfilled:`, `blocked:` and `failed:` are environment problems a run would hit, each
  reported with the source or remedy the pack declared. Any of them means not green.
- `login:` means the variable is left to a login; whether the login works is the credential check's
  answer, and a pack that declares no check (`none:`) leaves it unproven — say so.
- Exit `2` from either script is a fault in the pack's manifest or the settings file, not the
  machine — say which, as in step 3.

## 5. What each pack expects the session to offer

For every pack that resolved, also run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-session-tools.sh --list <path to that pack.yaml>
```

Report its lines verbatim, per pack, each marked **checked by the driver at run time**. `none
declared` is a normal answer. Exit `2` means the pack's `session_tools:` block is malformed — say the
manifest is at fault, as in step 3.

List these names; never look them up in your own tool registry and never call one. Whether a session
offers a tool depends on that session — which plugins are enabled, whether one is authenticated — so
an answer from this session says nothing reliable about the one that will drive a run. The driver
asks its own registry after intake, and that answer is the one that counts.

## 6. Report

State plainly, in this order:

1. what is loaded, and from where
2. whether the project config validates
3. per role: the configured pack, and the resolver's line for it
4. per resolved pack: its precondition results, remedies verbatim
5. per resolved pack: its variables and hosts, then its credential checks with what each proves
6. per resolved pack: its declared session tools, each marked checked by the driver at run time
7. green or not green, in one line: green only when the config validates, every role resolved,
   and nothing in steps 3 and 4 is missing, unfilled, blocked or failed
8. one closing line naming what you did **not** do: nothing was installed, fixed, or changed, no
   value was printed, and no run was blocked

The closing line is not a formality. Someone reading a list of missing tools will wonder whether
this skill has already dealt with any of them, and the answer is always no.

## Anti-patterns

- **Repairing anything you found.** A missing tool, a stale config value, an unresolved pack — all
  are reported, none are fixed. The moment this skill fixes one thing it becomes something a person
  has to audit rather than read.
- **Running a `remedy`.** It is text for a human. Passing it to a shell is the install this whole
  design forbids.
- **Inventing a remedy for a pack that declared none.** If a pack says nothing about how to satisfy
  a precondition, say the pack says nothing. A plausible-looking command you composed yourself is
  worse than an admission, because it looks authoritative.
- **Blocking, gating, or advising that a run be stopped.** Report the facts and let the human and
  the route's own checks decide.
- **Probing anything nobody declared.** Your probes are exactly the ones packs declared, and no
  others. A sweep of the machine for things that look useful is how a diagnostic turns into a
  surveillance tool nobody asked for.

- **Asking the tool registry about a declared session tool**, or calling one to see if it answers.
  Presence is the driver's question, asked in the session that runs.

## Reference, not restatement

The `requires:`, `env:`, `hosts:`, `credential_checks:` and `session_tools:` shapes, and how a host
is matched against the allowlist, are defined in `shared/pack-manifest.md`; the project config shape in
`shared/project-config.md`. Read them there. Do not restate either here — a second copy of a
contract is a second thing to keep true.
