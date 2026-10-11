# Commands

`install.sh` links every command in `bin/` into `~/bin`. Each one prints its full usage with `--help`. Everything runs locally unless a section below says otherwise.

## Delivery

### agent-ship

The delivery gate: where a branch goes, what must pass first, and pushes that never force. [policy/DELIVERY.md](../policy/DELIVERY.md) has the full rules.

| Command | What it does |
|---|---|
| `agent-ship plan` | where the branch will be pushed, what runs first, and the profile's rules |
| `agent-ship topology` | remotes, which one is canonical and why, mirrors, drift, CI and release tooling |
| `agent-ship sync` | fetch every remote; fast-forward clean local base branches |
| `agent-ship ci` | secret scan, floor guard and project checks for HEAD; records the result against the commit |
| `agent-ship ci --learn` / `--set CMD...` / `--list` | learn, set or show the project's checks |
| `agent-ship floor` | the floor guard alone, read-only, on unpublished and uncommitted work |
| `agent-ship floor --stats` | how often each floor rule fired, was acknowledged or blocked |
| `agent-ship push` | push to the canonical remote; refuses without a passing `ci` for this exact commit |
| `agent-ship release` | release paths for this project type, and which ones need an explicit request |
| `agent-ship tidy [--apply]` | branches already merged, locally and on each remote |
| `agent-ship scorecard` | local CI pass rate, CI time and pushes per project |
| `agent-ship guard` | Claude Code PreToolUse hook (installed with `--with-hooks`) |
| `agent-ship prepush` | git pre-push hook (installed with `--with-git-hooks`) |

**Network:**

- `sync` and `push` talk to your git remotes.
- After a push to GitHub, a commit status is posted through `gh`. See [DELIVERY.md](../policy/DELIVERY.md) to turn it off.

### agent-review-route

```
agent-review-route "<original requirement>" [--range A..B | --base REF | --worktree]
```

Reads the whole change: commits since the merge-base, plus staged, unstaged and untracked files. It prints JSON naming at most three reviewers:

- a general reviewer;
- `agent-risk-reviewer`, when the diff touches auth, payments, secrets, crypto, privacy, schema or migrations, infrastructure, or webhooks;
- one specialist chosen by the shape of the change.

The general reviewer and most specialists are agents from Anthropic's `pr-review-toolkit` plugin. Install it from the official plugin marketplace, or use any general reviewer you prefer.

## Task records and memory

### agent-task

A durable record of one piece of work: request, checklist, events, proof and outcome. [policy/TASKS.md](../policy/TASKS.md) describes the lifecycle.

| Command | What it does |
|---|---|
| `agent-task start "REQUEST" [--new]` | open (or resume) a task for this repository; prints the id |
| `agent-task status [ID]` | the record, latest outcome, event and proof counts |
| `agent-task context [ID]` | a JSON working brief: checklist, git state, checks, past failures, events, proof |
| `agent-task event ID TYPE [--payload JSON]` | append an event |
| `agent-task proof metric ID before\|after NAME VALUE UNIT` | record a measurement |
| `agent-task proof artifact ID before\|after NAME PATH` | record a file as evidence |
| `agent-task proof capture ID [--checks] [--run CMD]` | run checks, compare evidence with the checklist; exits 1 if incomplete |
| `agent-task finish ID --outcome success\|partial\|failure` | capture proof and close the task |
| `agent-task handoff [ID]` | a Markdown brief another session can resume from |
| `agent-task fail search "ERROR"` | recorded fixes that share words with an error |
| `agent-task fail remember "ERROR" "FIX" [--failed]` | record what fixed an error, or what did not |

Data: `~/.agent-os/v2/db/agentos.sqlite` and `~/.agent-os/v2/tasks/<id>/`.

### agent-recall

```
agent-recall "<query>" [--k 5] [--kind lessons,decisions,improvements,memory,failures] [--json]
```

A full-text index (SQLite FTS5, BM25 ranking, recency-weighted) over:

- `~/.agent-os/LESSONS.md`, `DECISIONS.md` and `IMPROVEMENTS.md` (whichever exist);
- Claude Code memory files;
- `agent-task` failure records.

