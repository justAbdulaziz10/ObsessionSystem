# ObsessionSystem

Rules, skills and a delivery gate for [Claude Code](https://claude.com/claude-code) that make the agent prove its work before anything ships.

[![CI](https://github.com/justAbdulaziz10/ObsessionSystem/actions/workflows/ci.yml/badge.svg)](https://github.com/justAbdulaziz10/ObsessionSystem/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Coding agents have predictable failure modes:

- They say "done" without running anything.
- They skip a failing test to get a green build.
- They push to the wrong remote.
- They forget everything when the session ends.

ObsessionSystem is the setup I use to stop that. It is a short rule file Claude Code loads every session, nine skills for the work that needs a method, and a set of local commands that enforce the parts rules alone can't.

<p align="center"><img src="assets/demo.svg" width="860" alt="Terminal: agent-ship ci fails because a commit skips a test, agent-ship push refuses; after a Floor-Guard-Ack line with a reason is added, ci passes and the push goes through."></p>

<sub>Real output. A commit skips a failing test. `agent-ship ci` fails, and `push` refuses without a passing run for that exact commit. Acknowledging the skip in the commit message, with a reason, lets it through and leaves a record.</sub>

## What you get

- **Rules** ([policy/RULES.md](policy/RULES.md)). About 60 lines, imported into `~/.claude/CLAUDE.md`:
  - acceptance criteria are pass/fail checks;
  - an agent's report is a claim until the checks run;
  - review is routed by risk;
  - nothing is pushed without the gate.
- **Skills:**
  - `diagnosing-bugs`: reproduce, then fix, then prove;
  - `requirements-grilling`: turn vague requests into checkable criteria;
  - `agent-team-lead` and `agent-team-reviewer`: split work into slices, then review it against the requirement;
  - `create-verification-skill`: drive the real app to verify changes;
  - `correct`: turn a mistake that keeps recurring into a lint rule, type, hook or test;
  - and three more.
- **`agent-ship`.** A local CI gate run before every push. It has three stages:
  - a secret scan;
  - a *floor guard* that blocks changes which lower the bar: skipped or deleted tests, removed assertions, new lint suppressions, loosened thresholds, stubs;
  - the project's own checks.

  It pushes only to the canonical remote and never forces.
- **`agent-review-route`.** Picks at most three reviewers from what the diff touches. Auth, payments, secrets, migrations and similar changes get a read-only Opus risk reviewer.
- **`agent-task`.** A task record that survives the session: checklist, events, proof, and a handoff another session can resume from.
- **`agent-overnight`.** A queue of unattended tasks. Each runs in its own worktree, a shell command decides when it is done, and nothing is merged or pushed.

[docs/how-it-works.md](docs/how-it-works.md) explains how the parts fit together. [docs/commands.md](docs/commands.md) covers every command.

## Install

Requires macOS or Linux, Python 3.9+ and git. `zsh` is needed only for the test suite, and `gitleaks` is optional: the secret scan uses it when present.

```sh
git clone https://github.com/justAbdulaziz10/ObsessionSystem.git
cd ObsessionSystem
./install.sh --dry-run    # print every change first
./install.sh
```

Commands are linked into `~/bin`, so make sure it is on your `PATH`. Start a new Claude Code session to load the rules and skills.

The installer never overwrites an existing file. It appends a marked three-line block to `~/.claude/CLAUDE.md` and backs up anything it edits. Two parts are opt-in:

| Flag | Adds |
|---|---|
| `--with-hooks` | Claude Code hooks:<br>• `agent-ship guard` blocks force-pushes to base branches;<br>• the telemetry hook records which skills, agents and MCP servers are used, locally and without prompts. |
| `--with-git-hooks` | a global git pre-push hook with the same push rules, for pushes from any tool |
| `--copy` | copy files instead of linking to this checkout |

`./uninstall.sh` reverses all of it. Your data in `~/.agent-os` stays unless you pass `--purge`.

## First steps in a project

```sh
agent-ship plan          # where this branch would go and what must pass first
agent-ship ci --learn    # try the detected checks (tests, lint, build) and remember the ones that work
agent-ship ci            # the full gate on HEAD
```

From then on the agent runs `agent-ship ci` and `agent-ship push` itself, as the rules tell it to. To learn the rest:

- [policy/DELIVERY.md](policy/DELIVERY.md): floor-guard rules, the acknowledgement format, per-repository profiles.
- [policy/TASKS.md](policy/TASKS.md): the task record lifecycle.

## Codex (optional)

The lead session can hand implementation slices to the [Codex CLI](https://github.com/openai/codex) through the `agent-codex-worker` agent. The worker verifies the result itself before committing. `codex-ha` fails over between logged-in accounts and exits 75 when none is available, and the lead then does the work itself. Everything else works without Codex. See [docs/codex.md](docs/codex.md).

## Tests

```sh
evals/run-all.sh
```

This installs into a temporary `HOME` and runs every suite there. Your own configuration is never touched. CI runs it on macOS and Ubuntu.

| Suite | Count |
|---|---|
| `agent-ship` | 155 cases |
| `agent-task` | 29 |
| Codex add-on | 24 |
| `agent-overnight` | 8 |
| Telemetry | 13 groups |
| Skill lint | the 9 skills |

## Limits

- The rules and skills come from one person's way of working. Read [policy/RULES.md](policy/RULES.md) before installing and edit it to suit you.
- The floor guard matches patterns in the diff. It catches the common ways a change weakens a test suite, not every way.
- Developed on macOS. Windows is not supported.

## Credits

Several skills adapt MIT-licensed work, with the license kept next to each skill:

- [mattpocock/skills](https://github.com/mattpocock/skills);
- [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills);
- Lauren Tan's pstack;
- tigerless-labs: the agent-memory recall design and the autoharness lint rules.

## License

[MIT](LICENSE)
