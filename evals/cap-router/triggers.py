"""Skill trigger & collision tier (deterministic, no LLM, stdlib only, Python 3.9).

Usage: python3 triggers.py [--skills-dir DIR] [--plugins] [--threshold 0.5] [--top 15]
                           [--json] [--save FILE] [--compare FILE] [--min-top3 PCT]

(a) Collision: TF-IDF cosine between every pair of skill descriptions; pairs at or above
    --threshold are routing-ambiguity hot spots (>= 0.75 marked HIGH).
(b) Self-rank: for each skill-triggers/*.json ({"skill","positive":[...],"negative":[...]};
    a negative may also be {"prompt","owner"}), rank every description against each prompt.
    Positive: hit@1 / hit@3 for the named skill. Negative: false fire when the named skill
    ranks #1 (or, with an owner, outranks the owner).

Lexical approximation of routing: a miss usually means the description lacks the words users
say; fix the description, not the prompt. Skills with `disable-model-invocation: true` are
left out of the corpus because the model never routes to them.

Approach reimplemented from addyosmani/agent-skills evals Tier 2 (MIT, commit 1401c8b).
"""
import json
import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
PLUGIN_GLOBS = [".claude/plugins/cache/*/*/*/skills/*", ".claude_second/plugins/cache/*/*/*/skills/*"]

STOP = set("""
a an and any are as at be before by for from in into is it its my need needs of on or our so that
the them this to use want we when with you your help me i can do does how please should will
what which while who why would make get let using used also only just like it's i've i'm don't
""".split())


def stem(t):
    for suf in ("ally", "ing", "ed", "es", "al"):
        if len(t) > len(suf) + 3 and t.endswith(suf):
            t = t[: -len(suf)]
            break
    if len(t) > 3 and t.endswith("s") and not t.endswith("ss"):
        t = t[:-1]
    if len(t) > 4 and t.endswith("e"):
        t = t[:-1]
    if len(t) > 4 and t[-1] == t[-2] and t[-1] not in "aeiou":
        t = t[:-1]
    if len(t) > 3 and t.endswith("y"):
        t = t[:-1] + "i"
    return t


def tokenize(text):
    toks = re.sub(r"[^a-z0-9\s-]", " ", (text or "").lower()).split()
    out = []
    for w in toks:
        for t in w.split("-"):
            if len(t) > 2 and t not in STOP:
                out.append(stem(t))
    return out


def frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}
    fm, i, block = {}, 1, lines[1:end]
    i = 0
    while i < len(block):
        m = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", block[i])
        i += 1
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        cont = []
        while i < len(block) and (block[i][:1] in (" ", "\t") or not block[i].strip()):
            cont.append(block[i].strip())
            i += 1
        if re.match(r"^[|>][+-]?$", raw):
            val = " ".join(c for c in cont if c)
        else:
            val = " ".join([raw] + [c for c in cont if c and not re.match(r"^[A-Za-z0-9_-]+\s*:", c)])
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        fm[key] = val
    return fm


def load_skills(skills_dir, plugins=False):
    skills, excluded = {}, []
    dirs = [(d.name, d) for d in sorted(Path(skills_dir).iterdir()) if not d.name.startswith(".")]
    if plugins:
        latest = {}
        for g in PLUGIN_GLOBS:
            for d in HOME.glob(g):
                vd = d.parent.parent
                try:
                    mt = vd.stat().st_mtime
                except OSError:
                    continue
                if vd.parent not in latest or mt > latest[vd.parent][0]:
                    latest[vd.parent] = (mt, vd)
        for _, vd in latest.values():
            for d in sorted((vd / "skills").glob("*")):
                dirs.append(("%s:%s" % (vd.parent.name, d.name), d))
    for name, d in dirs:
        f = d / "SKILL.md"
        if not f.is_file():
            continue
        fm = frontmatter(f.read_text(errors="replace"))
        if fm.get("disable-model-invocation", "").lower() == "true":
            excluded.append(name)
            continue
        skills[name] = fm.get("description", "")
    return skills, excluded


class Corpus:
    def __init__(self, skills):
        self.docs = {}
        for name, desc in skills.items():
            nt = tokenize(name.split(":")[-1].replace("-", " "))
            tf = {}
            for t in nt + nt + tokenize(desc):
                tf[t] = tf.get(t, 0) + 1
            self.docs[name] = tf
        df = {}
        for tf in self.docs.values():
            for t in tf:
                df[t] = df.get(t, 0) + 1
        n = len(self.docs)
        self.idf = {t: math.log(1 + n / (1 + c)) for t, c in df.items()}
        self.n = n
        self.vecs = {k: self.vec(tf) for k, tf in self.docs.items()}

    def vec(self, tf):
        return {t: f * self.idf.get(t, math.log(1 + self.n)) for t, f in tf.items()}

    @staticmethod
    def cos(a, b):
        if len(a) > len(b):
            a, b = b, a
        dot = sum(w * b.get(t, 0.0) for t, w in a.items())
        na = math.sqrt(sum(w * w for w in a.values()))
        nb = math.sqrt(sum(w * w for w in b.values()))
        return dot / (na * nb) if na and nb else 0.0

    def rank(self, prompt):
        tf = {}
        for t in tokenize(prompt):
            tf[t] = tf.get(t, 0) + 1
        pv = self.vec(tf)
        return sorted(((self.cos(pv, v), k) for k, v in self.vecs.items()), key=lambda x: (-x[0], x[1]))


