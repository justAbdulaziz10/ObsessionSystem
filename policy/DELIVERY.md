# AgentOS Delivery Reference

Full delivery rules (moved verbatim from GLOBAL.md on 2026-10-10; GLOBAL.md keeps the summary). Read when pushing, opening PRs, releasing, or debugging agent-ship.

## Delivery: pull, push, GitHub, GitLab

Use `agent-ship` (`plan` before shipping; `topology` explains it). It applies the user's rule below and checks freshly fetched evidence; don't decide from habit.

- **Pull:** `agent-ship sync` before starting work and before every push. It fetches all remotes and fast-forwards clean base branches only.
- **Where (user rule):** push to the GitHub remote. If the project also has a GitLab remote, push the same commit there too, for every branch, fast-forward only. A project with no GitLab remote gets GitHub only. `agent-ship push` does both, and PRs open on GitHub. This is set in `defaults` of `~/.agent-os/delivery/profiles.json`. Repos without a GitHub remote fall back to evidence: the remote the others are behind, or the mirror job's direction.
- **Never:** force-push to a base branch, push to a mirror before GitHub has the commit, or push to deploy remotes (heroku etc.), a fork's upstream or backups unless the user asks.
- **Stop for the user:** remotes diverged, local is behind canonical, or the push would need force.
- **CI gate:** run `agent-ship ci` on a clean commit before every push; `push` refuses without a pass for that exact commit.
  - It runs a secret scan of the commits being pushed (keys, tokens, `.env`, private keys), then the floor guard, then the project's checks.
  - Floor guard: only lines the change adds or removes count. It blocks new suppressions, skipped/focused/deleted tests, stripped assertions, lowered coverage thresholds, downgraded lint, strict flags turned off, `--no-verify`, weakened CI steps, and unimplemented stubs. A deliberate one needs `Floor-Guard-Ack: <rule>[@<path-glob>] <reason>` in a commit message of the range. Per-project `floor_guard`, `floor_ignore`, `floor_allow` in the profile, each with a "why". `agent-ship ci --help` has the details. `agent-ship floor --stats [--days N]` shows how often each rule fired, was acked (top reasons) or blocked; check it before loosening or tightening a rule.
  - The checks come from the profile, else from what was learned for the project, else from detection.
  - Checks that already failed when they were learned don't block until they pass once. After that they are required (ratchet). New failures always block.
  - A project with no known checks fails closed. Learn them with `agent-ship ci --learn`, or `--set CMD...` after reading the README and remote CI. Autopilot queues this for every project the user works in.
  - Remote CI is extra; compute limits never block shipping.
- **Release:** `plan` lists release paths by project type.
  - Test channels (TestFlight, Play internal, web preview) are part of shipping when the user asks to ship.
  - Production, App Store, package publishing, firmware flashing and registry pushes happen only when the user asks, and never with automatic release.
- **After merge:** `agent-ship tidy` lists merged branches on GitHub, GitLab and locally. `--apply` deletes them when the user wants a clean repo.
- **Measure:** `agent-ship scorecard` shows the CI pass rate, CI time and failed pushes per project. Report it instead of claiming quality.
- **New project:** a project with no remote, or not on GitHub, is flagged. Creating the GitHub (and GitLab) repo needs the user's OK.
- **Repo rules:** reviews, release targets and branch hygiene come from `~/.agent-os/delivery/profiles.json`, shown as `rule:` lines in `plan`. Follow them.
- **Who may push:** pushing, merging and releasing still need the user's request. Unattended workers (agent-overnight/autopilot) never push.
- **Enforcement (every repo, present and future):**
  - Claude's PreToolUse hook `agent-ship guard` blocks pushing to GitLab before GitHub has the commit, and forced base pushes.
  - A global git pre-push hook (`core.hooksPath` = `~/.agent-os/git-hooks`) applies the same two rules to every push from any tool (Codex, terminal, editors), including pushes to a URL. It also notes a missing local CI pass.
    - The base-branch rule covers a fork's upstream too; only deploy hosts are exempt.
    - Then it runs the repo's own hooks (every hook type, including server hooks in bare repos).
    - Only a rule violation blocks; if the tool is missing or broken, the push goes through.
    - A repo that sets its own `core.hooksPath` (husky, lefthook) skips it.
  - `git push --no-verify` is the deliberate, user-approved bypass. Agents never use it on their own.
  - Nothing is per-project: new repos get the rules, CI detection and autopilot `ci-learn` automatically.

