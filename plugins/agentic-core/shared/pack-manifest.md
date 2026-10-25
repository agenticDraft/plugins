---
description: The pack manifest schema — platform and provider shapes, the stage condition grammar, and the route digraph a platform pack ships. Every reader of a pack.yaml validates against this file rather than restating the shape inline.
---

# Pack manifest

A pack declares itself with `pack.yaml` at its own root, alongside its `skills/` directory. There
are two kinds, each with its own fixed shape.

## Location

`pack.yaml` at the root of the pack. Skills it names resolve to
`<pack root>/skills/<skill name>/SKILL.md`. A platform pack also ships `route.dot` at that same root.

## Format — platform pack

```yaml
kind: platform
stages:
  - id: <stage id>              # one of the fifteen below
    skill: <skill name>
    when:                       # optional; omit entirely for an always-on stage
      - { <fact field>: <value>, … }
      - { <fact field>: <value>, … }
    fix_attempts: <int>         # optional
always_autonomous: [<stage id>, …]
readiness_criteria:
  <item_type>:
    require: [<fact field>, …]
artifacts:
  - id: <artifact id>
    produced_by: <stage id>
    path: "<relative path>"
onboarding_state_path: "<relative path>"   # optional
audit_findings_path: "<relative path>"     # optional
audit_digest_path: "<relative path>"       # optional
authoring_examples_path: "<relative path>" # optional; a directory, relative to the pack root
branch_name:                               # optional
  pattern: "<expression>"
requires:                                  # optional; see Declarations — either kind
  - tool: <identifier>
    probe: [<argv>, …]
    remedy: "<what a human runs to fix it>"
env:                                       # optional
  - name: <VARIABLE_NAME>
    source: "<where a human gets the value>"
hosts: ["<host>", "*.<domain>", …]         # optional
ignore_paths: ["<relative path>", …]       # optional
credential_checks:                         # optional
  - check: <identifier>
    probe: [<argv>, …]
    proves: "<what a pass shows, and what it does not>"
    remedy: "<what a human does to fix it>"
config_derivation: "<relative path>"       # optional; a script, relative to the pack root
reference_docs: "<https url>"              # optional; last
```

## Format — provider pack

```yaml
kind: provider
role: tracker | scm | design | browser
operations:
  <operation name>: <skill name>
  …
unsupported: [<operation name>, …]
scripts:                        # optional
  <operation name>: "<path, relative to the pack root>"
text_conventions:               # tracker role only
  design_keywords: [<string>, …]
  before_state_keywords: [<string>, …]
  reproduction_headings: [<string>, …]
  acceptance_criteria_headings: [<string>, …]
requires:                       # optional
  - tool: <identifier>
    probe: [<argv>, …]
    remedy: "<what a human runs to fix it>"
env:                            # optional
  - name: <VARIABLE_NAME>
    source: "<where a human gets the value>"
hosts: ["<host>", "*.<domain>", …]   # optional
ignore_paths: ["<relative path>", …] # optional
credential_checks:              # optional
  - check: <identifier>
    probe: [<argv>, …]
    proves: "<what a pass shows, and what it does not>"
    remedy: "<what a human does to fix it>"
session_tools:                  # optional; last
  - tool: <exact tool name>
    remedy: "<what a human does to fix it>"
```

## Top-level keys

Fixed per kind, in order.

- **platform** — `kind`, `stages`, `always_autonomous`, `readiness_criteria`, `artifacts`. All
  required; `always_autonomous` and `artifacts` may be empty (`[]`) but must be present, the same way
  an empty `artifacts` list is present on every result envelope rather than omitted.
  `onboarding_state_path`, `audit_findings_path` (D80) and `audit_digest_path` (G500) are the
  exceptions to "all required" — all three optional, and a pack may declare any subset of them,
  including none. So is `authoring_examples_path` (D132), which follows them. After `branch_name`
  come the five optional declarations `requires`, `env`, `hosts`, `ignore_paths`,
  `credential_checks`, then the optional `config_derivation`, then `reference_docs` last.
