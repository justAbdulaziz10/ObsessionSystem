# Codex add-on

Everything in ObsessionSystem works with Claude Code alone. The Codex add-on lets the Claude session hand a well-scoped implementation slice to the [Codex CLI](https://github.com/openai/codex) and keep its own context for planning, integration and review.

## Setup

1. Install the Codex CLI and run `codex login`.
2. Check: `codex-ha status` should show `codex1 ~/.codex: READY`.
3. Optional: a second account in `~/.codex_second`:

   ```
   CODEX_HOME=~/.codex_second codex login
   ```

   `codex-ha` fails over to it when the first account hits a usage limit. To use other directories, set `CODEX_HA_HOMES=dir1:dir2`.

## How a slice runs

1. The lead (Claude) calls the `agent-codex-worker` agent with the task and its acceptance criteria. The agent runs in its own git worktree.
2. The worker runs `codex-ha ready`. On exit code 75 it stops and reports `CODEX_UNAVAILABLE` with the reason, and the lead does the work itself.
3. The worker writes a brief and starts `agent-codex --detach --file .agentos-brief.md`. It waits with `agent-codex --wait <job>`, because a foreground call would hit Claude Code's 10-minute Bash limit.
4. `codex-ha run` executes:

   ```
   codex --ask-for-approval never exec --ephemeral [--model M] [-c model_reasoning_effort="E"] \
         --sandbox workspace-write --skip-git-repo-check -- "<brief>"
   ```

   Codex can edit files and run commands in the worktree without asking. `.git` stays read-only, so Codex cannot commit.
5. The worker checks the result itself: diff, the acceptance check, and for bugs the reproduction before and after. Only then does it commit. Codex's own summary is not accepted as evidence.
6. The lead integrates the commit and runs review.

`codex-ha` holds a lock on the directory it runs in, so parallel workers need separate worktrees.

## Configuration

| Setting | Where | Default |
|---|---|---|
| Model | `CODEX_HA_MODEL`, else `codex_model` in `~/.agent-os/config.json` | the Codex CLI's configured default |
| Reasoning effort | `CODEX_HA_EFFORT`, else `codex_effort` | the Codex CLI's configured default |
| MCP servers to disable for workers | `worker_disabled_mcps` | none |
| Plugins to disable for workers | `worker_disabled_plugins` | none |

Workers run with approvals off. If your Codex config connects personal mail, chat or production services, list those MCP servers in `worker_disabled_mcps`; the lead passes workers whatever data they need in the brief. `CODEX_HA_ALL_MCPS=1` ignores both lists.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 75 | no Codex account available: not logged in, CLI missing, or every account in cooldown. Callers treat this as "do it without Codex". |
| 73 | another `codex-ha run` holds this directory |
| 1 | usage error |
