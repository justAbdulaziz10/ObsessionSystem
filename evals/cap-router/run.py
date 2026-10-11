"""Score `agent-cap recommend`. Usage: python3 run.py [cases.json|holdout.json]

holdout.json was written before tuning the ranker; do not tune against it."""
import json, subprocess, sys
from pathlib import Path

cases = json.loads((Path(__file__).parent / (sys.argv[1] if len(sys.argv) > 1 else "cases.json")).read_text())
total = 0
for c in cases:
    out = json.loads(subprocess.run([sys.argv[2] if len(sys.argv) > 2 else "agent-cap", "recommend", c["task"]], capture_output=True, text=True).stdout)
    names = lambda k: [x.get("name", "") if isinstance(x, dict) else str(x) for x in out.get(k, [])]
    skills, mcps = names("recommended_skills"), names("recommended_mcps")
    s_ok = not c["skills_any"] and not skills or any(p in s for p in c["skills_any"] for s in skills)
    m_ok = set(mcps) <= set(c["mcps_any"]) if not c["mcps_any"] else any(m in c["mcps_any"] for m in mcps)
    d_ok = out.get("domain") == c["domain"]
    score = s_ok + m_ok + d_ok
    total += score
    print(f"{score}/3  domain={'ok' if d_ok else out.get('domain')} skills={'ok' if s_ok else skills} mcps={'ok' if m_ok else mcps}  {c['task'][:55]}")
print(f"\nTOTAL {total}/{3 * len(cases)}")