- **provider** — `kind`, `role`, `operations`, `unsupported`, `scripts`, `text_conventions` for
  the `tracker` role, `requires`, `env`, `hosts`, `ignore_paths`, `credential_checks`,
  `session_tools`. The first four are
  required; `unsupported` may be empty (`[]`) but must be present. Every key after `unsupported` is
  optional.

## The stage vocabulary

**Fifteen ids, fixed. The core defines every one.** A pack implements an id or declines it; no pack
may add one, and adding one is a version bump on this contract. In the order a full route runs them:

`intake`, `readiness`, `extract`, `conventions`, `serve`, `baseline`, `prototype`, `verify-design`,
`plan`, `plan-gate`, `implement`, `verify`, `lint`, `publish-gate`, `deliver`.

A pack that needs behaviour no id covers implements it inside a stage it already owns. There is no
open class.

## Field rules — platform

- `stages` — an ordered **list**, one entry per stage, each with an `id` from the fifteen and a
  `skill`. Order is execution order. A stage id appears at most once.
- The list **begins with `intake` and ends with `deliver`**, and neither carries a `when:`. A route
  that skipped `intake` would have no fact record to filter itself with, and one that skipped
  `deliver` could never reach a delivered terminal state.
- `when` — optional per stage. Omit it entirely for a stage that always runs; the key present but
  empty is a contract violation, not an always-on stage. Semantics below.
- `fix_attempts` — optional per stage, a positive integer overriding the configured default. It
  counts **edits**, not checks: `N` allows up to N edits and N+1 checks (`fix-loop.md`). The
  component that drives a route never applies it: every retry loop is internal to the stage that
  owns it, and asks `check-fix-budget.sh` rather than counting. **Declare it only on a stage whose
  skill asks `check-fix-budget.sh`.** `check-fix-budget-readers.sh` fails on a stage that declares it
  while its `skills/<skill>/SKILL.md` never invokes that script; a stage that invokes it without
  declaring a value reads the configured default. A poll ladder, retry count or timeout is not a
  budget of edits: it stays in the script beside the operation it bounds.
- `always_autonomous` — every entry must be a stage id present in `stages`. A `question` from such a
  stage is treated as a failure in both execution modes.
- `readiness_criteria` — keyed by `item_type`, each with a `require` list of fact-record fields.
  **At least one `item_type` must be declared**, and every field required must be a real fact-record
  field (`fact-record.md`). A pack declaring none would fail every item it was given; a criterion
  naming a field the record does not carry could never be satisfied.
- `artifacts` — every entry's `produced_by` must be a stage id present in `stages`. `id` names the
  artifact; `path` is the relative path it is written to.
- `onboarding_state_path`, `audit_findings_path` (D80), `audit_digest_path` (G500) — all three
  optional. When present, each must be a
  non-empty, quoted, relative path: no leading `/`, and no `..` path segment. This validator checks
  only that the string is a well-formed relative path — never that it exists in any project's
  working tree, since a pack has no fixed project to check against. A declared path is read at
  runtime by pre-flight's third check (`pre-flight.md`), never by anything in this validator.
- `audit_digest_path` (G500) — the file the platform pack's own audit writes recording what each
  file it judged hashed to when it judged it: one `<sha256>  <relative path>` line per file. The
  core never learns what any listed path is for; it re-hashes the paths the digest itself names,
  which is how a freshness check stays platform-neutral (D28). Declared here, read only at runtime.
- `authoring_examples_path` (D132) — optional, platform packs only. A directory **relative to the
  pack root** (not the project root) holding the work-item authoring examples the core's authoring
  skill reads from the configured platform pack. Checked exactly as the three paths above: a
  non-empty, double-quoted, relative path with no `..` segment. The core never learns what the
  directory holds, so the validator does not open it or test that it exists. A pack that declares
  none leaves the authoring skill with its neutral templates only. A provider manifest carrying it
  is invalid. Two names inside the directory are fixed here, never their content:
  `component-path.txt` — optional, one regular expression per line, each matching a component path
  written without the trailing slash the platform's intake needs to record it; and any `*.md` file —
  a worked work-item draft the authoring skill shows as the platform's example.
