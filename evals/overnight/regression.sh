#!/bin/bash
# Regression tests for the reviewer's 8 findings. Fakes: codex-ha, claude.
set -u
B=$(mktemp -d); F=$B/bin; mkdir -p $F; export PATH=$F:$PATH AGENT_OVERNIGHT_DIR=$B/ov
cat > $F/codex-ha <<'X'
#!/bin/bash
[ "$1" = ready ] && exit 0
case "$FAKE" in
  edit) echo fixed > feature.txt ;;
  selfcommit) echo fixed > feature.txt; git add feature.txt; git -c user.name=a -c user.email=a@a commit -qm self ;;
  push) echo fixed > feature.txt; git push origin HEAD:refs/heads/pwned >/dev/null 2>&1; echo "push rc=$?" > push.txt ;;
  crash) echo fixed > feature.txt ;;
esac
exit 0
X
cat > $F/claude <<'X'
#!/bin/bash
[ -n "${FAKE_CALLS:-}" ] && echo "$CLAUDE_CONFIG_DIR" >> "$FAKE_CALLS"
[ -n "${FAKE_LIMIT_ALL:-}" ] && { echo '{"is_error":true,"result":"You hit your limit"}'; exit 1; }
case "$CLAUDE_CONFIG_DIR" in
  */.claude) [ -n "${FAKE_LIMIT1:-}" ] && { echo '{"is_error":true,"result":"You hit your limit"}'; exit 1; } ;;
  *) [ -n "${FAKE_SLEEP2:-}" ] && sleep 5 ;;
