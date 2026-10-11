# cap-router eval

Scores `agent-cap recommend` on domain, skills, and MCPs (3 points per case).

    python3 run.py [cases.json|holdout.json|holdout2.json] [agent-cap-command]

- `cases.json`: tuning set.
- `holdout.json`: written before the 2026-10-08 rewrite. Skill/MCP ranking was not tuned on it, but the domain word lists were written after seeing it.
- `holdout2.json`: written after the rewrite and scored blind once (17/24), then two general fixes (service-name aliases, removing generic hints) gave 19/24.

2026-10-08: old ranker 11/24, 19/36, 15/24 (45/84). New ranker 19/24, 32/36, 19/24 (70/84).
When tuning again, add a fresh blind set first and report its score before any change.

## Trigger & collision tier (skill descriptions)

    ./run-triggers.sh [--compare triggers-baseline.json] [--threshold 0.5] [--plugins] [--json]

Deterministic TF-IDF approximation of skill routing over every `~/.agents/skills/*/SKILL.md`
description (user-only skills with `disable-model-invocation: true` are left out). Approach
reimplemented from addyosmani/agent-skills evals Tier 2 (MIT, 1401c8b).

- Collision: cosine between every pair of descriptions; pairs >= 0.5 are routing hot spots (>= 0.75 HIGH).
- Self-rank: each `skill-triggers/<skill>.json` (`{"skill","positive":[...],"negative":[...]}`, a negative may be
  `{"prompt","owner"}`) ranks all descriptions per prompt. Reports hit@1 / hit@3 on positives and the
  false-fire rate (skill ranks #1 on a negative). Write prompts in user words, never copied from the description;
  a miss means the description lacks the vocabulary, so fix the description.
- `triggers-baseline.json`: accepted state to compare against. `triggers-pre-20261010.json`: before the
  2026-10-10 home-grown description pass.
- Lexical only: it rewards shared words and penalises longer descriptions. Use it to catch regressions and
  collisions, not to tune wording to the prompts. Lint first: `agent-skill-lint --all`.

2026-10-10, 14 cases (48 positives, 46 negatives, 123 routable skills): top1 58.3%, top3 68.8%, false-fire 2.2%,
7 pairs >= 0.5 (1 HIGH: liquid-glass / swiftui-liquid-glass), identical before and after the home-grown description
pass. Adding writing-skills.json (15 cases): top1 61.5%, top3 71.2%, false-fire 2.0% (saved as the baseline).
Cap-router run.py unchanged at 19/24, 32/36, 19/24 before and after.

2026-10-10 (change 20261010-211517-d82fd4): added apple-hig, swiftui-iphone-duo, swiftpieces, seo-growth-loop
(+4 case files, cases written before descriptions were trimmed). 19 cases, 66 positives: top1 60.6%, top3 72.7%,
false-fire 3.4% (seo-growth-loop fires on "make the pricing page load faster"); collisions unchanged (7, 1 HIGH).
Every pre-existing skill scores identically with and without the four new skills (snapshot run). archify top1 3→1
predates this change (it appeared once the 124th skill landed). Previous baseline: triggers-pre-d82fd4.json.
Cap-router run.py unchanged at 19/24, 32/36, 19/24. `agent-cap recommend` after `refresh` routes Duo and HIG
prompts to the new skills but still sends "swipeable card stack in SwiftUI" to swiftui-liquid-glass and an SEO
keyword prompt to privacy-legal-pages (name-token bonus); not tuned here, needs a blind set first.

2026-10-10 (change 20261010-212708-52efcc): holdout3.json (12 cases, new skills plus generic "page"/"customer"
names) written and scored blind once at 24/36. Ranker fix in agent-intel score_item: name hits weigh by the share
of the name the task covers, description length penalty halved (/120), and the usage-history boost only applies
once the lexical score clears MIN_SCORE. A/B over the four sets in memory before editing: cases 19 -> 19,
holdout 32 -> 33, holdout2 19 -> 21, holdout3 24 -> 27 (no set lost a point; coverage alone or the length change
alone each lost one on cases.json because history pushed create-verification-skill into unrelated tasks).
Triggers after description fixes (seo-growth-loop excludes site speed, swiftpieces "swipe decks",
swiftui-iphone-duo "hinge (half-open posture)"): top1 63.6%, top3 75.8%, false-fire 1.7%; only those three
skills changed. Saved as the baseline.
