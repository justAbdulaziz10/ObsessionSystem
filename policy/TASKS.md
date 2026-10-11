# Task records

Use `agent-task` for substantial work: several steps or files, delegated to workers, or likely to outlive one session or account. Skip it for questions and small edits.

A task is a row in a local SQLite database plus a folder of plain files under `~/.agent-os/v2/tasks/<id>/`. Nothing is sent anywhere. Treat the record, not your memory of the conversation, as the source of truth.

## Lifecycle

1. **Start or resume.** From the repository, run:

   ```
   agent-task start "<request>"
   ```

   It prints a task id. Running it again with the same request in the same repository returns the task that is still open. `--new` always opens a fresh one.
2. **Brief.** `agent-task context` compiles the request, a checklist, the git state, detected checks, matching past failures, recent events and proof into one JSON brief.
   - The checklist is a keyword heuristic: "fix" adds a reproduction step, "slow" adds before/after metrics, "auth" adds an independent review.
   - Edit `checklist.json` when the checklist is wrong.
3. **Log decisions** that a later session needs:

   ```
   agent-task event <id> decision --payload '{"why": "..."}'
   ```
4. **Attach evidence** as you produce it:

   ```
   agent-task proof metric   <id> before|after NAME VALUE UNIT
   agent-task proof artifact <id> before|after NAME PATH
   ```

   A metric is a number such as p95 latency or bundle size. An artifact is a screenshot, log or report file.
5. **Check the proof.** `agent-task proof capture <id> --checks` runs the detected checks, compares the evidence with the checklist and exits 1 if anything is missing. Add `--run "CMD"` to run a specific check.
6. **Finish, always, including on failure:**

   ```
   agent-task finish <id> --outcome success|partial|failure --checks
   ```

   Without an id, `status`, `context` and `handoff` pick the most recently updated open task in the repository, so a forgotten task gets in the way of the next one.

## Switching session or account

`agent-task handoff` writes `handoff.md` and prints it. It holds the request, branch and commit, the checklist, the proof recorded so far, the proof still missing, and recent events. The next session runs `agent-task context` or reads that file instead of rediscovering the work.

## Failure memory

- `agent-task fail search "<error>"` finds recorded fixes that share words with the error message.
- `agent-task fail remember "<error>" "<fix>"` records a fix once it is proven. Add `--failed` to record an approach that did not work.
- `agent-recall "<query>"` searches more widely: these records, `LESSONS.md`, `DECISIONS.md` and Claude Code memory files. It returns pointers; read only the entries it points to.
