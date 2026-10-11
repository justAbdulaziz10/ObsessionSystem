# Command reference

Every command lives in `bin/` and is linked into `~/bin` by `install.sh`. Most accept `--help`. Several small commands are thin aliases that forward to `agent-intel` or `agentos2`.

## Plan and route

| Command | Purpose |
|---|---|
| `agent-cap recommend "<task>"` | Recommends the minimum skills, plugins and MCPs for a task, within the budgets in `config.json`. Also `refresh`, `audit`, `summary`. Alias of `agent-intel cap`. |
| `agent-review-route "<task>" [--range A..B]` | Looks at the whole branch (committed and uncommitted) and recommends at most three reviewers: general, one Opus risk reviewer, one specialist. |
| `agent-mode [owner\|work\|personal\|guest]` | Shows or sets the privacy mode. Guest mode never uses private connectors. |
| `agent-project bootstrap` | Caches project intelligence (stack, checks, conventions) for the repo. Alias of `agent-intel project`. |
| `agent-toolchain detect` | Detects the runtimes a project needs. Alias of `agent-intel toolchain`. |

## Build

| Command | Purpose |
|---|---|
| `codex-ha run "<task>"` · `ready` · `status` | Codex worker pool with multi-account failover. Exit `75` (`AGENT_CODEX_HA_EXHAUSTED`) means every account is unavailable. It locks the current directory, so parallel workers need separate worktrees. |
| `agent-codex "<task>"` | Foreground or detached Codex HA job (`--detach --file brief.md`, `--wait`). |
| `agent-ha run\|status\|doctor\|logs` | Claude-side failover across accounts, falling back to `codex-ha`. |
| `agent-team init\|task\|write\|read\|status\|done` | Shared task board for a multi-agent team. |
| `agent-ops` | Checkpoints, handoff notes and an emergency fallback command (`AGENTOS_EMERGENCY_CMD`). |

## Track and prove

| Command | Purpose |
|---|---|
| `agent-v2 start "<request>"` | Starts or resumes a durable task and prints its id. Also `status`, `event`, `context`, `finish`, `dashboard`, `maintain`. |
| `agent-spec "<request>"` | Alias of `agent-v2 start`. |
| `agent-proof --checks "<task>"` | Captures pass/fail proof for a task. `agent-proof capture\|metric\|artifact <id>` attaches evidence to a v2 task. |
| `agent-handoff <task-id>` | Packages durable state so another account or session continues without rediscovery. |
| `agent-dashboard` | Overview of v2 tasks, metrics and events. |
| `agent-guard "<command>"` | Advisory risk check before an uncertain consequential command. |

## Deliver

| Command | Purpose |
|---|---|
| `agent-ship plan` | Explains where work comes from and goes to: canonical remote, mirrors, CI, release lanes. |
| `agent-ship sync` | Pulls safely before work and before every push. |
| `agent-ship ci [--learn \| --set CMD...]` | Local CI: secret scan, floor guard, whitespace and conflict markers, then the project's checks. Fails closed when a project has no checks. |
| `agent-ship push` | Pushes to GitHub, then the same commit to a GitLab mirror if one exists, fast-forward only. Refuses without a CI pass for that exact commit. |
| `agent-ship floor` | Runs the floor guard early: new suppressions, skipped or deleted tests, stripped assertions, loosened lint, coverage, strictness or CI, stubs. |
| `agent-ship guard` / `prepush` | Claude PreToolUse hook and global git pre-push hook that apply the same rules. |
| `agent-ship tidy [--apply]` · `release` · `scorecard` | Branch cleanup, releases, delivery stats. |

## Memory and learning

| Command | Purpose |
|---|---|
| `agent-recall "<query>"` | One ranked index over decisions, lessons, improvements, failure memories, the manual and Claude memory. |
| `agent-fail remember "<error>" "<resolution>"` | Stores a proven recovery for next time. |
| `agent-session-distill` | Turns yesterday's resolved tool failures into failure memories. |
| `agent-corrections` | Lists your messages that look like corrections, as input for the `correct` skill. |
| `agent-usage skills\|agents\|mcp\|unused\|sessions` | Capability usage recorded locally by the telemetry hook. |
| `agent-telemetry-hook` / `agent-telemetry-ingest` | The hook (shebang-less POSIX sh, usually forks nothing) and its detached ingester. |

## Autonomy

| Command | Purpose |
|---|---|
| `agent-autopilot tick\|status\|worktrees` | Hourly unattended upkeep on `overnight/*` branches. Lists finished worktrees and removes them only with your OK, the exact list, and re-checks. |
| `agent-overnight add\|run\|status\|clean` | A queue of coding tasks, each with a pass/fail `--done` check. It never pushes. |
| `agent-storage` | Disk guard that cleans caches safely. |

## The system itself

| Command | Purpose |
|---|---|
| `agent-system` | Where every canonical file lives. |
| `agent-doc-sync` | Regenerates `STATE.md` from the real configuration and reports drift. |
| `agent-system-change begin\|finish\|status\|rehash` | Backup, change, evidence, ADR, rollback. |
| `agent-skill-lint [--all]` | Deterministic SKILL.md checks: descriptions, layout, provenance, paths. |
| `agent-promote <dir>` | Promotes a standalone skill into the shared catalog after checks. |
| `agent-models refresh\|status\|rollback-luna` | Resolves current model IDs. New Codex releases are staged as candidates. |
| `agent-model-governor scan` | Stages new model candidates; promotion needs canary evidence. |
| `agent-plugin-governor scan` | Detects changed hooks, MCP config and executables after plugin updates. |
| `agent-plugins-sync` | Shares plugin state and the MCP deny list between accounts. |
| `agent-upstream refresh` | Tracks official Anthropic and OpenAI repositories. |
| `agent-research` | Mines finished tasks for orchestration experiments. |
| `mcpall doctor\|sync\|diff\|add-http\|add-stdio\|remove\|login` | One manifest for MCP servers across every Claude and Codex account. |
