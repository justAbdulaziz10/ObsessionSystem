---
name: agentos-system-governance
description: Governs changes to the machine-wide AgentOS environment itself. Use when auditing, debugging, or changing AgentOS models, routing, skills, plugins, MCPs, permissions, account failover, task state, context engineering, evals, telemetry, or storage, even for a one-line policy edit.
metadata:
  origin: home-grown
---

# AgentOS System Governance

When the task involves AgentOS itself, the canonical source is:

`~/.agent-os/SYSTEM.md`

Always inspect:

1. `~/.agent-os/SYSTEM.md`
2. `~/.agent-os/STATE.md`
3. relevant `DECISIONS.md`
4. relevant `LESSONS.md`
5. relevant `IMPROVEMENTS.md`
6. actual executable configuration

Do not modify AgentOS from memory alone.

## Change Protocol

Start a meaningful change with:

`agent-system-change begin "<goal>"`

Make the smallest sufficient reversible change.

Validate:

- syntax
- executable behavior
- relevant evals/checks
- no obvious account/auth regression
- no accidental secret exposure

Complete with:

`agent-system-change finish <id> "<summary>" --evidence "<evidence>"`

Use `--decision` for architectural decisions.

Use `--lesson` for durable established lessons.

Use `--improvement` for promising but unproven hypotheses.

Finally run:

`agent-doc-sync`

## Self-Improvement Rule

AgentOS is expected to improve.

Do not blindly self-mutate.

Prefer:

observe → measure → hypothesize → experiment → verify → promote → document.

Always consider whether removing an unnecessary layer is better than adding another one.
