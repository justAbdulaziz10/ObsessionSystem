# AgentOS Autonomy and Storage Reference

Full autopilot, worktree, and disk rules (moved verbatim from GLOBAL.md on 2026-10-10; GLOBAL.md keeps the summary). Read when handling autopilot results, removing worktrees, or freeing disk.

## Autonomy: the user types no AgentOS commands

Agents run AgentOS tools themselves; never ask the user to type one.
- Runtime change in a repo without a `verify-<app>` skill: create it with `create-verification-skill` as part of the task. With one: drive it; fix it if it is stale.
- The user corrects the same mistake twice: run the `correct` skill.
- Work left over with a pass/fail check (remaining slices, out-of-scope failures you found, follow-ups): queue it with `agent-overnight add --source <who>`; do not leave it only in chat.
- `agent-autopilot` (launchd, hourly) finds repos the user works in (a repo wakes up on the user's first session in it after activation, including any future project), queues upkeep, and runs the queue unattended on `overnight/*` branches. A session-start hook lists finished work (Codex has no hook: run `agent-autopilot status --hook` once when starting engineering work): tell the user in a line or two, and with their OK merge locally (never push) and clean up.
- Which repos it may touch (`agent-autopilot allow|deny`) and turning it off are the user's call; act when they say so.


## Storage and side effects

- Never delete user data, active source work, credentials, auth, or dirty worktrees as cleanup.
- **Finished worktrees:** autopilot lists them once a day: clean (ignored files only if rebuildable, never `.env`, keys or release archives), idle a day, nobody inside, and merged or untouched for 14 days with commits still on a branch. The session hook shows the list. Removal (`agent-autopilot worktrees --apply <list id>`) needs the user's OK on that exact list; it refuses a changed list and rechecks each one. Unmerged branches are kept.
- **Disk safety net:** below 15 GB free, autopilot clears only what builds recreate. That means `agent-storage`'s pressure tier (orphaned or old DerivedData, uv/brew download caches) plus git-ignored build folders in worktrees idle a day with nobody inside. Folders holding release archives, IPAs, AABs or symbol mappings are kept. An open Xcode keeps DerivedData. Simulators and package stores (Gradle, SwiftPM, pub) are never touched. Below 10 GB, unattended work pauses.
- **Local CI on GitHub:** a local `agent-ship ci` result shows as the `agent-ship/local-ci` commit status once the commit is on GitHub (posted by `push` and the pre-push hook). A profile can opt out with `"report_status": false`. Branch protection is not set up: the user declined it.
- Reading, reasoning, drafting, and local reversible work may proceed autonomously. Follow provider confirmation requirements before consequential external side effects.

