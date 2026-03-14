---
name: repo-diff-commit-planner
description: Analyze repository differences, group related changes into logical commits, and execute safe staging and commit steps with clear messages.
---

# Repo Diff Commit Executor

## Overview

Use this skill to inspect current repository differences, decide what is ready to commit, split the work into logical commit groups, and then execute the git staging and commit steps for all commit-ready groups. It focuses on clean grouping, safe execution, and a buildable commit sequence.

## When To Use

- You have mixed local changes and need a clean commit strategy.
- You want to split one large diff into several distinct commits and actually create them.
- You need help deciding what should be committed now versus later and want the commit-ready groups executed.
- You want concise and descriptive commit messages per group and a clear execution report.

## When Not To Use

- Do not use this skill for history rewriting such as `git rebase`, `git commit --amend`, or force-push workflows unless explicitly requested.
- Do not use this skill when the working tree contains risky or unexplained changes that cannot be safely grouped.

## Inputs Needed

- Current branch and repository context.
- `git status` and diff summaries for changed files.
- Any known constraints, such as release urgency or risky files.
- Build or test command when verification is expected.

## Workflow

### 1. Inventory Repository Differences

- List changed, untracked, deleted, and renamed files.
- Summarize change scope by area (feature, bugfix, docs, config, tests, refactor).
- Identify potentially sensitive or generated files that should not be committed.
- Check whether any candidate file is ignored by `.gitignore`, `.git/info/exclude`, or a global excludes file before staging it.

### 2. Commit-Readiness Analysis

- Mark each change as `commit-now`, `hold`, or `needs-review`.
- Check dependency links between files to avoid broken intermediate commits.
- Highlight risky changes needing explicit confirmation.
- Aim to commit every `commit-now` group before finishing the task.
- Treat ignored files, local secret files, API keys, token-bearing config, and other secret-like artifacts as `hold` by default unless the user explicitly requests versioning them.

### 3. Logical Grouping

- Build groups by single responsibility and coherent intent.
- Keep unrelated concerns in separate commit groups.
- Prefer small, reviewable groups that preserve a buildable progression.

### 4. Commit Sequencing

- Order groups so foundational changes land first.
- Place follow-up refactors or cleanup after behavior-changing commits.
- Keep test updates with the commit they validate when possible.

### 5. Commit Message Drafting

- Draft one strong subject line per group in imperative mood.
- Prefix each commit subject with the current local execution date in ISO format for easier later searching and lightweight date-based filtering.
- Default subject format:
  - `[YYYY-MM-DD] Imperative subject`
- Use the actual current local date of execution, unless the user explicitly requests a different commit-message format.
- Add a short body when context, risk, or migration notes are needed.
- Ensure message text reflects what changed and why.

### 6. Execute Commits

- Stage only the files that belong to the current group.
- Commit each group with the drafted message using non-interactive git commands.
- If `git add` reports that a path is ignored, do not use `git add -f` or any force-add switch as a shortcut.
- When an ignored file seems to be showing up in status anyway, diagnose whether it is already tracked with `git ls-files` and confirm the matching ignore rule with `git check-ignore -v --no-index` before changing anything.
- If an ignored file is already tracked and should stay local-only, prefer removing it from version control with `git rm --cached` instead of trying to restage or re-force-add it.
- Only version an ignored file after explicit user confirmation that the ignore should be bypassed, and call out the consequence clearly before doing so.
- If a git command fails because of `.git/index.lock` or a likely concurrent git process, wait a few seconds and retry before treating it as a blocker.
- Preferred retry behavior for transient git locking:
  - wait about 2 to 5 seconds
  - retry up to 3 times
  - only report a blocker if the lock condition remains
- Do not delete `index.lock` blindly as part of the normal workflow.
- After each commit, verify the worktree and confirm the next group is still valid.
- If build or tests are part of the expected verification, run them at the appropriate point.
- Continue until all `commit-now` groups are committed or a real blocker is reached.

### 7. Final Reporting

- After committing all `commit-now` groups, attempt a normal `git push`.
- If push succeeds, report that briefly.
- If push fails, do not force-push or rewrite history.
- Instead, give a short diagnosis based on the visible git error, for example:
  - authentication/credential failure
  - remote rejected update
  - non-fast-forward because remote is ahead
  - missing upstream tracking
- Report which groups were committed and in what order.
- Report any deferred `hold` or `needs-review` items left in the worktree.
- State any verification commands that were run and their result.
- State whether push succeeded or failed.

## Output Format

Keep the final report concise by default. Compress file-by-file detail unless it is needed to explain grouping or a deferred risk.

Provide results using this structure:

1. Repository change summary
2. Commit readiness table (`commit-now` / `hold` / `needs-review`)
3. Proposed commit groups with short rationale
4. Ordered commit plan
5. Draft commit messages (subject and optional body when needed)
6. Execution result per committed group
7. Push result
8. Deferred items and assumptions

Prefer:
- short grouped file summaries over long file inventories
- one-line rationale per group
- compact execution results like `<hash> [YYYY-MM-DD] <subject>`
- compact push result like `push succeeded` or `push failed: non-fast-forward`
- brief deferred-item notes

Only expand beyond that when:
- a group boundary is non-obvious
- a risky file is being held back
- the user explicitly asks for a detailed breakdown

## Execution Guardrails

- Do not use destructive commands such as `git reset --hard`, `git checkout --`, or force-push unless explicitly requested.
- Do not use `git add -f`, `git add --force`, or similar overrides to stage ignored files unless the user has explicitly confirmed that bypassing ignore rules is intended.
- Do not amend commits unless explicitly requested.
- Do not commit files marked `hold` or `needs-review` just to empty the worktree.
- If unexpected changes appear during execution, stop and report the issue before continuing.
- Keep commits scoped, reviewable, and logically ordered.
- Treat transient git lock errors as retryable first, not as immediate hard failures.
- After successful commits, a normal push attempt is expected by default unless the user explicitly says not to push.
- If push fails, report the likely cause from the git output and stop there.

## References

- `references/commit_grouping_playbook.md`
