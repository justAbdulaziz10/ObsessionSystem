# Writing levers

Read when a skill, `AGENTS.md`, or `CLAUDE.md` pointer still behaves unpredictably after it passes lint: the agent fires it at the wrong time, rushes a step, or ignores a section. Condensed from mattpocock/skills `writing-for-agents` (MIT); see LICENSE-upstream.md.

## Context pointers and the two loads

A context pointer is anything in the agent's context that names out-of-context material and the condition for reaching it: a skill description, or an `AGENTS.md` line naming a doc. Its wording decides when the material is reached. A must-have target behind a weak pointer is a variance bug: sharpen the wording first, inline only if that fails.

- **Context load**: always-loaded text (descriptions, AGENTS.md lines) costs tokens and attention every turn whether or not it fires. Prune pointers harder than bodies.
- **Cognitive load**: the human remembering which user-only skills exist. Spend it where human judgement matters.

## Information hierarchy

1. In-file steps: what the agent does, in order.
2. In-file reference: rules and facts consulted on demand.
3. Disclosed reference: a separate file behind a pointer, loaded only when the pointer fires.

Inline what every branch needs; disclose what only some branches reach. Keep a concept's definition, rules, and caveats under one heading (co-location). A document that is simply too long (sprawl) thins attention even when every line is live.

## Completion criteria

- **Clarity**: the agent can tell done from not-done. A vague bound invites premature completion, especially when later steps are visible. Sharpen the bound first; hide later steps (split across a subagent or handoff) only if the rush persists.
- **Demand**: "every modified model accounted for" drives more legwork than "produce a change list". The strongest criteria are checkable and exhaustive.

## Leading words

A leading word is a compact concept already in the model's pretraining (_tight_ loop, _red_ test, _tracer bullet_). Repeated as a token, it anchors behaviour in the body and triggering in the pointer. Collapse restated triads into one such word. A word too weak to beat the default (_be thorough_) is a no-op; pick a stronger one (_relentless_).

State the target behaviour rather than the banned one: a prohibition makes the banned behaviour more available. Keep a prohibition only as a hard guardrail and pair it with the positive target.

## Pruning

- **Single source of truth**: each meaning lives in one place. Duplication inflates its apparent rank and costs maintenance.
- **Environment as source**: `package.json`, config files, `--help` output. A copy is a cache; cache only what the agent cannot find by looking (unwritten conventions, reasons, gotchas).
- **Relevance and sediment**: delete lines that never bear on the task or have gone stale. Adding feels safe and removing feels risky; prune anyway.
- **No-op test**: does this sentence change behaviour versus the model's default? If not, delete the whole sentence. Settle disagreements by running the document, not by debate.
