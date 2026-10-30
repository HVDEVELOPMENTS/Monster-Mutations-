---
description: Run the Studio test suite, then save (or compare against) a named git checkpoint.
argument-hint: create <name> | verify <name> | list
---

Checkpoints are git tags named `checkpoint/<name>` on a commit whose tests passed. If `git` isn't on PATH use `%LOCALAPPDATA%\Programs\Git\cmd\git.exe`.

Arguments: $ARGUMENTS

## create <name>

1. Run the full test suite in Studio exactly as described under "Running tests" in `CLAUDE.md` (Play session, Server datamodel, cloned `ServerScriptService.MonsterFactory`). Stop play afterwards.
2. If any test fails, report the failures and **do not** create the checkpoint.
3. If all pass: commit any outstanding changes with message `Checkpoint: <name>` (show the user what will be committed first if there are changes they haven't seen), then `git tag checkpoint/<name>`.
4. Report: tag, commit hash, tests passed/total.

## verify <name>

1. `git diff --stat checkpoint/<name>` to show what changed since the checkpoint.
2. Run the full test suite as above.
3. Report files changed, and tests passed/total now (the checkpoint had all passing by definition).

## list

`git tag -l "checkpoint/*" --sort=-creatordate --format="%(refname:short)  %(objectname:short)  %(creatordate:short)"`
