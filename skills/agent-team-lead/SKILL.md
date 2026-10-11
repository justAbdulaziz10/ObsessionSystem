---
name: agent-team-lead
description: Plans substantial engineering work as vertical slices with acceptance checks and blocked-by links, dispatches Codex workers, and integrates and verifies the result on one branch. Use when a change needs several slices or parallel workers, or when work must be reviewed in proportion to its risk.
---

# Agent team lead

Act as lead architect and integrator. One strong worker beats three overlapping ones: split only genuinely independent work, and make tiny mechanical edits yourself. Treat external tools, MCPs, plugins, and subagents as optional when direct work is faster and sufficient.

## 1. Ground

- Load only the skills and tools that materially help this task.
- Reuse current state: `agent-task status`, checkpoints, and earlier research.
- When the requirements are vague, run `requirements-grilling` first.
- Write acceptance criteria as pass/fail checks.

Done when each acceptance criterion names a command, test, or observable result.

## 2. Slice vertically

- Each slice delivers end-to-end, testable behaviour through every layer it touches (data, logic, API, UI, tests).
- Each slice fits one worker context: a brief of about a page plus pointers. Split anything larger.
- Prefactoring that makes later slices easy is its own first slice.
- A wide mechanical refactor (rename or retype a shared symbol) runs as expand (add the new form beside the old), migrate callers in batches, then contract (remove the old form), one slice per step.

Write the plan as a table:

| # | Behaviour delivered | Acceptance check | blocked-by |
|---|---|---|---|
| 1 | <end-to-end behaviour> | `<command>` exits 0 | none |
| 2 | <end-to-end behaviour> | `<command>` exits 0 | 1 |

List in `blocked-by` only the slices whose output this slice needs. Interactive: show the table and let the user adjust granularity and links before dispatch.

Done when every slice has an acceptance check and an explicit `blocked-by` (or `none`).

## 3. Dispatch the frontier

The frontier is every slice whose blockers are merged into the integration branch.

- Create the integration branch from the freshly synced base (`agent-ship sync`, then `git switch -c integrate/<slug>`) and keep it checked out. Worker worktrees start from its last commit, so commit integrated work before each dispatch.
- Dispatch each frontier slice as soon as it is unblocked, each worker in its own worktree: to `agent-codex-worker` when the Codex add-on is set up (`codex-ha ready` exits 0), otherwise to a Claude Code subagent. Brief with the slice's behaviour, its acceptance check, and pointers (spec path, related commits, files) instead of pasted context.
- Run at most 3 workers at once, and only on slices with no blocking link between them and no overlapping files.
- On `CODEX_UNAVAILABLE`, implement the slice yourself from the worker's worktree and say so in the final report.
- Background workers die when this session compacts or exits. Tell each worker to write its report to a file (path in the brief) before its final verification, and to run checks longer than a minute detached: `nohup <cmd> > <log> 2>&1 &`, then read the log.
- If a worker is cut off, read its report file and log, then rerun the acceptance check yourself; a partial transcript is not evidence.

Done when every frontier slice has a running worker or is merged.

## 4. Integrate each slice

- Read the worker's actual commit (`git show <sha>`); its summary is a claim, not evidence.
- Merge or cherry-pick it onto the integration branch and rerun its acceptance check there.
- Recompute the frontier and dispatch newly unblocked slices.

Done when the slice's acceptance check passes on the integration branch.

## 5. Review and verify

- Run `agent-review-route "<task>"` and only the reviewers it recommends. Give each reviewer the integration diff (`git diff <base>...integrate/<slug>`) and the acceptance criteria, never worker summaries, per `agent-team-reviewer`.
- Fix findings in one worker per cycle. After 3 review-fix cycles without SHIP, escalate to the user with the open findings.
- Run every acceptance check and the project's checks on the integration branch, then record them with `agent-task proof capture <task-id> --checks`.

Done when every acceptance check passes on the integration branch and the review verdict is SHIP.

## 6. Queue leftovers

Queue each unfinished slice whose blockers are merged into the base you pass, with its acceptance check as the done command:

```bash
agent-overnight add --repo <path> --base integrate/<slug> --done "<acceptance check>" \
  --source agent-team-lead --key <slug>-<n> "<behaviour delivered>"
```

The queue has no dependency links, so list still-blocked slices in the report with their blockers.

Done when every unfinished slice is queued or listed with its blocker.

## Report

Integration branch, slices merged (commit SHAs), checks run with results, review verdict, queued items, still-blocked slices, worker worktrees left for cleanup, remaining risks.

Source: vertical slices, blocking links, and frontier dispatch adapted from mattpocock/skills `to-tickets` and `implement-spec` (MIT).
