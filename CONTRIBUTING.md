# Contributing

Thanks for helping. ObsessionSystem holds contributions to the same bar it holds agents to: **a change is done when a pass/fail check says so**, and a change to the system is better only if the evidence says it is.

## Setup

```bash
git clone https://github.com/justAbdulaziz10/ObsessionSystem.git
cd ObsessionSystem
evals/run-all.sh          # installs into a throwaway $HOME and runs every suite
```

`run-all.sh` never touches your real home, repos or remotes. It takes a few minutes and must pass before a PR merges. CI runs it on macOS and Ubuntu.

## What makes a good PR

- **One concern per PR.** A bug fix, a new check, a new command. Not all three.
- **A regression check for new behavior.** Add a case to the matching suite in `evals/`. Bugs get a case that fails before the fix and passes after.
- **Evidence for heuristics.** Changes to review routing, check detection or floor-guard rules need cases that show the old and new behavior.
- **Meet the floor, don't lower it.** No skipped or deleted tests, stripped assertions, new lint suppressions or loosened CI. The floor guard in `agent-ship` blocks these; if one is truly deliberate, explain it in the PR.
- **Keep it small.** Deleting dead weight counts as an improvement. A new dependency needs a reason.

## Conventions

- Commands live in `bin/` as single-file Python 3.9+ or POSIX/zsh scripts, standard library only.
- Paths come from `$HOME` (`~/.agent-os`, `~/bin`, `~/.agents/skills`). Never hard-code a user, machine or project name.
- Skills follow `skills/writing-skills` and must pass `agent-skill-lint`. Adapted third-party work keeps its license file next to the skill.
- `policy/RULES.md` is loaded into every session, so every line costs context. Detail belongs in `DELIVERY.md`, `TASKS.md` or `docs/`.
- Docs describe what the code does today. If you change behavior, change the doc in the same PR.

## Good first contributions

- More check detection in `agent-ship` (languages and build tools it doesn't recognize yet)
- Floor-guard patterns for test frameworks it doesn't cover
- Clearer error messages wherever a command fails without saying what to do next

## Privacy

Before you push, check that your diff and any pasted output contain no tokens, emails, private repo names or personal file paths. CI runs `gitleaks` on every push and PR.

By contributing you agree your work is released under the [MIT License](LICENSE) and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
