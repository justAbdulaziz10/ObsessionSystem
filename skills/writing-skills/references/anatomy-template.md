# SKILL.md skeleton

Read when starting a new skill. Delete every section the skill type does not need (see "Sections by type" in SKILL.md).

```markdown
---
name: <dir-name>
description: <Does X for Y, third person>. Use when <case 1>; when <case 2>, even <edge case the model would otherwise handle alone>.
metadata:
  origin: home-grown
---

# <Title>

<One or two sentences: what this skill changes about the agent's default behaviour.>

## Loading constraints            <!-- interactive skills only -->

- Interactive: <what the agent asks, and in what batch size>.
- Non-interactive (agent-overnight, `claude -p`, Codex exec): <default it takes, where it records assumptions, which side effects it stops before>.

## Steps

1. <Action>.
   Done when: <observable, pass/fail condition>.
2. <Action>. For <branch only some runs reach>, read [references/<topic>.md](references/<topic>.md).
   Done when: <condition>.
3. Call the Skill tool with `<other-skill>` to <sub-task>.
   Done when: <condition>.

## Common rationalizations         <!-- discipline skills only -->

| Excuse | Reality |
|---|---|
| "<what an agent says to skip a step>" | <why it is wrong, with the cost> |

## Red flags                       <!-- discipline skills only -->

- <observable sign the skill is being skipped>

## Verification

- [ ] <check> — evidence: <command output / screenshot / diff>
```

