# Changelog

## 2.0.0 — 2026-10-11

A rewrite toward a smaller, accurate product. 1.0 was a copy of one person's machine setup; 2.0 keeps the parts that work for anyone and documents only what they actually do.

**Removed:** 20 commands that were author-specific, aliases, or broken outside the original machine: capability routing (`agent-cap`, `agent-intel`), model governance, the autopilot and its launchd services, the self-change/ADR machinery, `mcpall`, `agent-storage`, and others. Also removed: the 131-section manual, the autonomy policy, and three skills for maintaining the original setup.

**New:** `agent-task` replaces `agentos2`, its eight alias commands (`agent-v2`, `agent-fail`, `agent-handoff`, ...) and `agent-proof`. It is a single command for task records, proof and failure memory, and is 843 lines instead of 1,975.

**Changed**
- Rules: `policy/RULES.md` (about 60 lines, always loaded) replaces `GLOBAL.md`. `DELIVERY.md` and `TASKS.md` are read only when needed.
- Installer:
  - links skills one by one into `~/.claude/skills`, so an existing skills directory is no longer skipped;
  - adds a marked, removable import block to `~/.claude/CLAUDE.md`;
  - honours `CLAUDE_CONFIG_DIR`;
  - backs up before editing, and only when it changes something;
  - records everything it creates in `~/.agent-os/install-manifest.tsv`, and relinks after the checkout moves.
- Uninstaller: removes only what the manifest lists, plus the import block and the hooks it added. A `--copy` file you have since edited is kept and reported.
- `codex-ha`:
  - no hard-coded model; the Codex CLI's defaults apply unless configured;
  - `ready` and `status` check that the CLI exists and is logged in;
  - the MCP servers disabled for workers are configurable and empty by default.
- `agent-codex`: no longer runs cleanup commands as a side effect.
- `agent-review-route`: suggests only specialist skills that are installed.
- `agent-recall`: model-written aliases are off by default, because they send note text to a model.
- Docs: `agent-ship` now documents the GitHub commit status it posts after a push, and how to turn it off.
- The test harness clears `CLAUDE_CONFIG_DIR` and related variables, so the suites can't reach the real config.
- CI runs the suites on macOS and Ubuntu.

## 1.0.0 — 2026-10-11

First public release.

- 41 commands: delivery gate (`agent-ship`), durable tasks (`agent-v2`, `agent-handoff`), risk-routed review (`agent-review-route`), capability routing (`agent-cap`), Codex failover (`codex-ha`), proof records (`agent-proof`), memory (`agent-fail`, `agent-recall`), autopilot and overnight queues, governance (`agent-system-change`, `agent-doc-sync`), one MCP manifest across accounts (`mcpall`).
- Policy: global routing and budgets, task lifecycle, delivery, autonomy.
- 12 skills and 2 Claude Code subagents.
- Installer that only adds files, with opt-in hooks and background services, and a clean uninstaller.
- 194 regression checks, all passing on a fresh `$HOME` with Python 3.9; `evals/run-all.sh` runs them in one go.
- Fixed: a background GitHub status post passed arguments in an order only Python 3.12+ accepted.
- Fixed: `agent-ship` no longer hands zsh, fish or csh scripts to shellcheck, which can't parse them.
