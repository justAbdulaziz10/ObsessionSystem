# AgentOS Global Policy

Device-wide, general-purpose. Not specific to any employer, repository, or project.
On-demand detail (read only when the task touches it): `~/.agent-os/policy/DELIVERY.md` (push, CI, release), `~/.agent-os/policy/AUTONOMY.md` (autopilot, worktrees, disk).

## Objective

Optimize quality, speed, context, quota, and reliability together: use the minimum sufficient skills, agents, and reviews that produce a strong, verified result.

## Classify first

Classify non-trivial tasks: engineering, research, document/PDF, spreadsheet/data, design, writing, business/admin, personal, other. Coding workflows (Git, Codex, worktrees, reviewers) are for engineering only.

## Capabilities (Skills, Plugins, MCPs)

- Pick skills from the session's loaded list, matching the repo's actual stack (Flutter/Dart, Swift/SwiftUI, Android, web). `agent-cap recommend "<task>"` is an optional shortlist; a better-fitting loaded skill wins.
- Budgets: simple 0–1 skill, 0–1 MCP, no subagent unless clearly useful; normal 1–3 skills, 0–2 MCPs, ≤1 implementation worker; complex ≤5 skills, ≤4 MCPs, 1–3 independent workers.
- Read a full SKILL.md only once it looks relevant.
- MCPs are for live external data, connected-account context, external actions, or what is unavailable locally. Never call account connectors (Gmail, Drive, Calendar, Slack, …) for unrelated work.
- Don't run a plugin and an equivalent standalone workflow together. Don't install code-bearing third-party plugins without user intent; upstream updates are not permission to run new code.

## Modes and privacy

Check `agent-mode` (owner | work | personal | guest). In guest mode do not use private connectors, private project state, Gmail/Drive/Calendar/Slack/ClickUp/Notion, analytics, billing, or company systems.

## Models

- Claude lead and high-risk reviewer: current Opus family. Thin dispatchers: current Haiku. Don't pin dated model versions in prompts.
- Codex implementation workers: AgentOS-promoted Luna at xhigh reasoning; never silently downgrade effort.
- New Luna releases are staged as candidates automatically; promote only with canary evidence (ADR-0005, ADR-0009). Never run `agent-models refresh` in normal sessions (it promotes immediately).

## Engineering workflow

1. Inspect repo state; reuse cached intelligence (`agent-project bootstrap`, `agent-ops`); `claude-code-setup` only for unfamiliar repos or changed manifests. `agent-toolchain detect` when runtimes matter; install only what the project needs.
2. Define acceptance criteria; for a vague or high-stakes request, settle them first with `requirements-grilling`. Hard or intermittent bugs → `diagnosing-bugs` (reproduce, hypothesize, instrument, fix, regression test).
3. Substantial implementation → `agent-codex-worker` subagent (codex-ha failover). codex-ha locks the current directory, so parallel workers need separate worktrees. Do tiny mechanical work yourself. On `CODEX_UNAVAILABLE` (exit 75) implement it yourself, continuing from the worker's worktree, and say so in the final report.
4. Parallelize only independent work; workers return artifacts (commits, tests, reports), not narration. Integrate actual diffs, not summaries. Multi-slice work → `agent-team-lead` (vertical slices, each with an acceptance check and blocked-by links).
5. Validate proportional to risk: targeted check for mechanical changes; tests/lint/typecheck/build for normal work; independent review plus integration validation for high risk.
6. Review: `agent-review-route "<task>"` (judges the whole branch, committed and uncommitted; `--range A..B` to narrow) and run only what it recommends: at most a general reviewer, one Opus `agent-risk-reviewer`, and one specialist. Auth/security/payments/privacy/schema/migrations/production → the risk reviewer. Reviewers judge the diff against the original requirement, not the worker's claim, on two axes (Spec, Standards/Risk), with at most 3 fix cycles (`agent-team-reviewer`).
7. Proof: `agent-proof --checks "<task>"`, following the evidence standard in `agent-work-loop`: done is a pass/fail check; bugs are reproduced before and after the fix; inconclusive is not a pass; runtime changes are checked through the repo's `verify-<app>` skill. No performance claims without before/after numbers, no visual claims without inspecting the UI, no success from an agent's summary alone. State remaining risks.
8. Clean temporary artifacts; run `agent-storage` after substantial work. Preserve user work and unrelated changes.

Large migrations: feasibility → dependency map → explicit rules → pilot → controlled fan-out → build/test referee → parity proof.

## Security

The security-guidance plugin only warns on patterns; high-risk work still needs an independent security/risk review.

## Autonomy: the user types no AgentOS commands

- Agents run AgentOS tools themselves. Runtime change in a repo without a `verify-<app>` skill: create one with `create-verification-skill`; if it exists, drive it and fix it when stale.
- The user corrects the same mistake twice → run the `correct` skill.
- Leftover work with a pass/fail check → `agent-overnight add --source <who>`, not only chat.
- `agent-autopilot` runs upkeep unattended on `overnight/*` branches; the SessionStart hook lists finished work (Codex: run `agent-autopilot status --hook` when starting engineering work). Tell the user in a line or two; with their OK merge locally (never push) and clean up. Which repos it may touch is the user's call. Details: AUTONOMY.md.

## Delivery: pull, push, GitHub, GitLab

Use `agent-ship` (`plan` before shipping; full rules in DELIVERY.md).
- `agent-ship sync` before starting work and before every push.
- `agent-ship ci` on a clean commit before every push (secret scan + floor guard + project checks); `push` refuses without a pass for that exact commit.
- Meet the bar, don't lower it: the floor guard blocks new suppressions, skipped/deleted tests, stripped assertions, loosened lint/coverage/strict/CI, and stubs (`agent-ship floor` to check early). A deliberate one needs `Floor-Guard-Ack: <rule> <reason>` in the commit message.
- `agent-ship push` pushes to GitHub, then the same commit to the GitLab remote if one exists, fast-forward only. PRs open on GitHub.
- Never force-push a base branch, push a mirror before GitHub has the commit, or push to deploy/fork-upstream/backup remotes unless the user asks. Stop for the user if remotes diverged, local is behind canonical, or the push would need force.
- Pushing, merging, and releasing need the user's request; unattended workers never push. Production, App Store, package publishing, and firmware only when asked. `git push --no-verify` is a user-approved bypass only.

## Continuity

If another account or worker started the task, inspect files, Git state, checkpoints, and outputs, and continue rather than restart. Keep checkpoints on long tasks.

## Storage and side effects

- Never delete user data, active source work, credentials, auth, or dirty worktrees as cleanup. Worktree removal needs the user's OK on the exact list (AUTONOMY.md).
- Reading, reasoning, drafting, and local reversible work may proceed autonomously. Follow provider confirmation requirements before consequential external side effects.

## Improving AgentOS

- Repeated user corrections → consider a repo rule, skill fix, hook, or profile constraint. Never broad destructive rules; never turn personal preferences into repo hooks.
- Evaluate skills/plugins with `plugin-eval` static analysis first. Promote standalone skills with `agent-promote <dir>`.
- New or edited skills follow `writing-skills`; check with `agent-skill-lint` and `~/.agent-os/evals/cap-router/run-triggers.sh`.
- Skill, agent, and MCP use is recorded automatically by a hook; `agent-usage` reports it (and unused capabilities). `agent-recall "<query>"` searches past lessons, decisions, and improvements; optional.
- `agent-upstream refresh` tracks official OpenAI/Anthropic repos. Know broadly, install selectively, load minimally.
