---
name: requirements-grilling
description: Turns a vague feature request into a short spec with checkable acceptance criteria. Use when asked to build or add a feature, screen, flow, or tool whose users, scope, or definition of done are unstated. Skip for bug fixes and fully specified changes.
---

# Requirements grilling

Reach checkable acceptance criteria before writing code. Facts are yours to look up; decisions are the user's to make.

## 1. Frame the request

Fill these slots from the request and the repo: outcome, user, success check, binding constraint, out of scope. Mark each unfilled slot open.

Done when every slot is filled or marked open. If none are open, go to Output.

## 2. Look up facts first

For each open slot, check whether a fact settles it: code, config, docs, existing screens, the issue or ticket, the repo's feature map or `verify-<app>` skill. Use tools directly, or an Explore subagent for broad searches. Ask the user only for decisions.

Done when every remaining open item is a decision only the user can make.

## 3. Ask in rounds

Treat open decisions as a tree. A decision is askable when the decisions it depends on are settled. Each round, ask every askable question at once, numbered:

```
**Q1 - <title>**: <question; list options when useful>
Recommended: <answer> (confidence: high | medium | low - <one-line reason>)
```

- Word each question so "yes" accepts the recommendation.
- Hold a question for a later round when its answer depends on another open question.
- While a lookup is still running, ask the questions that do not depend on it.
- Read "whatever you think" as accepting the recommendation, and say so in the next round.
- Each answer can open new questions; recompute the askable set before the next round.

Done when the user has answered every question in the round.

## 4. Stop

Stop asking when each acceptance criterion names a check (command, test, or observable UI/API result) and nothing load-bearing rests on an unstated assumption. After three rounds with criteria still uncheckable, say what is still missing and ask whether to narrow the scope.

Done when every criterion has a check.

## Non-interactive runs

In `agent-overnight`, Codex workers, `claude -p`, or CI, ask nothing:

- Adopt high-confidence recommendations as decisions.
- Record medium- and low-confidence ones as assumptions or blockers in the task notes, report, or PR description.
- When a blocker gates the core behaviour, record it and stop before building.

Done when every open decision is written down as adopted, assumed, or blocked.

## Output

A spec of at most 25 lines:

```
Goal:          <one line>
User:          <who benefits>
In scope:      <bullets>
Out of scope:  <bullets>
Decisions:     Q1 -> <answer> (user | recommended | looked up)
Assumptions:   <adopted without confirmation>
Blockers:      <open, with who can resolve>
Acceptance checks:
- [ ] <behaviour> - check: <command, test, or UI step> -> <expected result>
```

Interactive: wait for the user's go before building. Then hand off: a single change goes to `agent-work-loop`; work with several slices goes to `agent-team-lead`.

Done when the user has confirmed the spec (interactive) or it is saved with the task (non-interactive).

Source: adapted from mattpocock/skills `grilling` and addyosmani/agent-skills `interview-me` (MIT, see `LICENSE-mattpocock`, `LICENSE-addyosmani`).