It prints pointers (`path:line`, heading, one-line abstract), not the full text.

`agent-recall index --aliases` is opt-in. It asks a Claude model for alternative phrasings of each entry, so search works with different words. This sends note text to the model, which is why it is off by default.

### agent-corrections

```
agent-corrections [--days 30] [--project SUBSTR] [--json]
```

Lists your messages in local Claude Code and Codex transcripts that look like corrections ("no, don't...", "I told you..."). Secret-looking strings are redacted. The `correct` skill uses this list to find mistakes that repeat.

### agent-session-distill

```
agent-session-distill [--hours 24] [--max 5] [--dry-run]
```

Finds tool failures in recent Claude Code transcripts that were later resolved, then stores each as `agent-task fail remember "<error>" "<fix>"`.

- **Model use:** it sends a short, redacted snippet per session to a Claude model through `claude -p`, with no tools. `--dry-run` shows the candidates without calling the model.
- **Storage:** no transcript text is stored.
- **When it runs:** only when you run it. Put it in cron if you want it daily.
- **Opt-out:** it does nothing when `~/.agent-os/mode` contains `guest`.

## Telemetry

Installed only with `install.sh --with-hooks`.

| Command | What it does |
|---|---|
| `agent-telemetry-hook` | Claude Code hook. Writes one small file per event to a private spool (`~/.agent-os/runtime/telemetry-spool`, mode 700). It never calls Python or the network on the hot path. |
| `agent-telemetry-ingest` | moves the spool into SQLite (`usage` and `sessions` tables); safe to run concurrently |
| `agent-usage skills\|agents\|mcp\|unused\|sessions [--days N] [--account LABEL]` | which skills, agents and MCP servers were actually used, and which installed skills never were |

What is recorded:

- skill, agent and MCP tool names;
- session ids, working directory, transcript path;
- stop counts and API error types;
- the account: the name of the Claude config dir the session ran in, without the dot (`claude`, `claude_second`).

Prompts, arguments and transcript text are never recorded. To pause recording, put `guest` in `~/.agent-os/mode`.

## Unattended work

### agent-overnight

```
agent-overnight add --repo PATH --done "CMD" [--base main] [--engine codex|claude] "GOAL"
agent-overnight run [--attempts 3] [--max N] [--detach]
agent-overnight brief | list | cancel | clean ID|--merged
```

A queue of coding tasks, each with a shell command that decides when it is done.

1. Every task gets its own worktree and an `overnight/<id>-<slug>` branch.
2. The check runs on the base branch first. If it already passes, the task is skipped.
3. The check runs again after every attempt. A passing attempt is committed on the task branch and, unless `--no-review` is given, read by a Claude reviewer.
4. Nothing is merged or pushed: pushes are disabled inside the run.
5. `brief` is the morning summary, with anything that needs your attention first.

The engine is Codex through `codex-ha`, or Claude Code with `--engine claude`. Claude calls try each config dir in turn (see [several accounts](how-it-works.md#several-claude-accounts)) when one is out of usage. State lives in `~/.agent-os/runtime/overnight/`.

## Skills

### agent-skill-lint

```
agent-skill-lint [<skill-dir>...] [--json] [--strict]
```

Deterministic checks for `SKILL.md` files. It never calls a model. It checks:

- frontmatter;
- whether the description says what the skill does and when to use it;
- body size and absolute paths;
- broken links to subfiles.

With no argument it lints every skill under `~/.agents/skills`. Exit code 1 means at least one error.

## Codex add-on

Optional. These need the [Codex CLI](https://github.com/openai/codex) and at least one `codex login`. [codex.md](codex.md) has the details.

| Command | What it does |
|---|---|
| `codex-ha ready` | exit 0 if a logged-in Codex account is available; exit 75 with the reason if not |
| `codex-ha status` | each account: ready, not logged in, or in cooldown until when |
| `codex-ha run "TASK"` | run `codex exec` in the current directory, failing over between accounts on quota errors |
| `agent-codex --detach --file BRIEF` / `--wait JOB` | start a `codex-ha run` in the background and wait for it; used by `agent-codex-worker` |
