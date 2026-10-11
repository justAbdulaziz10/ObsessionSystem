# How it works

ObsessionSystem is the working method of one heavy Claude Code user, made portable. It has four parts, each usable without the others.

## 1. Rules

[policy/RULES.md](../policy/RULES.md) is about 60 lines that Claude Code loads at the start of every session, through an import line in `~/.claude/CLAUDE.md`. It sets the working method:

- acceptance criteria are pass/fail checks;
- an agent's report is a claim until the checks run;
- review is routed by risk;
- nothing is pushed without the gate.

Two longer references, [DELIVERY.md](../policy/DELIVERY.md) and [TASKS.md](../policy/TASKS.md), are read only when a task needs them. This keeps the always-loaded context small.

## 2. Skills and agents

Skills are loaded by Claude Code when their description matches the task:

| Skill | Use |
|---|---|
| `agent-work-loop` | the default loop for substantial work: inspect, define done, implement, prove |
| `requirements-grilling` | turn a vague feature request into checkable acceptance criteria |
| `diagnosing-bugs` | reproduce, hypothesize, instrument, fix, regression-test |
| `agent-team-lead` | split work into vertical slices with checks and dependencies; dispatch and integrate |
| `agent-team-reviewer` | review against the original requirement on two axes, Spec and Standards/Risk |
| `create-verification-skill` | generate a project-local `verify-<app>` skill that drives the real app |
| `maintain-verification-skill` | keep that skill accurate as the app changes |
| `correct` | find mistakes that keep recurring and make them impossible with types, lint, hooks or tests |
| `writing-skills` | write and review skills to one standard |

Agents run as subagents:

| Agent | Use |
|---|---|
| `agent-risk-reviewer` | read-only adversarial review for auth, payments, privacy, data and migrations; Opus model |
| `agent-codex-worker` | hands one implementation slice to Codex and verifies the result ([codex.md](codex.md)) |

## 3. Commands

Plain Python and shell scripts in `~/bin`, with no dependencies beyond Python 3.9 and git. [commands.md](commands.md) lists them all. The main ones:

- **`agent-ship`:** the delivery gate. It runs a secret scan, a floor guard against weakened tests and lint, and the project's own checks before any push. It also pushes only to the right remote and never forces.
- **`agent-review-route`:** picks at most three reviewers from what the diff actually touches.
- **`agent-task`:** a durable task record (checklist, events, proof, handoff) that survives the session.
- **`agent-recall`:** searches lessons, memory files and recorded fixes.
- **`agent-overnight`:** an unattended queue in which a shell command, not the agent, decides when a task is done.

## 4. Hooks (opt-in)

- `install.sh --with-hooks` adds Claude Code hooks:
  - `agent-ship guard` blocks force-pushes to base branches and pushes to a mirror ahead of the canonical remote;
  - the telemetry hook records which skills, agents and MCP servers were used.
- `install.sh --with-git-hooks` sets git's global `core.hooksPath`, so the same push rules apply to pushes from any tool. A repository's own hooks still run.

## What is installed where

| Path | Contents | Removed by `uninstall.sh` |
|---|---|---|
| `~/bin/agent-*`, `~/bin/codex-ha` | links to `bin/` (copies with `--copy`) | yes |
| `~/.agent-os/policy/` | links to `policy/` | yes |
| `~/.agents/skills/<name>` | links to `skills/` | yes |
| `~/.claude/skills/<name>`, `~/.claude/agents/<name>.md` | links | yes |
| `~/.claude/CLAUDE.md` | a three-line marked block, appended | yes (backup kept) |
| `~/.claude/settings.json` | hook entries (`--with-hooks` only) | yes (backup kept) |
| git `core.hooksPath` | `~/.agent-os/git-hooks` (`--with-git-hooks` only) | yes |
| `~/.agent-os/install-manifest.tsv` | every path the installer created | yes |
| `~/.agent-os/config.json`, `delivery/profiles.json`, `LESSONS.md` | starting files, then yours | only with `--purge` |
| `~/.agent-os/v2/`, `runtime/` | task records, telemetry, CI results | only with `--purge` |

`uninstall.sh` removes only paths listed in the manifest; an edited `--copy` file is kept.

### Several Claude accounts

`~/.claude` above means every Claude Code config dir in use: `$CLAUDE_CONFIG_DIR` (default `~/.claude`), plus each directory in `AGENT_CLAUDE_DIRS`, a colon-separated list. With a second account in `~/.claude_second`:

```sh
export AGENT_CLAUDE_DIRS=~/.claude_second   # in your shell profile
./install.sh --with-hooks
```

The installer then sets up both dirs. Telemetry labels each session with its dir's name (`claude`, `claude_second`). `agent-overnight` tries the dirs in order when one runs out of usage, and `agent-review-route` looks for skills in all of them.

## Data and network

All state is local files and SQLite under `~/.agent-os`. Nothing is uploaded except in the cases below:

- `agent-ship sync` and `push` talk to your git remotes. After a push to GitHub, a pass/fail commit status is posted with `gh` (it can be turned off).
- `agent-session-distill` and `agent-recall index --aliases` send short, redacted text to a Claude model through `claude -p`. Both run only when you invoke them; aliases are off by default.
- `agent-overnight` and `codex-ha` run Claude Code and Codex, which talk to their providers as usual.

The telemetry hook records names and counts, never prompts or transcript text.

## Limits

- Developed on macOS. The CI suite also runs on Linux; Windows is not supported. The telemetry ingester's shebang uses `env -S`, which needs GNU coreutils 8.30 or newer on Linux (not BusyBox).
- The rules and skills were extracted from one person's setup and tuned for it. Edit `policy/RULES.md` to match how you work; it is meant to be yours.
- The floor guard is pattern-based. It catches the common ways a change weakens a test suite, not every way.
- The `agent-task` checklist comes from keywords in the request. Edit `checklist.json` when it is wrong.