- `branch_name` (D544, D129) — optional. It declares the character rule a branch name must meet on
  this platform: `pattern`, a double-quoted extended regular expression the whole name must match,
  so anchor it. The length limit is not the pack's: it depends on the project, so it lives in the
  project config's `branch_name.max_length` (`project-config.md`), and a `max_length` here is
  invalid. `lib/check-branch-name.sh <branch>` reads the pattern from the configured platform pack
  and the limit from the project config, and answers `ok`, `too-long` or `bad-chars`. The core plugin's hook runs that check on every
  branch-creating command an agent issues and blocks the command when the name fails. A pack that
  declares nothing is unconstrained.
- `config_derivation` (D138) — optional, platform packs only. A double-quoted path, relative to the
  pack root, of a script that derives this project's own config values from its repository remote.
  The core's `setup` runs it once as `<script> --remote <remote URL>` through
  `lib/derive-project-values.sh`; every line it prints must be `branch_name.max_length=<positive int>`
  or `platform.<snake_case key>=<value>`, or the whole output is refused. `setup` writes the lines
  into the project config (`project-config.md`) and never asks the human for them. What is derived,
  and how, is the pack's; the core learns neither. Checked as a `scripts:` path is: relative, no `..`
  segment, the file exists (validator 27). A pack that declares none leaves those keys to a hand
  edit.
- `reference_docs` (D117) — optional, the last platform key: one double-quoted `https` URL, the
  platform's official reference. Every stage that writes code, and the item-authoring skill, read it
  before deciding a question no project rule answers, and cite what they read
  (`official-reference.md`). A pack that declares none has no reference to consult; nothing
  substitutes a search.
- Every skill named in `stages` must resolve to `<pack root>/skills/<skill name>/SKILL.md`. A skill
  name with no matching directory is a **dangling skill reference**.
- Every skill named in `stages` must declare isolated execution in its own frontmatter — the literal
  key is `context: fork`. Every stage runs as an isolated subagent; a skill that omits the
  declaration still resolves and still returns a valid envelope, so nothing about a run visibly
  fails — what fails silently is the cost model, because that stage's context then accumulates in
  whichever component drives the route instead of dying with the stage. This applies only to a
  platform pack's stage skills, never to a provider pack's operation skills.

## Condition semantics

- **A stage with no `when:` always runs.**
- **`when:` is a list of blocks. Any block matching runs the stage** — blocks are alternatives.
- **Within one block every key must match.** Absent keys are not tested.
- **Keys name fact-record fields only** (`fact-record.md`). Nothing else is addressable: not the
  environment, not a previous stage's output, not the clock. Environment questions — is a tool
  installed, is an operation supported — are answered once before the first stage, never inside a
  condition, because a condition that could probe a machine would make a run's shape depend on the
  machine it ran on.
- **A value must match its field's kind**, which is what lets a condition be checked before a run
  rather than discovered during one:
  - a **list** field — `labels`, `components`, `files_named` — compares against `present` or
    `empty`, and nothing else. An absent list and an empty one are the same thing to a reader of
    the fact record, so both are `empty`.
  - a **boolean** field — `design_source`, `design_mentioned`, every `has_*` — compares against
    `true` or `false`.
  - a **string** field compares against a literal, for equality.

  A field the record does not carry, or carries as `null`, matches nothing except a list's `empty`:
  it was never determined, and guessing is exactly what the fact record forbids.
- **A skipped stage is recorded `skipped`**, along with the condition that skipped it, and control
  passes to the next stage in list order. Skipping is visible, which a list that simply never
  contained the stage was not.

The list form exists because a single all-keys-must-match block cannot express a stage that must run
when a reference is present *or* when the text asked for one:

```yaml
- id: extract
  skill: extract
  when:
    - { design_source: true }
    - { design_mentioned: true }
```

A stage gated on a list field names the kind of test it wants rather than a value:

```yaml
- id: baseline
  skill: baseline
  when:
    - { components: present }
```

**Conditions are evaluated once**, against the fact record, as soon as that record exists. The record
is written once and never rewritten, so a stage's skip state cannot change mid-run.

### Canonical rendering

One `when:` has exactly one string form, so that comparing a condition is string equality rather
than judgment. Blocks joined by ` OR ` in list order; keys within a block joined by ` AND ` in
fact-record field order; each key rendered `<field>=<value>`, unquoted, single-spaced. The example
above renders:

```
design_source=true OR design_mentioned=true
```

This is the form recorded against a skipped stage, and the form the route digraph's edge labels carry.

## The route digraph

A platform pack ships **`route.dot` at its root**: the stage list drawn as a graph, checked against
the manifest so the picture cannot drift from the contract.

```dot
digraph route {
    "intake"    [shape=box];
    "extract"   [shape=box, style=dashed];
    "implement" [shape=box];
    "deliver"   [shape=box];

    "intake"    -> "extract"   [label="design_source=true OR design_mentioned=true"];
    "extract"   -> "implement";
    "implement" -> "deliver";
}
```

- **Nodes are stage ids and nothing else.** Every node name is exactly an id from `stages`, and every
  id has a node — a bijection. No decoration, no gate suffix, and no pre-flight, decision or terminal
  nodes: admitting those would require a marker to exclude them, and a bijection needs none.
- **A conditional stage's node is `style=dashed`**; an always-on stage's node is not. Both directions
  are checked.
- **A conditional stage's incoming edge carries `label="<canonical rendering of its `when:`>"`**,
  compared by string equality. A label differing by one character is a failure, and the failure names
  both strings.
- **Edges follow list order, and there are no bypass edges.** This is a filtered list, not a
  branching graph: a skipped stage hands control to the next stage in order, which needs no edge of
  its own.

## Anti-patterns

- `stages` written as a mapping of id to skill rather than an ordered list.
- A stage id outside the fifteen, or one appearing twice.
- `intake` or `deliver` carrying a `when:`, or the list beginning or ending with anything else.
- A `when:` key naming anything but a fact-record field — it can never match, and would silently
  disable its stage forever.
- A `when:` present but empty. Omit the key instead.
- A condition testing the environment, the clock, or a previous stage's output.
- `readiness_criteria` absent, empty, or requiring a field the fact record does not carry.
- `always_autonomous` or an artifact's `produced_by` naming a stage id absent from `stages`.
- A stage announcing its own skip from inside its result envelope. A condition is declared by the
  pack and evaluated from the fact record; `next_action` is a name, not a directive.
- `route.dot` absent, carrying a node that is not a stage id, missing a node for a declared stage,
  marking an always-on stage dashed (or leaving a conditional one undashed), or carrying an edge
  label that does not match its stage's `when:` exactly.
- `operations` or `unsupported` naming an operation outside the declared role's set; an operation in
  both; a role operation in neither.
- A skill name with no `<pack root>/skills/<skill name>/SKILL.md` on disk.
- `fix_attempts` on a stage whose skill never invokes `check-fix-budget.sh`, or used to describe
  anything but a budget of edits.
- A provider operation writing an artifact to a name an earlier call already returned.
- `scripts` naming an operation absent from `operations`, or a path that does not resolve to a real
  file under the pack root.
- `scripts` present but empty. Omit the key instead.
- `session_tools` present but empty, on a platform pack, with an entry whose `tool` is empty, a
  pattern, or declared twice, or whose `remedy` is missing or empty.
- A stage skill's frontmatter omitting `context: fork`.
- A top-level key outside the fixed set for the manifest's `kind`, or a required key missing.
- `onboarding_state_path`, `audit_findings_path` or `audit_digest_path` present but empty, absolute
  (a leading `/`), or containing a `..` path segment.
- `authoring_examples_path` that is not a double-quoted string, is empty, absolute or contains a `..`
  path segment, comes after `evidence_manifest`, or appears on a provider manifest.