esac
echo '{"is_error":false,"result":"ATTENTION:\n- nothing\nFINDINGS:\nVERDICT: SHIP"}'
X
chmod +x $F/*
mkrepo(){ R=$B/$1; mkdir -p $R; git -C $R init -q -b main; echo todo > $R/feature.txt; git -C $R add -A; git -C $R -c user.name=t -c user.email=t@t commit -qm init; git init -q --bare $B/$1.remote.git; git -C $R remote add origin $B/$1.remote.git; echo $R; }
st(){ python3 -c "import json,sys;q=json.load(open('$B/ov/queue.json'));print(' '.join(t['id']+':'+t['status'] for t in q))"; }
DONE='grep -q fixed feature.txt'
pass=0; fail=0; ok(){ if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

# F2: agent commits itself -> passed, not no-change, branch kept
R=$(mkrepo r2); agent-overnight add --repo $R --done "$DONE" g2 >/dev/null
FAKE=selfcommit agent-overnight run --attempts 1 >/dev/null; agent-overnight clean --merged >/dev/null
ok "F2 self-commit counted as change" '[[ "$(st)" == *":passed"* ]]'

# F4: push blocked at git level
R=$(mkrepo r4); agent-overnight add --repo $R --done "$DONE" g4 >/dev/null
FAKE=push agent-overnight run --attempts 1 --no-review >/dev/null
ok "F4 push blocked" '! git -C $B/r4.remote.git rev-parse -q --verify refs/heads/pwned >/dev/null'

# F1: interrupted task whose worktree holds a commit -> blocked, never cleaned
R=$(mkrepo r1); agent-overnight add --repo $R --done "$DONE" g1 >/dev/null
ID=$(python3 -c "import json;print(json.load(open('$B/ov/queue.json'))[-1]['id'])")
WT=$B/ov/worktrees/$ID; git -C $R worktree add -q -b overnight/x $WT main; echo fixed > $WT/feature.txt; git -C $WT -c user.name=a -c user.email=a@a commit -qam work
python3 - "$B/ov/queue.json" "$ID" <<'P'
import json,sys; q=json.load(open(sys.argv[1]))
for t in q:
    if t["id"]==sys.argv[2]: t.update(status="running", branch="overnight/x", worktree=sys.argv[3] if len(sys.argv)>3 else t.get("worktree"))
json.dump(q,open(sys.argv[1],"w"))
P
FAKE=edit agent-overnight run --attempts 1 >/dev/null; agent-overnight clean --merged >/dev/null
ok "F1 interrupted work blocked, kept" '[[ "$(st)" == *"$ID:blocked"* ]] && git -C $R rev-parse -q --verify overnight/x >/dev/null'

# F3: denied repo not run
R=$(mkrepo ProjectLike); agent-overnight add --repo $R --done "$DONE" g3 >/dev/null
D3=$(python3 -c "import json;print(json.load(open('$B/ov/queue.json'))[-1]['id'])")
R=$(mkrepo okrepo); agent-overnight add --repo $R --done "$DONE" g3b >/dev/null
A3=$(python3 -c "import json;print(json.load(open('$B/ov/queue.json'))[-1]['id'])")
FAKE=edit agent-overnight run --attempts 1 --no-review --deny=projectlike >/dev/null
ok "F3 denied repo skipped, allowed one ran" '[[ "$(st)" == *"$D3:pending"* && "$(st)" == *"$A3:passed"* ]]'

# F7: interruption cap
python3 - "$B/ov/queue.json" <<'P'
import json,sys; q=json.load(open(sys.argv[1]))
for t in q:
    if t["status"]=="pending": t.update(status="running", interrupted=2)
json.dump(q,open(sys.argv[1],"w"))
P
agent-overnight run --attempts 1 --deny=projectlike >/dev/null
ok "F7 interrupted 3x -> blocked" '[[ "$(st)" != *":pending"* && "$(st)" != *":running"* ]]'

# F8: ids unique after clean
before=$(st); agent-overnight clean --merged >/dev/null; R=$(mkrepo r8); agent-overnight add --repo $R --done "$DONE" g8 >/dev/null
N=$(python3 -c "import json;print(json.load(open('$B/ov/queue.json'))[-1]['id'])")
ok "F8 new id $N not reused" '[[ "$before" != *"$N:"* ]] && [[ "$N" == *"-006" ]]'

# F5: failover where account 2 times out -> 124, not 75
mkdir -p $B/.claude_second
F5=$(AGENT_CLAUDE_DIRS=$B/.claude_second python3 - <<'P'
import importlib.machinery,importlib.util,os
l=importlib.machinery.SourceFileLoader('ov',__import__('shutil').which('agent-overnight'))
m=importlib.util.module_from_spec(importlib.util.spec_from_loader('ov',l)); l.exec_module(m)
os.environ.update(FAKE_LIMIT1="1", FAKE_SLEEP2="1")
rc,_=m.claude(["x"],"/tmp",2)
print(rc)
P
)
ok "F5 timeout after limit -> rc=$F5" '[[ "$F5" == 124 ]]'

# Config dirs: ~/.claude, CLAUDE_CONFIG_DIR, AGENT_CLAUDE_DIRS in order, each once; only ~/.claude when neither is set
ovclaude(){ python3 - <<'P'
import importlib.machinery,importlib.util,os
l=importlib.machinery.SourceFileLoader('ov',__import__('shutil').which('agent-overnight'))
m=importlib.util.module_from_spec(importlib.util.spec_from_loader('ov',l)); l.exec_module(m)
rc,text=m.claude(["x"],"/tmp",5)
print(rc, text.split(":")[0])
P
}
mkdir -p $B/work-claude; H=$(python3 -c "import os;print(os.path.abspath(os.environ['HOME']))")  # dirs are normalized
ALL=$(CLAUDE_CONFIG_DIR=$B/.claude_second AGENT_CLAUDE_DIRS="$HOME/.claude:$B/work-claude:~/.claude:$B/.claude_second/:$B/missing" \
  FAKE_LIMIT_ALL=1 FAKE_CALLS=$B/calls1 ovclaude)
ok "all dirs tried in order, each once, missing skipped -> rc 75, label work-claude" \
  '[[ "$ALL" == "75 work-claude" && "$(tr "\n" " " < $B/calls1)" == "$H/.claude $B/.claude_second $B/work-claude " ]]'
ONE=$(unset CLAUDE_CONFIG_DIR AGENT_CLAUDE_DIRS; FAKE_LIMIT1=1 FAKE_CALLS=$B/calls2 ovclaude)
ok "only ~/.claude when neither is set -> rc 75, label claude" '[[ "$ONE" == "75 claude" && "$(cat $B/calls2)" == "$H/.claude" ]]'

# F6: concurrent add + update keep both
R=$(mkrepo r6); for i in $(seq 1 8); do agent-overnight add --repo $R --done true "c$i" >/dev/null & done; wait
ok "F6 8 concurrent adds all kept" '[ $(python3 -c "import json;print(sum(t[\"goal\"].startswith(\"c\") for t in json.load(open(\"$B/ov/queue.json\"))))") -eq 8 ]'
echo "passed=$pass failed=$fail"; rm -rf $B
[ "$fail" = 0 ]
