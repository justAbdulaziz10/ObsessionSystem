---
name: maintain-verification-skill
description: Keep a project's verify-<app> skill and feature map honest as the app changes. One read-only source reader per feature, one live pass driving every feature, at most one commit of proven corrections. Use when asked to audit or refresh the verification skill, or on a daily schedule.
---

# Maintain a verification skill

A feature map goes stale as soon as the app changes. This is the upkeep loop for a skill made by `create-verification-skill` (or any project-local verification skill with a feature map). Cover every feature from source and drive every feature live at least once.

Adapted from pstack by Lauren Tan (MIT, see `LICENSE-pstack`).

## Outcome

End with exactly one, and say which:

- **clean:** every feature had source and live coverage; nothing to change.
- **changed:** one commit (or PR) of proven corrections to the verification skill.
- **blocked:** coverage could not finish or a fix could not be proven; name the blocker.

## Edit scope

Edit only the verification skill's own directory (SKILL.md, `features/`, its helper scripts). Never edit product code here. A behavior the map describes that the app no longer has is either map drift (fix the map) or a product regression (report it; do not hide it in docs).

## Pass

0. **Locate.** Find `.agents/skills/verify-*/` (or `.claude/skills/verify-*/`). Several: ask which. None: stop and point at `create-verification-skill`.
1. **Index hygiene.** Read `features/README.md`, list the feature files, fix missing, extra, duplicate, or dead entries.
2. **Source wave.** One read-only subagent per feature file, in parallel where the client allows it (otherwise sequentially). Each explains how the feature works from source, flags likely drift with file citations, and returns one live recipe. Readers never drive the app or edit files.
3. **Reconcile.** Every feature has a summary. Merge recipes into as few app states as practical. Spot-check cited drift. Look at recent commits for user-facing surfaces missing from the map; name a source path before calling one missing.
4. **Live pass.** Required even when the source looks clean. You drive; follow the skill's own Launch model. Hold three rules the whole time:
   - Run Doctor before the first drive and after any failed or surprising drive; reset or relaunch when Doctor cannot see the problem.
   - Evidence captured so far survives every cleanup; check it at its location.
   - Nothing a drive started outlives the run; clean failed-attempt residue too, but only what this run started.
   A Doctor failure caused by skill drift is drift: fix it in scope and retry once before calling the pass blocked. A feature counts as unreachable only with the concrete prerequisite (auth, entitlement, OS, hardware, external state) and the route tried.
5. **Triage.** Wrong description: fix the map. Working behavior the harness cannot drive: fix the harness and re-drive it live. Broken app behavior: report it to the user, outside this change.
6. **Ship or stop.** Changed: re-read every changed file, then one commit/PR. Clean or blocked: report coverage honestly, no commit.

Report: outcome, features covered live, unreachable features with prerequisites, drift fixed, product regressions found, artifact paths.