- `branch_name` with no `pattern`, with a `max_length` (the project config's, not the pack's), or
  with an unquoted, empty or non-compiling `pattern`.
- `config_derivation` that is not double-quoted, is empty, absolute or contains a `..` segment, names
  a file that does not exist, comes before `ignore_paths` or after `reference_docs`, or appears on a
  provider manifest.
- `credential_checks` present but empty, out of the fixed order, with a `check` that is not an
  identifier or is declared twice, a `probe` given as a string, empty, or naming a `<pack>/` file that
  does not exist, or a `proves` or `remedy` missing or empty (validator 28).
- `reference_docs` that is not one double-quoted `https` URL, or any key after it.
- Any file under the pack root containing the literal sequence `{{`, the reserved marker for an
  unfilled template placeholder. A generated pack that still carries one is a failed setup, not a
  pack with a hole in it.

## Field rules — provider

- `role` — exactly one of the four core roles. Each has a fixed set of operation names it must
  account for:
  - `tracker` — `fetch_item`, `post_note`, `attach_file`, `list_types`
  - `scm` — `create_branch`, `publish_change`, `check_status`
  - `design` — `fetch_reference`
  - `browser` — `render`, `capture`, `measure`, `interact`
- `operations` — a mapping of operation name to skill name. Every key must be an operation that role
  actually has.
- `unsupported` — operation names this pack declines to implement. Every entry must be an operation
  that role has, and must not also be a key of `operations`.
- **Completeness.** Every operation the declared role has must appear in one of the two. One in
  neither is silently missing — the runner would only discover it mid-run.
- **An operation that writes an artifact writes a new file on every call.** It never replaces a file
  an earlier call named in its envelope's `artifacts:`. The operation chooses a name no earlier call
  used; the caller takes the path from `artifacts:` and never predicts, renames or copies it.
- `scripts` — optional. A mapping of operation name to a path, relative to the pack root, of a
  directly-executable script implementing that same operation for a caller that must run it as a
  subprocess rather than through `Skill()` — most operations are only ever invoked the latter way, so
  a provider with no such caller declares nothing here. Every key must also be a key of `operations`
  (naming a script for an operation this pack does not implement is meaningless), and every path must
  resolve to a real file under the pack root, the same way an `operations:` skill name must resolve.
  A caller that needs an operation's script form and finds `scripts` silent about it degrades rather
  than guessing one — this is never inferred from a skill's own prose.
- `text_conventions` — `tracker` role only. Describes how one tracker's items are written: the word
  lists that set `design_mentioned` (`design_keywords`) and `before_state_mentioned`
  (`before_state_keywords`), and the heading names that set
  `has_reproduction_steps` (`reproduction_headings`) and `has_acceptance_criteria`
  (`acceptance_criteria_headings`). It lives with the tracker because a team that formats items
  differently changes its tracker pack, not its platform pack. `has_reproduction_url` needs no list
  here — any `http(s)` URL in the sanitized text sets it.
- `requires` — optional, on either kind (see **Declarations — either kind**). What this pack needs
  present on the machine that runs it: a tool, a downloaded binary, anything selecting the pack does
  not by itself provide. Each entry declares three things.
  - `tool` — a non-empty identifier for what must be present. It names the thing, and it is what a
    report says is missing.
  - `probe` — how "present" is answered, as a **list of arguments, never a string**. An argument may
    carry the literal prefix `<pack>/`, which resolves against the pack root — the way a pack whose
    "is it present" question needs real logic (a fallback search path, a second artifact the first
    one says nothing about) ships that logic as its own script instead of asking the core to guess
    on its behalf. The prefix is required for that: a bare relative path would resolve against
    whatever directory the caller happened to run from. Such a path is checked exactly as a
    `scripts:` path is — no `..` segment, and the file must exist — because a probe pointing at a
    file that is not there is a check that will never run, and a check that never runs must not look
    like one that passed. A string would
    have to reach a shell to be run, and a shell is the one thing a precondition check must not
    need. Only the exit status is read: zero means present. The output is never parsed and a version
    is never compared — a version requirement is a second question this key deliberately cannot ask,
    because answering it would mean parsing whatever the tool happened to print.
  - `remedy` — what a human runs to fix it. It is quoted text, printed verbatim by whatever reports
    the tool missing, and **nothing ever executes it**. A pack that could install its own dependency
    would be a pack that changes the machine it was merely asked to run on.
  - **Absent means ungated**, the same rule an undeclared `unsupported:` list already follows. A
    pack that declares no `requires` has no local precondition; silence is never read as a hidden
    one.
  - **Declaring this gates nothing at load time.** Two readers consult it — a read-only diagnostic,
    on demand, and the operation itself before it acts — and both quote the declared `remedy` rather
    than composing their own. The capability check that runs before a route starts reads manifests
    only and never probes a machine, so a missing tool is reported, never guessed at, and never
    discovered by a route that already created a branch.
