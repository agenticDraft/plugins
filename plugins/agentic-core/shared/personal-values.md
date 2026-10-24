---
description: How every core skill handles a personal value — a credential or a personal identifier — that a project file needs. Read by setup and by any skill that writes or reads such a file.
---

# Personal values

A **personal value** is a credential or a personal identifier: a password, a token, an API key, an
account id, an email tied to an account, a private key, a session cookie, or a tracker identity such
as an entry of the project config's `trigger.allowed_identities`.

## Rules

- **Never ask for one.** No question, no option, no free-text prompt asks for a personal value.
- **Never write one.** Automation writes the key and a placeholder; only the human writes the value.
- **Never print one.** Not in chat, a report, a commit, a pull request, a prompt for another session,
  or a file — even when it is already in a file that was read. Refer to it by file and key.
- **A placeholder is the marker `FILL-IN:` followed by what goes there**, inside the value's own
  quotes: `"FILL-IN: tracker identity of a person allowed to trigger a run"`. It names the kind of
  value, never an example of one.
- **Name the file and the line.** After writing a placeholder, tell the human the file path, the line
  number `lib/find-placeholders.sh` reports, and what goes there.
- **Confirm by an offered answer, never a typed word.** Ask with `AskUserQuestion` whether the line is
  filled, offering exactly two answers: **Filled** and **Later**. Do not ask the human to type
  anything.
- **Re-check the file, not the answer.** On **Filled**, run `lib/find-placeholders.sh <file>`. Exit
  `0` means none is left; exit `1` names the lines still holding one — report them and offer the two
  answers again. On **Later**, stop and say the file is not validated until the placeholder is gone.
- **Validate after the check, never before.** A shape-only validator accepts a placeholder, so it runs
  only once `lib/find-placeholders.sh` exits `0`.
- **Keep what the human filled.** A re-run carries every filled value forward unchanged and unprinted;
  it writes a placeholder only where none and no value is present.

## Verification

```bash
bash plugins/agentic-core/shared/lib/find-placeholders.test.sh
```
