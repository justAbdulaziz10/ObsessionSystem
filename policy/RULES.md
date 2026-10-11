# Working rules

These rules apply to every coding session. Two reference files hold the detail; read them only when the task touches them:

- `~/.agent-os/policy/DELIVERY.md`: pushing, the CI gate, releases.
- `~/.agent-os/policy/TASKS.md`: durable task records for work that may outlive one session.

The repository's own instructions (README, CONTRIBUTING, AGENTS.md, CLAUDE.md) take precedence over these rules.

## Before changing code

- Read the relevant code, the repository's instructions and `git status` first.
- Write the acceptance criteria as checks that pass or fail. If the request is vague or high-stakes, settle them with the user first (`requirements-grilling` skill).
- For a hard or intermittent bug, follow the `diagnosing-bugs` skill: reproduce, hypothesize, instrument, fix, add a regression test.
- Load only the skills and MCP servers the task needs.

## Doing the work

- Make small, mechanical edits yourself. Hand a substantial, well-scoped slice to `agent-codex-worker` when `codex-ha ready` exits 0. Otherwise do it yourself or give it to a Claude subagent.
- Parallelize only independent work. Each parallel worker needs its own git worktree, because codex-ha locks the directory it runs in.
- Integrate the workers' actual diffs, not their summaries.
- Preserve the user's changes and unrelated code. Never delete user data, credentials or a dirty worktree as cleanup.

## Proving it

- Done means the acceptance checks ran and passed. An inconclusive check is not a pass.
- For a bug fix, run the reproduction before the fix (it fails) and after it (it passes).
- Make no performance claim without before/after numbers, and no visual claim without looking at the UI.
- An agent's report is a claim, not evidence. Read the diff and run the checks yourself.
- For runtime changes, drive the app with the repository's `verify-<app>` skill. If the repository has none, create one with `create-verification-skill`.
- The final report states what was verified, what was not, and the risks that remain.

## Review

- Run `agent-review-route "<requirement>"` and use only the reviewers it recommends. That is at most three:
  - a general reviewer;
  - `agent-risk-reviewer` for auth, payments, secrets, privacy, schema, migrations, infrastructure or webhooks;
  - one specialist.
- Reviewers judge the change against the original requirement, not against the author's description of it.
- After three fix cycles, stop and take the open findings to the user.

## Delivery

- Push, merge, release or publish only when the user asks. Unattended runs never push.
- Before every push, run `agent-ship sync`, then `agent-ship ci` on a clean commit, then `agent-ship push`.
- Do not lower the bar to get a green result:
  - no new suppressions;
  - no skipped or deleted tests, and no removed assertions;
  - no loosened thresholds or lint rules;
  - no stubs.

  A deliberate exception needs a `Floor-Guard-Ack: <rule> <reason>` line in the commit message.
- Never force-push a base branch. Never use `git push --no-verify` unless the user asks.

## Failures and memory

- When the same approach fails twice, stop. Run `agent-recall "<error>"`, then change the approach.
- When a fix is proven, record it with `agent-task fail remember "<error>" "<fix>"`.
- When the user corrects the same mistake twice, run the `correct` skill to turn the correction into a lasting rule.
- Leftover work that has a pass/fail check goes into the queue with `agent-overnight add`, not just into the chat.
