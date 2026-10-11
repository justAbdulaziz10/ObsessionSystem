# Delivery

Read this before pushing, opening a pull request, releasing, or debugging `agent-ship`. `agent-ship --help` and `agent-ship ci --help` give the exact flags.

## The sequence

1. `agent-ship sync` before you start and again before you push. It fetches every remote and fast-forwards clean local base branches (main, master, develop, development, trunk). It never rebases or merges your work.
2. `agent-ship plan` shows where the branch will go and what runs first. Read its `rule:` lines; they come from the delivery profile and you follow them.
3. Commit everything. `agent-ship ci` refuses to run on a dirty tree, because it must test exactly the commit that is pushed.
4. `agent-ship ci` runs the local gate for HEAD (see below) and records the result against the commit SHA.
5. `agent-ship push` refuses unless there is a passing `ci` record for that exact commit. `--no-ci REASON` skips the check and logs the reason; use it only when the user agrees.

Pushing, merging and releasing happen only when the user asks. Unattended runs never push.

After a push to GitHub, `agent-ship` posts the recorded local CI result as a commit status named `agent-ship/local-ci`, so pull requests show it. The status holds only pass/fail counts, never check output. This needs the `gh` CLI. To turn it off, set `"report_status": false` in the profile or `AGENT_SHIP_NO_STATUS=1` in the environment.

## Where pushes go

A repository can have several remotes. The canonical remote is the one commits land on first; a mirror is a copy of the same repository on another host, such as a GitLab copy of a GitHub project. `agent-ship topology` explains its decision. It chooses the canonical remote in this order:

1. `canonical` set in the matching delivery profile.
2. A remote on `canonical_host` (the default profile sets `github`).
3. The only remote.
4. The remote the others are behind on base branches.
5. The source of a mirror job found in the repository's CI files.

`agent-ship push` pushes to the canonical remote. It pushes a mirror only to fast-forward a base branch to exactly the canonical commit, or for every branch when the profile sets `mirror_all_branches`. It never force-pushes.

Stop and ask the user when:

- remotes have diverged;
- your branch is behind the canonical remote;
- the push would need force;
- the project has no remote yet. Creating a repository on a host needs the user's OK.

## The CI gate

`agent-ship ci` runs three stages in order. Any failure blocks the push.

1. **Secret scan** of the commits being pushed:
   - known key and token patterns in added lines;
   - committed `.env` files and private keys;
   - `gitleaks` too, when it is installed.

   A line containing `agent-ship: allow-secret` is skipped; use it only for test fixtures.
2. **Floor guard.** It reads only the lines the change adds or removes, and blocks a change that lowers the bar:

   | Rule | Catches |
   |---|---|
   | `suppression` | new lint or type suppressions (`noqa`, `eslint-disable`, `@ts-ignore`, `swiftlint:disable`, ...) |
   | `skip-test`, `focus-test` | skipped or focused tests |
   | `test-deleted`, `assert-removed` | deleted test files, removed assertions |
   | `threshold-lowered` | lowered coverage thresholds |
   | `lint-downgraded`, `strict-off` | lint rules downgraded, strict compiler flags turned off |
   | `no-verify` | `--no-verify` added to scripts |
   | `ci-weakened` | CI steps removed or allowed to fail |
   | `stub` | unimplemented stubs (`TODO: implement`, `NotImplementedError`, `fatalError("unimplemented")`, ...) |

   A deliberate exception needs a trailer in a commit message of the pushed range:

   ```
   Floor-Guard-Ack: skip-test@test/net/* upstream API is down, tracked in #123
   ```

   The format is `Floor-Guard-Ack: <rule>[,<rule>...][@<path-glob>] <reason>`. `agent-ship floor` runs the guard alone and is read-only, so you can check before committing. `agent-ship floor --stats` shows how often each rule fired, was acknowledged or blocked; look at it before arguing that a rule should change.
3. **Project checks.** They come from the first source that has any:
   1. `checks` in the delivery profile;
   2. checks learned for this repository (`~/.agent-os/delivery/learned/`);
   3. detection: package.json scripts, Makefile targets, pytest and ruff, cargo, go, Gradle, `swift test`, Flutter and Dart.

   - **No checks:** a project with no known checks fails closed. Run `agent-ship ci --learn` to try every detected check and remember the ones that work. Use `agent-ship ci --set "CMD" ...` once you have read the README and the remote CI config.
   - **Ratchet:** a check that was already failing when it was learned does not block until it passes once. After that it is required.
   - **New failures** always block.

Remote CI is a second opinion. A remote CI quota or outage never blocks a local ship.

## Enforcement outside agent-ship

- **Claude Code hook** (`agent-ship guard`, installed with `--with-hooks`): blocks force-pushes or deletes of a base branch and pushes to a mirror ahead of the canonical remote. Setting `AGENT_SHIP_GUARD=off` disables it for one command.
- **Global git pre-push hook** (installed with `--with-git-hooks`):
  - Applies the same two rules to pushes from any tool: the terminal, Codex, editors.
  - Prints a note when there is no passing local `ci` record. The note does not block.
  - Then runs the repository's own hooks.
  - Allows the push if `agent-ship` itself is missing or broken.
  - Does not apply to a repository that sets its own `core.hooksPath` (husky, lefthook).
- **`git push --no-verify`** bypasses the git hook. Agents use it only when the user explicitly asks.

## Delivery profiles

`~/.agent-os/delivery/profiles.json` holds per-repository rules. A profile matches on a remote slug (`owner/name`), the checkout path or the directory name. Keys:

| Key | Meaning |
|---|---|
| `match` | list of globs to match against |
| `rules` | free-text rules shown in `plan` as `rule:` lines |
| `canonical`, `canonical_host` | force the canonical remote or host |
| `mirror_all_branches` | push every branch to mirrors, not just base branches |
| `checks` | the project's check commands |
| `floor_guard` | set to `false` to turn the floor guard off |
| `floor_ignore` | path globs the floor guard skips |
| `floor_allow` | regexes for an agreed idiom the floor guard accepts |
| `report_status` | set to `false` to stop posting the local CI result to GitHub |
| `why` | where the rule came from; recommended, so the next agent knows whether it still applies |

## Releases and housekeeping

- `agent-ship release` lists release paths by project type.
  - Test channels (TestFlight, Play internal testing, preview deploys) are part of shipping when the user asks to ship.
  - Production deploys, App Store submission, package publishing and firmware flashing happen only on an explicit request.
- `agent-ship tidy` lists branches already merged, locally and on each remote. `--apply` deletes them when the user wants that.
- `agent-ship scorecard` shows each project's local CI pass rate, CI time and push count. Report it instead of making general claims about quality.
