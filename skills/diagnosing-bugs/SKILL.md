---
name: diagnosing-bugs
description: Finds the root cause of a bug or performance regression and proves the fix with a command that fails before it and passes after. Use when something is broken, throws, or gives wrong output; when a test or CI job fails for an unclear reason; when behaviour is flaky; or when something got slower.
---

# Diagnosing bugs

Find the cause before changing source. Each phase ends with a check you can run. Stack-specific commands are in `references/stack-repros.md`.

Rules for every phase:

- Edit only the repro, tests, and tagged debug logs until Phase 4 confirms a cause.
- Change one variable at a time.
- Keep credentials in env vars and write `<REDACTED>` in any output you show.
- Label claims measured (you ran it), inferred, or guessed.

## Phase 1: Build a failing repro command

This phase is the skill. With one command that goes red on this bug, the rest is mechanical. Try, roughly in order:

1. A failing test at the seam that reaches the bug (unit, widget/integration, e2e).
2. An HTTP call or script against a local dev server.
3. A CLI run on a fixture input, diffed against known-good output.
4. A headless UI script (Playwright, Flutter integration test, XCUITest, Android instrumented test), or the repo's `verify-<app>` skill when it scripts the flow.
5. A replay of a captured payload, log, or trace through the code path.
6. A throwaway harness: one function call with mocked dependencies.
7. A property/fuzz loop over many inputs, for "sometimes wrong".
8. `git bisect run <cmd>` between a known-good and a known-bad state.
9. A differential run: the same input through old and new versions or configs, outputs diffed.

Then tighten it: make it faster (narrow scope, skip unrelated setup), sharper (assert the exact symptom, not "no crash"), and deterministic (pin time, seed RNG, isolate filesystem and network). For a flaky bug, raise the failure rate (loop 50-100x, parallelise, add load or sleeps) and record the rate.

Done when you have run the command at least once and shown the invocation and its output, and it:

- fails with the reported symptom, not a nearby error, setup failure, or compile error;
- gives the same verdict on repeat runs (flaky: a recorded, debuggable failure rate);
- runs unattended in seconds, at most a few minutes.

### When no repro can be built

Stop. List what you tried.

- Interactive: ask the user for access to the environment that reproduces it, a redacted artifact (log, HAR, crash report, timestamped screen recording), or permission to add temporary instrumentation.
- Non-interactive (autopilot, `agent-overnight`, Codex worker, CI): record the blocker in the task notes or report (what you tried, what would unblock it) and end the task as blocked. Leave source unchanged.

Done when the blocker is recorded. A fix without a repro is a guess; ship none.

## Phase 2: Minimise

Cut inputs, steps, config, and data one at a time, rerunning after each cut. Keep what keeps it failing.

Done when removing any remaining element makes the command pass.

## Phase 3: Rank hypotheses

Write 3-5 ranked hypotheses before testing any. Each states a prediction:

> If <X> is the cause, then changing <Y> makes the repro pass (or changing <Z> makes it worse).

Discard any hypothesis without a prediction. Interactive: show the list to the user and keep working on your ranking while they read.

Done when 3-5 hypotheses each carry a falsifiable prediction.

## Phase 4: Instrument

Test hypotheses in rank order. Prefer a debugger or REPL breakpoint; next, targeted logs at the boundaries that separate hypotheses.

Pick one tag for the session (for example `[DEBUG-a4f2]`) and put it in every temporary log line. For performance, measure a baseline first (timer, profiler, query plan, trace), then bisect; logs mislead on timing.

Done when one hypothesis's prediction held, the others failed, and the evidence is shown.

## Phase 5: Fix the root cause

1. If a seam exists that exercises the real call pattern, turn the minimised repro into a regression test and watch it fail. If none exists, note the missing seam in the report.
2. Fix the cause. Catch-and-ignore, retries that hide the error, and special cases for the repro input are symptom fixes.
3. Rerun the minimised repro and the original Phase 1 command.
4. Run the project's checks (tests, lint, analyze/typecheck, build). For a runtime app, drive the affected flow with the repo's `verify-<app>` skill (`.agents/skills/verify-*` or `.claude/skills/verify-*`) when one exists.

Done when the repro failed before the fix and passes after (both outputs shown) and the project's checks pass.

## Phase 6: Clean up

- Remove every tagged log line, then search for the tag: `git grep -n "DEBUG-a4f2"` (or `grep -rn` outside git).
- Delete throwaway harnesses, or keep them as the regression test.
- Put the confirmed hypothesis in the commit message or report.

Done when the tag search finds nothing and `git status` lists only intended files.

## Report

Repro command; failing output before; passing output after; confirmed cause; fix; checks run with results; regression test or missing seam; remaining risk.

Source: adapted from mattpocock/skills `diagnosing-bugs` (MIT, see `LICENSE-mattpocock`).