- `session_tools` — optional, the last provider key. The tools this pack's operations call that only
  the session running the route can provide — a tool a plugin or a server registers in the session,
  which no script on the machine can see. Each entry declares two things.
  - `tool` — the exact name the session registers the tool under: letters, digits, `_` and `-`
    only, never a pattern. Each name at most once.
  - `remedy` — what a human does to make the tool present. Quoted text, printed verbatim by whatever
    reports the tool missing, and never executed.
  - **Absent means ungated**, as for `requires`.
  - **One reader decides, at run time.** The component that drives a route checks every declared
    tool of every pack whose role the run will use, once the fact record exists and before any
    branch, run state or outbound write exists, by asking the session's own tool registry; a missing
    tool ends the run `blocked` with its `remedy`. The comparison of names declared against names
    found is `lib/check-session-tools.sh`'s, never the driver's. The read-only diagnostic lists the
    declared tools and says they are checked at run time, since it cannot see the registry either.
    Pre-flight does not read this key.
- Every skill named in `operations` must resolve to `<pack root>/skills/<skill name>/SKILL.md`.

## Declarations — either kind

Five optional keys say what a project must provide for a pack, in this fixed order: `requires`,
`env`, `hosts`, `ignore_paths`, `credential_checks`. A platform pack declares them after
`branch_name` and before `config_derivation`; a provider pack after `text_conventions` and before
`session_tools`. Each is absent when the pack needs nothing of its kind, never present and empty.

- `requires` — as under **Field rules — provider**, with the same shape and the same readers on a
  platform pack.
- `env` — the environment variables this pack's operations read. Each entry declares two things, an
  optional third, and nothing else:
  - `name` — the variable's name, unquoted: upper-case letters, digits and `_`, starting with a
    letter. Anything else in that place is refused, and the refusal never repeats what was written,
    because a value written where a name belongs may be a credential.
  - `source` — quoted text telling a human where to get the value.
  - `login_alternative` — optional, after `source`: quoted text naming a login that replaces the
    variable. Declare it when the pack's tool prefers the variable to a login, so any value in it —
    a placeholder included — overrides the login. `setup` writes no key for such a variable and
    names the two as alternatives.
  - **A value is never declared** — no default, no example value. The value lives only where the
    human puts it; a pack never reads, writes or creates the file that holds it. The core's `setup`
    creates each declared name there as a placeholder for the human to fill, unless it declares a
    `login_alternative`.
  - **Only the owning pack declares a variable.** A variable another pack's code also reads is
    declared once, by the pack whose credential it is. Each name at most once per pack.
- `hosts` — the network hosts this pack's operations reach, as a bracket list of double-quoted
  entries, each a literal host name or `*.<domain>`: lower case, at least one dot, no scheme, port or
  path — the form a sandbox network allowlist takes. A host that is a variable's value, different in
  every project, is declared by its wildcard. Each host at most once.
- `ignore_paths` — the project-relative paths this pack's operations write that must never be
  committed, as a bracket list of double-quoted entries; a directory ends in `/`. No leading `/`, no
  `..` segment, no glob character, backslash or space: what the ignore file hides and what delivery
  excludes must be the same literal path. Each path at most once.
