---
description: scm.publish_change — pushes the current branch and opens (or reuses) a pull request on GitHub, filling the repository's pull request template from the given body when one exists. Requires gh authenticated on this machine (gh auth status).
---

# publish-change

Implements the `scm` role's `publish_change` operation: push the working branch and open a pull
request for review on a real GitHub remote, or report the pull request already open for it. When
the repository has a pull request template, the body follows it.

## Input

Three or four lines in the invocation argument:

```
branch: <branch name>              # must be the currently checked-out branch
title: <pull request title>        # one line
body: <pull request body text>     # may span multiple lines
base: <base branch name>           # optional, defaults to the repository's default branch
```

## What to do

**This script calls `gh`, and the default Bash sandbox's network-filtering proxy does TLS
interception that breaks `gh`'s own Go TLS client — a consistent, every-time failure
(`connect EPERM`-shaped errors or a token reported invalid), not a flaky occasional one; `curl` and
the token itself are unaffected, only `gh`'s own HTTP client (G68).** Run
every step below with `dangerouslyDisableSandbox: true`, unconditionally, on the first attempt.

1. Write the `body` text to a new temporary file, exactly as given, with no shell interpolation of
   its content — this keeps arbitrary body text (quotes, newlines, special characters) out of any
   command line. Call it the composed body.
2. Find the repository's pull request template:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/publish-change/scripts/find-pr-template.sh <repository root>`.
   Exit `3` (`none: …`) — the composed body is the body; go to step 4.
3. Exit `0` (`template: <path>`) — fill it, because the project's reviewers read pull requests in
   that shape and a body that ignores it has to be rewritten by hand. Read the template and write a
   second temporary file:
   - the template's text, in its order, each heading's section filled from what the composed body
     says (the item, the requirements, the verified-locally block, the preview links). Leave out
     the template's instruction lines; they were written for a person filling it in;
   - every placeholder (`<name>`, `{name}`) replaced by its real value from the composed body or
     the repository. A value nothing tells you is never guessed: write `Empty: <why>` in its place
     (an issue number for an item that lives in another tracker, for example);
   - a heading nothing in the composed body answers gets `Empty: <why>` as its content, never a
     blank section;
   - then a line `---`, then the composed body, unchanged, so nothing the caller wrote is lost.

   Check it:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/publish-change/scripts/check-pr-body.sh <template> <filled file> --source <composed body file>`.
   Exit `1` — fix each `unfilled:` line it names and check again, at most twice; the script in
   step 4 refuses a body that still fails, so never pass one you have not seen pass. Exit `0` — the
   filled file is the body.
4. Run, with `dangerouslyDisableSandbox: true`:
   `${CLAUDE_PLUGIN_ROOT}/skills/publish-change/scripts/publish-change.sh <branch> <title>
   <body file> [base]`, substituting the values given above. Omit the final argument if no
   `base` line was given.
5. Delete the temporary files.
6. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail`, from the live `git`/`gh` outcomes and from the same
template check run again before anything is pushed. The only judgement in this skill is which part
of the composed body answers which template heading.
