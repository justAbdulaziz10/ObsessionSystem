---
name: agent-work-loop
description: Keeps substantive software work grounded in the real codebase and finished with evidence rather than claims. Use for features, ambiguous bugs, architecture, UI or runtime behavior, or performance work where context and proof affect correctness.
---

# Agent work loop

Deliver the requested outcome with evidence that it works. Preserve the user's scope and any existing work in the checkout.

## Ground the problem

- Read the applicable project instructions and inspect repository status before editing.
- Start from the request and its source material: issue, report, screenshot, thread, code, runtime evidence, and relevant project docs. Restate the underlying problem in plain language when intent is ambiguous or the source material is noisy; separate observed facts from assumptions and hypotheses.
- Trace the affected code path and its callers. Read history, design records, or related tickets when they help explain why the system works this way. Use only sources and connectors actually available.
- Define success as an observable user or system outcome. Leave room for a sound implementation rather than prescribing details the codebase can decide. When a feature request leaves users, scope, or the definition of done unstated, use `requirements-grilling` to reach checkable acceptance criteria first.

## Choose a design with evidence

- For a small, clear change, keep the design and plan small.
- For a significant design choice, compare plausible alternatives against real call sites, constraints, failure modes, and measured behavior. Use a runnable prototype, benchmark, or focused experiment to answer open questions instead of extending an abstract plan. Independent agents can compare alternatives when the task and client policy permit delegation and the work justifies the added cost.
- For a large change, turn the chosen design into small steps, each with a clear check. Keep temporary plans out of permanent project documentation once the work is complete.
- For substantial or high-risk changes, review the final diff in a separate pass after implementation. Recheck the requested outcome, affected callers, and likely regressions. Use a fresh reviewer context only when the task and client policy permit it; otherwise perform an explicit self-review of the diff.

## Use and improve the project harness

- Find the project's verification skill, control CLI, feature map, and build instructions before inventing a new workflow. Follow the project-specific source of truth.
- When a feature changes, update an existing feature map or verification guide in the same change if the project expects it. Create project-specific documentation only when it prevents repeated rediscovery or materially improves verification.
- When the same manual inspection or interaction keeps recurring, prefer a small reusable CLI or script over repeated prose or throwaway automation. Give it clear subcommands, useful `--help`, machine-readable output where practical, actionable errors, and `--dry-run` for commands with destructive effects.
- Keep tools narrow and cheap to maintain. Add controls such as snapshots, screenshots, logs, traces, seeded test data, or runtime inspection only when the project needs them.

## Close the verification loop

- Choose the smallest meaningful checks for the changed behavior, following higher-priority policies, project instructions, and the user's request. A passing test is useful evidence, but it does not by itself prove that a changed screen or runtime flow works.
- For user-facing UI or runtime changes, launch the app in the intended development environment, exercise the affected path, and inspect the result. Use screenshots, accessibility state, logs, or traces when they provide direct evidence. For performance changes, compare the same workload and environment before and after.
- For Apple-platform work, use the project's simulator profile and available Xcode tools. Never disturb a simulator another person or agent may be using.
- Keep prototypes and test data isolated from production accounts and user data. Make cleanup part of the workflow when temporary artifacts are created.
- If an environment or permission prevents verification, state exactly what remains unverified. Never imply you ran a check you did not run.

## Evidence standard

- Define done as checks that can pass or fail before you start ("the repro passes, the JSON parses, text output is byte-identical"). A duration is not a finish condition.
- Bug: follow the `diagnosing-bugs` skill. Before editing any source file, run one repro command on the surface where the bug was reported and show it failing with the reported symptom; with no repro, record the blocker instead of guessing a fix. Confirm the cause with runtime evidence, fix, then rerun the same repro and show it passing. Remove every tagged `[DEBUG-<id>]` log before finishing.
- Verify on the real artifact through the project's `verify-<app>` skill when one exists (`.agents/skills/verify-*` or `.claude/skills/verify-*`). If the project has none and the work changes runtime behavior, create one with `create-verification-skill` first.
- "Inconclusive" and "checked on a different surface" are not passes; say which check could not run.
- Mark claims as measured (you ran it and saw the result), inferred (follows from what you saw), or guessed.
- The agent that wrote a change does not approve it: review it in a fresh context, with a different model when one is available, following `agent-team-reviewer` (give the reviewer the diff and the original requirement, not your claim of success).
- When the user corrects the same mistake twice, use the `correct` skill to make it impossible instead of adding another written rule.
- Work that can run unattended (a goal plus a command that proves it done) goes to `agent-overnight add --repo <path> --done "<cmd>" "<goal>"`; `agent-overnight run` works through the queue, each task in its own worktree and branch. Queue leftovers yourself instead of telling the user to.

## Report the result

Summarize the user-visible change, the evidence actually collected, and any important tradeoff or unverified surface. Measure the outcome and quality of the work; change counts and PR counts are not success criteria.