- `credential_checks` — how this pack proves that the credential its operations use reaches what
  they need. Each entry declares exactly four things, in this order:
  - `check` — an identifier: lower-case letters, digits and `-`, starting with a letter; each at most
    once.
  - `probe` — argv, never a string, judged by exit status alone: `0` passes. An argument prefixed
    `<pack>/` names a file the pack ships, resolved against the pack root, and must exist. Its output
    is discarded, so nothing it prints reaches a report. It runs in the project's checkout.
  - `proves` — quoted text saying what a pass shows **and what it does not**. A report prints it on a
    pass in place of "works", because a check that reaches a service rarely proves every permission
    a run will use.
  - `remedy` — quoted text for a human, printed on a failure; never executed.
  A probe may reach the network, so pre-flight never runs one. `lib/check-credentials.sh` does, for
  two readers: `health`, on demand, and the route driver, after pre-flight passes and before
  `intake`, ending the run `blocked` with the remedy on a failure. A pack that declares none is
  reported as unproven, never as passing.

**Who checks them before a run.** `lib/check-pack-environment.sh` reads `env` and `hosts` for the
packs it is given: each variable set in the process environment and not a `FILL-IN:` placeholder —
never printed, and reported as present, never as working; a variable with `login_alternative` may
be unset or empty, since the login stands in, but a placeholder in it fails, because it breaks the
login; each host in the committed settings' `sandbox.network.allowedDomains` — a literal host is met
by itself or by a `*.<domain>` entry it ends in, a `*.<domain>` only by that same entry. Offline.
Pre-flight (check 5) and `health` both run it.

**The core's own paths** are not a manifest key. `run-paths.txt` lists them, one per line:
`ignore <path>` for a file a run writes and never commits, `commit <path>` for a project file
committed on purpose; the credentials file `setup` creates is among the `ignore` lines. The two lists
together — the core's and every configured pack's `ignore_paths` — are everything a project ignores
for a run.

**Who reads them in `setup`.** `lib/collect-pack-declarations.sh` reads these keys from the packs the
project config names, and `run-paths.txt`; `lib/write-credential-placeholders.sh`,
`lib/write-sandbox-hosts.sh` and `lib/write-ignore-rules.sh` each merge one kind into the project,
add only; `lib/name-files-to-commit.sh` names what the human commits.

## Example — platform

```yaml
kind: platform
stages:
  - id: intake
    skill: intake
  - id: extract
    skill: extract
    when:
      - { design_source: true }
      - { design_mentioned: true }
  - id: lint
    skill: lint
    fix_attempts: 3             # its skill asks check-fix-budget.sh
  - id: deliver
    skill: deliver
always_autonomous: [deliver]
readiness_criteria:
  task:
    require: [has_description, has_acceptance_criteria]
artifacts:
  - id: fact-record
    produced_by: intake
    path: ".ai/run-context/fact-record.yaml"
```

## Example — provider

```yaml
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: []
```

A `browser`-role provider that also has a script-level caller declares `scripts` for the operation
that caller needs:

```yaml
kind: provider
role: browser
operations:
  render: render
  capture: capture
  measure: measure
  interact: interact
unsupported: []
scripts:
  render: "skills/render/scripts/render.cjs"
```

A provider whose operations call a remote service with a token declares the variables, the host and
the directory its operations write:

```yaml
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: []
env:
  - name: EXAMPLE_SITE
    source: "the host name of your example site"
  - name: EXAMPLE_API_TOKEN
    source: "your example account's settings, API tokens"
hosts: ["*.example.test"]
ignore_paths: [".ai/tracker/"]
```

## Reference, not restatement

A skill or script that reads a pack manifest references this file with one line rather than
restating the shape inline, the same convention `project-config.md` and `result-envelope.md` use
for their own contracts.

## Fixtures

