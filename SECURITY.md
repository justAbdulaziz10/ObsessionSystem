# Security policy

ObsessionSystem runs on your machine with your permissions, installs git hooks and Claude Code hooks, and gates pushes. Security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through GitHub:
[Security → Report a vulnerability](https://github.com/justAbdulaziz10/ObsessionSystem/security/advisories/new).

Include what you found, how to reproduce it, and what an attacker could do with it. This is a personal open-source project, so reports are handled on a best-effort basis, but confirmed issues are fixed before anything else. Credit is given in the advisory unless you prefer otherwise.

## In scope

- A secret, token or private data that slips past the `agent-ship` secret scan or the telemetry redaction
- A way to bypass the floor guard or the pre-push guard without `--no-verify` or an explicit acknowledgement
- The installer or uninstaller overwriting or deleting user files it didn't create
- Telemetry or task state written with permissive file modes, or sent anywhere off the machine
- Command injection through task text, branch names, repo names or hook input

## Out of scope

- Behavior of Claude Code, Codex, or third-party plugins and MCP servers themselves
- Deliberate bypasses the docs describe as human escape hatches (`git push --no-verify`)
- The fake credentials in `evals/` fixtures; they exist to prove the scanners work