def collisions(corpus, threshold):
    names = sorted(corpus.vecs)
    out = []
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            s = corpus.cos(corpus.vecs[names[i]], corpus.vecs[names[j]])
            if s >= threshold:
                out.append((round(s, 3), names[i], names[j]))
    return sorted(out, reverse=True)


def self_rank(corpus, case_dir):
    per, missing = [], []
    for f in sorted(Path(case_dir).glob("*.json")):
        try:
            case = json.loads(f.read_text())
        except ValueError as e:
            missing.append("%s (bad json: %s)" % (f.name, e))
            continue
        skill = case.get("skill")
        if skill not in corpus.vecs:
            missing.append("%s (skill %r not in routable corpus)" % (f.name, skill))
            continue
        row = {"skill": skill, "pos": 0, "top1": 0, "top3": 0, "neg": 0, "false_fire": 0, "misses": [], "fires": []}
        for p in case.get("positive", []):
            prompt = p["prompt"] if isinstance(p, dict) else p
            ranking = corpus.rank(prompt)
            pos = next(i for i, (_, k) in enumerate(ranking) if k == skill) + 1
            score = ranking[pos - 1][0]
            row["pos"] += 1
            if score > 0 and pos == 1:
                row["top1"] += 1
            if score > 0 and pos <= 3:
                row["top3"] += 1
            else:
                row["misses"].append("#%d %r (top: %s)" % (pos, prompt[:70], ranking[0][1]))
        for neg in case.get("negative", []):
            prompt = neg["prompt"] if isinstance(neg, dict) else neg
            owner = neg.get("owner") if isinstance(neg, dict) else None
            ranking = corpus.rank(prompt)
            order = [k for _, k in ranking]
            row["neg"] += 1
            if owner and owner in corpus.vecs:
                fired = order.index(skill) < order.index(owner)
            else:
                fired = ranking[0][1] == skill and ranking[0][0] > 0
            if fired:
                row["false_fire"] += 1
                row["fires"].append(repr(prompt[:70]))
        per.append(row)
    return per, missing


def pct(a, b):
    return round(100.0 * a / b, 1) if b else 0.0


def main(argv):
    def opt(name, default=None):
        if name in argv:
            return argv[argv.index(name) + 1]
        return default
    skills_dir = Path(opt("--skills-dir", str(HOME / ".agents" / "skills"))).expanduser()
    threshold = float(opt("--threshold", "0.5"))
    top = int(opt("--top", "15"))
    skills, excluded = load_skills(skills_dir, "--plugins" in argv)
    corpus = Corpus(skills)
    pairs = collisions(corpus, threshold)
    per, missing = self_rank(corpus, HERE / "skill-triggers")
    P = sum(r["pos"] for r in per)
    N = sum(r["neg"] for r in per)
    summary = {
        "skills_dir": str(skills_dir),
        "routable_skills": len(skills),
        "excluded_user_only": excluded,
        "description_chars": sum(len(d) for d in skills.values()),
        "collision_threshold": threshold,
        "collision_pairs": len(pairs),
        "collision_pairs_high": sum(1 for s, _, _ in pairs if s >= 0.75),
        "cases": len(per),
        "positives": P,
        "top1_rate": pct(sum(r["top1"] for r in per), P),
        "top3_rate": pct(sum(r["top3"] for r in per), P),
        "negatives": N,
        "false_fire_rate": pct(sum(r["false_fire"] for r in per), N),
    }
    if "--save" in argv:
        Path(opt("--save")).write_text(json.dumps(dict(summary, per_skill=[{k: r[k] for k in ("skill", "pos", "top1", "top3", "neg", "false_fire")} for r in per], top_pairs=pairs[:top]), indent=1) + "\n")
    if "--json" in argv:
        print(json.dumps(dict(summary, per_skill=per, pairs=pairs[:top], missing=missing), indent=1))
    else:
        print("Collision pairs (cosine >= %.2f): %d  [HIGH >= 0.75: %d]" % (threshold, len(pairs), summary["collision_pairs_high"]))
        for s, a, b in pairs[:top]:
            print("  %.2f %s  %s <-> %s" % (s, "HIGH" if s >= 0.75 else "    ", a, b))
        print("\nSelf-rank (%d cases over %d routable skills%s)" % (len(per), len(skills), ", %d user-only excluded" % len(excluded) if excluded else ""))
        print("  %-28s %6s %6s %8s" % ("skill", "top1", "top3", "falsefire"))
        for r in per:
            print("  %-28s %3d/%-2d %3d/%-2d %5d/%-2d" % (r["skill"], r["top1"], r["pos"], r["top3"], r["pos"], r["false_fire"], r["neg"]))
            for m in r["misses"]:
                print("      miss %s" % m)
            for m in r["fires"]:
                print("      false fire on %s" % m)
        for m in missing:
            print("  skipped: %s" % m)
        print("\nTOTAL top1=%.1f%% top3=%.1f%% (%d positives)  false-fire=%.1f%% (%d negatives)  desc-chars=%d"
              % (summary["top1_rate"], summary["top3_rate"], P, summary["false_fire_rate"], N, summary["description_chars"]))
    if "--compare" in argv:
        base = json.loads(Path(opt("--compare")).read_text())
        print("\nvs %s:" % opt("--compare"))
        for k in ("routable_skills", "description_chars", "collision_pairs", "collision_pairs_high", "top1_rate", "top3_rate", "false_fire_rate"):
            print("  %-22s %s -> %s" % (k, base.get(k), summary[k]))
    floor = opt("--min-top3")
    if floor is not None and summary["top3_rate"] < float(floor):
        print("FAIL: top3 %.1f%% < %s%%" % (summary["top3_rate"], floor))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
