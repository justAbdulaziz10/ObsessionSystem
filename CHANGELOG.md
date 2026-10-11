# Changelog

## 1.0.0 — 2026-10-11

First public release.

- 41 commands: delivery gate (`agent-ship`), durable tasks (`agent-v2`, `agent-handoff`), risk-routed review (`agent-review-route`), capability routing (`agent-cap`), Codex failover (`codex-ha`), proof records (`agent-proof`), memory (`agent-fail`, `agent-recall`), autopilot and overnight queues, governance (`agent-system-change`, `agent-doc-sync`), one MCP manifest across accounts (`mcpall`).
- Policy: global routing and budgets, task lifecycle, delivery, autonomy.
- 12 skills and 2 Claude Code subagents.
- Installer that only adds files, with opt-in hooks and background services, and a clean uninstaller.
- 194 regression checks, all passing on a fresh `$HOME` with Python 3.9; `evals/run-all.sh` runs them in one go.
- Fixed: a background GitHub status post passed arguments in an order only Python 3.12+ accepted.
- Fixed: `agent-ship` no longer hands zsh, fish or csh scripts to shellcheck, which can't parse them.