`fixtures/pack-manifest/platform-valid/` (always-on stages only) and
`fixtures/pack-manifest/platform-valid-conditions/` (the same pack with a conditional stage, its
`route.dot` carrying the dashed node and the matching edge label) are well-formed platform examples;
`fixtures/pack-manifest/provider-valid/` is the provider one. Each is a small pack root with a
matching `skills/` directory.

`fixtures/pack-manifest/platform-valid-onboarding/` is `platform-valid` with all three of
`onboarding_state_path`, `audit_findings_path` and `audit_digest_path` declared — proof the optional
keys coexist with an otherwise-conformant manifest, and in that order.
`fixtures/pack-manifest/platform-valid-authoring-examples/` is that fixture with
`authoring_examples_path` added after them.

`fixtures/pack-manifest/platform-invalid/` holds one directory per rejection case:
`unknown-stage-always-autonomous`, `unknown-stage-artifact-producer`, `dangling-skill`,
`stage-not-isolated`, `unfilled-placeholder`, `stage-id-not-in-vocabulary`, `when-unknown-field`,
`no-readiness-criteria`, `readiness-criteria-unknown-field`, `digraph-node-not-a-stage`,
`digraph-missing-node`, `digraph-label-mismatch`, `onboarding-path-absolute`,
`onboarding-path-traversal`, `onboarding-path-empty`, `authoring-examples-path-absolute`,
`authoring-examples-path-traversal` and `authoring-examples-path-not-string`.
`fixtures/pack-manifest/provider-invalid/` holds `missing-operation`, `unknown-operation`,
`dangling-skill`, `authoring-examples-path` and `env-value-as-name` (a token-shaped value where a
variable name belongs). `scripts`'s own rejection cases (unknown operation, dangling script,
present-but-empty) and those of `env`, `hosts`, `ignore_paths` and `config_derivation` are inline in the validator's test
suite, alongside the remaining shape errors that fit a single block.

`fixtures/session-tools/` holds the session-tools comparison's inputs: `one-tool`, `two-tools` (after a
`requires:` block, which the comparison never reads), `none-declared`, and `no-remedy` (malformed).

## Verification

`lib/validate-pack-manifest.sh <path-to-pack.yaml>` is the deterministic checker — no model
involved. It exits `0` and prints `valid: <kind>` for a conformant manifest, `1` with
`invalid: <reason>` on stderr for a contract violation, `2` for a usage error.

`lib/evaluate-stage-conditions.sh <path-to-pack.yaml> <path-to-fact-record.yaml>` evaluates every
stage's `when:` against a fact record and prints, in list order, one `run: <stage id>` or
`skipped: <stage id> — <canonical rendering>` line per stage. Also deterministic, also no model.

`lib/check-session-tools.sh --list <pack.yaml>…` prints the declared session tools to ask the
registry for (`tool: <name>`, each once) or `none declared`; `lib/check-session-tools.sh <pack.yaml>…
--found <name>…` exits `0` with `ok: <tool>` per declared tool found, `1` with `missing: <tool> —
<remedy>` per one not found, `2` for a usage error or a malformed block. Exact names only.

```bash
bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
bash plugins/agentic-core/shared/lib/evaluate-stage-conditions.test.sh
bash plugins/agentic-core/shared/lib/check-session-tools.test.sh
bash plugins/agentic-core/shared/lib/check-requires.test.sh
bash plugins/agentic-core/shared/lib/run-paths.test.sh
bash plugins/agentic-core/shared/lib/collect-pack-declarations.test.sh
bash plugins/agentic-core/shared/lib/write-credential-placeholders.test.sh
bash plugins/agentic-core/shared/lib/write-sandbox-hosts.test.sh
bash plugins/agentic-core/shared/lib/write-ignore-rules.test.sh
bash plugins/agentic-core/shared/lib/name-files-to-commit.test.sh
bash plugins/agentic-core/shared/lib/setup-project-files.test.sh
bash plugins/agentic-core/shared/lib/resolve-configured-packs.test.sh
bash plugins/agentic-core/shared/lib/check-pack-environment.test.sh
bash plugins/agentic-core/shared/lib/check-credentials.test.sh
```
