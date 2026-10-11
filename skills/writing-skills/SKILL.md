---
name: writing-skills
description: Writes and reviews agent skills (SKILL.md) to a consistent standard for descriptions, lean bodies, invocation, layout, and provenance. Use when creating, editing, splitting, or reviewing a skill, even for a one-line description change, or when a skill fires at the wrong time or never.
---

# Writing skills

A skill is two things: a **description** that sits in every session's context and decides when the skill fires, and a **body** read only after it fires. Write both for a reader that already knows everything general: spend words only on what changes its behaviour.

## Steps

1. **Find the gap.** Search `~/.agents/skills` and plugin skills for overlap by reading their descriptions. Edit the overlapping skill instead of adding a neighbour.
   Done when: you can name the one case no installed skill covers, and you have chosen model-invoked or user-only (see Invocation).
2. **Write the description** by the rules below.
   Done when: `agent-skill-lint <dir>` reports no `desc-*` or `frontmatter-*` finding.
3. **Write the body**: ordered steps, each ending in a checkable **Done when** line; reference material that only some runs need goes to `references/<topic>.md` behind a pointer that says when to read it.
   Done when: the body is under 150 lines and every step has a pass/fail completion line.
4. **Add the sections the skill type needs** (see Sections by type).
   Done when: each applicable section exists, and none of the rest do.
5. **Install one layout** (see Layout and provenance).
   Done when: lint shows no `nested-plugin-layout`, `ref-*`, `abs-user-path`, or `provenance-missing` finding.
6. **Prove it routes.** Write at least 3 prompts in the user's own words (never copied from the description) and 2 that belong to neighbouring skills. Try each in a fresh session.
   Done when: every positive prompt loads the skill and no negative does. A miss means the description lacks the user's words: fix the description, not the prompt.

## Description rules

The description is a context pointer: its wording, not the body, decides whether the body is ever read.

- Shape: `<What it does, third person>. Use when <case>; when <case>.` One trigger per distinct case; synonyms of one case collapse into one.
- Name the edge case the model would otherwise handle alone, e.g. "even when the diff is pasted inline". One such clause is often the difference between a skill that fires and one that never does.
- State the outcome and the triggers. A step list in the description ("Ground, design, implement, verify …") gets executed in place of the body.
- Front-load the words users actually type: tool names, error strings, file types, slash commands.
- Target 300 characters or fewer; over 500 is a hard warning; 1024 is the host limit. Every character is paid in every session.
- Quote any value that contains `: ` or ` #`. Frontmatter that fails YAML parsing still loads, with every field dropped and the description replaced by the body's first line.

Before: `Fetch current library documentation with Context7 MCP tools.` (a topic label; never says when)
After: `Fetches the latest docs for libraries, frameworks, SDKs, and CLIs through the Context7 MCP. Use when an answer depends on a specific library's API, configuration, version, or migration, even for well-known ones like React or Next.js.`

## Body rules

- Lean: under 150 lines; push what only some branches need into `references/`, one level deep, each pointer naming when to read it.
- Every step ends on a checkable completion line ("Done when: the test fails before the fix and passes after"), never on "understanding reached".
- Phrase the target behaviour ("write one-line comments"). Keep a prohibition only for a hard guardrail, paired with the positive target.
- Delete no-ops sentence by sentence: an instruction the model already follows by default ("be careful", "write clean code") costs tokens and changes nothing.
- Point at the environment instead of copying it: `--help`, config files, and scripts are the source of truth; restated facts go stale (lint flags lines that call an old OS or Swift release the latest or the default).
- Compose explicitly: "Call the Skill tool with `diagnosing-bugs`", not "debug it properly".
- Use `~` or `$HOME` in paths; absolute `/Users/<name>/` paths break on other accounts.

## Sections by type

- **Interactive skills** (ask the user questions, wait for approval, open a browser for the user): add `## Loading constraints` stating what happens when no human is present (agent-overnight, `claude -p`, Codex exec). Example: "Non-interactive: take the recommended answer for each question, record the assumptions in the spec, and stop before any external side effect."
- **Discipline skills** (TDD, verification, review, root-cause debugging; anything an agent is tempted to skip): add `## Common rationalizations` (excuse | reality table) and `## Red flags` (observable signs the skill is being skipped).
- **Workflow skills**: end with a `## Verification` checklist where each item names its evidence (command output, screenshot, diff).

A copyable skeleton with all sections is in [references/anatomy-template.md](references/anatomy-template.md).

## Invocation

- **Model-invoked** (default): keep a trigger-rich description. Pay its characters in every session in exchange for the agent finding it on its own, or another skill calling it.
- **User-only**: set `disable-model-invocation: true` (supported by Claude Code). The description then becomes a one-line human summary with no trigger list. For Codex, also add `agents/openai.yaml` with `policy: allow_implicit_invocation: false`. Use this for setup wizards, smoke tests, destructive one-shots, and scheduled maintenance the user types by name.
- A skill that another skill or an autonomous worker must call stays model-invoked.

Frontmatter keys, `user-invocable`, Codex `openai.yaml` fields, and splitting decisions are in [references/skill-mechanics.md](references/skill-mechanics.md).

## Layout and provenance

```
<name>/SKILL.md            # name: <name>, matching the directory
<name>/references/*.md     # every file referenced from SKILL.md or another reference
<name>/scripts/            # runnable helpers; output is cheaper than inline code
<name>/assets/             # templates, images
<name>/agents/openai.yaml  # Codex display name and invocation policy (optional)
```

- One layout per skill directory. A `.claude-plugin/` folder or a nested `skills/<name>/SKILL.md` inside `~/.agents/skills/<name>` registers the skill a second time as `<name>:<name>`.
- Third-party skill: keep its license next to it and record where it came from (repository, exact commit SHA). If you keep a catalog in `~/.agents/skill-sources.json`, `agent-skill-lint` checks it.
- Home-grown skill: add `metadata:` with `origin: home-grown` to the frontmatter.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "The description needs the workflow so the agent knows what to do." | The body loads when the skill fires; a workflow in the description gets followed instead of the body. |
| "Longer descriptions trigger more reliably." | Distinct trigger words do. Repeated synonyms cost every session and blur neighbouring skills. |
| "It is only a description tweak; no eval needed." | Description edits are routing changes. Run lint and `run-triggers.sh`. |
| "I'll explain the background so the agent understands." | The agent knows the background. Write only what changes behaviour here. |

## Red flags

- The description lists steps, or opens with "This skill …".
- A step ends without a "Done when" line.
- The body restates a tool's `--help`, or names "the latest" version of anything.
- A new skill scores above 0.5 similarity with an existing one and neither was edited.

## Sources

Adapted from mattpocock/skills `writing-for-agents` (MIT, 49dd158), the addyosmani/agent-skills skill-anatomy doc and Tier-2 evals (MIT, 1401c8b), and the tigerless-labs/autoharness `validate.py` lint rules (MIT, 9eec623). Notices: [LICENSE-upstream.md](LICENSE-upstream.md). Longer authoring theory (context pointers, information hierarchy, leading words, pruning): [references/writing-levers.md](references/writing-levers.md).
