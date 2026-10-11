---
name: create-verification-skill
description: Generates a project-local verify-<app> skill that drives the real product the way a user does and captures evidence, for web, mobile, desktop, CLI, services, embedded and data stacks. Use when a repo has no scripted way to prove behavior.
---

# Create a verification skill

An agent that can prove its own work does not need a human to check it, and only then is running several agents in parallel safe. This skill gives a repo that ability: a project-local `verify-<app>` skill that launches the product, drives it like a user, captures evidence, and cleans up. Write it for the next agent, who will read it cold in the middle of a task.

Adapted from pstack by Lauren Tan (MIT, see `LICENSE-pstack`).

## 1. Interview the repo, not the user

Answer from the code. Ask the user only what the repo cannot show (credentials, which physical board is attached, a paid service).

- **Surface:** what does a user touch? Web UI, mobile app, desktop app, CLI/TUI, API, network service, device firmware, library. Pick the primary surface and list the others.
- **Run:** the repo's own dev command (package scripts, Makefile, README). Ports, env vars, seed data, test users, auth.
- **Drive:** existing harnesses first (Playwright/XCUITest/integration_test/Espresso specs, expect scripts, Postman collections, HIL rigs). Only then pick a recipe from [references/recipes.md](references/recipes.md).
- **Observe:** what proves behavior here: screenshots, accessibility tree, terminal transcript, response bodies, packet capture, serial log, DB rows, files written, exit codes.
- **Isolate:** can two runs coexist (ports, data dirs, simulator/emulator per run, network namespace, one board)? If not, the skill must say so and refuse to drive an instance it did not start.
- **Danger:** list anything irreversible: flashing firmware, payments, emails/SMS, production APIs, deleting data. The skill must name the safe mode (sandbox keys, dry-run, emulator, simulator, mock boundary) and say that real-world side effects need the user's approval.

If the checkout does not build or start, fix that or report it precisely before generating. A skill written against a broken base teaches wrong steps.

## 2. Write the skill

Create `.agents/skills/verify-<app>/SKILL.md` in the repo, then link it for Claude Code: `mkdir -p .claude/skills && ln -s ../../.agents/skills/verify-<app> .claude/skills/verify-<app>`. Codex reads `.agents/skills`, Claude reads `.claude/skills`; one copy serves both.

Frontmatter: `name: verify-<app>` and a `description` naming the app, the surface, and when to use it. Then these sections, all filled with real commands from this repo (no placeholders):

- **Launch:** the exact start command and the ready signal (log line, port answering, prompt, device enumerated). Teardown command. For a short-lived CLI: build once, then one fresh PTY or tmux session per drive.
- **Doctor:** one read-only check that this instance is worth driving: our process, right build/version, port owned by us, device/simulator ID, auth valid. Run it before the first drive and after anything surprising.
- **Drive:** the harness recipe with real handles: accessibility labels, test IDs, routes, CLI prompts, endpoints, serial commands. Prefer stable handles over coordinates.
  Every mapped drive must check its own result: state the expected outcome (reply, element state, read-back, exit code) and fail on a mismatch. A drive that only sends input and prints output proves nothing; it reported `ok: true` while a broken `DEL` left the key in place.
- **Evidence:** what to capture and where (default `artifacts/verify/<feature>/<timestamp>/`, git-ignored). Proof standards: drive the real user path, not internal setters or test-only endpoints; capture the action and the resulting state; check side effects (files, rows, packets, messages, device state); mock only at a boundary production already isolates. Observe what a dry-run actually skips instead of trusting its name.
- **Cleanup:** stop only what this run started (by PID, container, simulator UDID, namespace), never by process name. Evidence survives cleanup.
- **Helpers:** if one-off scripts keep appearing, ship a small control CLI (`scripts/verify-<app>` or similar): few composable subcommands, `--help`, JSON output, actionable errors, `--dry-run` on anything destructive. A failed check returns the same JSON shape with `"ok": false` and the reason, and a nonzero exit; never a bare traceback. Make it executable and show its invocation in the skill.

## 3. Seed the feature map

Create `.agents/skills/verify-<app>/features/README.md` (index, baseline preconditions, driving conventions, proof rules) and one file per user-facing feature, starting with the top 3-5 (from routes, commands, screens, endpoints, device functions). Follow [references/feature-map-example/](references/feature-map-example/). Each feature file has an H1, one paragraph, then exactly these H2s:

1. `Sub-features`: short IDs, one line each.
2. `How to get to it (user POV)`: every entry point.
3. `Driving it with <harness>`: `Preconditions:`, then bullets pairing each user action with an exact command and the observable result.
4. `Gotchas`: traps that waste or invalidate a run.

No implementation details in the map: user paths, stable handles, required state, commands, observable proof.

## 4. Prove it before handing it over

Run the generated skill end to end once: launch, doctor, drive one mapped feature, capture evidence, clean up, then confirm the evidence still exists. Fix what fails and rerun cleanup after every failed attempt. Then prove it catches a break: change one line of product code so a mapped feature is wrong (skip a save, return the wrong reply), run that drive, confirm it fails with a clear reason, and restore the code (`git diff` must be empty for product files). A skill that passes on broken code is not done. A skill that was never executed is a draft. If the environment cannot run it (no simulator runtime, no board attached), say exactly which step is unproven.

## 5. Hand over

Report: the skill path, the surface and harness chosen, the features mapped, the proof run (commands and artifact paths), the break it caught, and anything unproven. Point at `maintain-verification-skill` to keep the map current.
