# Skill mechanics

Read when choosing frontmatter keys, deciding model-invoked vs user-only, adding Codex metadata, or splitting one skill into two.

## Frontmatter keys

| Key | Host | Effect |
|---|---|---|
| `name` | all | Must equal the directory name. |
| `description` | all | The always-loaded pointer. Claude Code and Codex both list it. |
| `disable-model-invocation: true` | Claude Code | Only the user can run it (`/name`); the model and other skills cannot. Removes the description's routing role. |
| `user-invocable: false` | Claude Code | Hides it from the `/` menu; the model can still invoke it. Use for background reference skills. |
| `allowed-tools`, `argument-hint`, `model`, `effort`, `context`, `agent`, `paths`, `hooks` | Claude Code | Runtime controls. Codex ignores them. |
| `license` | all | SPDX id when the skill ships under its own license. |
| `metadata:` (map) | all | Free-form. `agent-skill-lint` treats `origin: home-grown` as a locally written skill. Codex reads `metadata.short-description`. |

Codex has no frontmatter equivalent of `disable-model-invocation`. Its control lives in `agents/openai.yaml`:

```yaml
interface:
  display_name: "Shared Smoke Test"
  short_description: "Check every account can see shared skills"
policy:
  allow_implicit_invocation: false
```

Claude Code users can also hide or demote any skill without editing it, through the `skillOverrides` setting (`on`, `name-only`, `user-invocable-only`, `off`). Prefer that for third-party skills you must not edit.

## YAML hazards

Claude Code drops every frontmatter field when the block fails to parse, then matches the skill on its body's first line. The common causes:

- An unquoted value containing `: ` (`description: Use when: …`). Quote it or use `>` folded style.
- ` #` inside an unquoted value: everything after it becomes a comment.
- A value starting with `` ` ``, `@`, `%`, `*`, `&`, `!`, `[`, or `{`.
- Tabs in indentation, duplicate keys, or an unclosed quote.

`agent-skill-lint` reports these as `frontmatter-yaml` / `frontmatter-comment`.

## Choosing invocation

Make a skill user-only when all of these hold:

- It only ever runs because a person typed its name (wizard, smoke test, scheduled audit, one-shot migration).
- No other skill, subagent, or unattended worker needs to reach it.
- Firing it unprompted would waste a turn or cause a side effect.

Keep it model-invoked when an agent must reach it on its own or when another skill composes it. A user-only skill that two others depend on cannot be reached by them; move that shared material to a plain file both point at.

## Splitting

- Split by **sequence** when later steps tempt the agent to rush the current one; the cut only helps across a real context boundary (a subagent or a handoff).
- Split by **invocation** when part of the skill has its own trigger word that should fire independently, or another skill must call just that part. Each split adds an always-loaded description, so the independent reach must be worth those characters.
- Router skill: when user-only skills pile up, one user-only skill can list them and when to reach for each.

## Duplicate registration

Claude Code scans `~/.claude/skills` (a symlink to `~/.agents/skills`) and treats a `.claude-plugin/` folder or `skills/<name>/SKILL.md` inside a skill directory as a plugin, so the same skill appears as both `name` and `name:name`. Upstream repos that ship both layouts must be installed as the plain `SKILL.md` layout only.
