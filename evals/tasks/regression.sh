#!/bin/bash
# Regression tests for bin/agent-task. Runs in a throwaway HOME and git repo; never touches the real home.
#   regression.sh          run all checks; exit 1 if any fail
#   KEEP=1 regression.sh   keep the temp dir for inspection
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
AT="$ROOT/bin/agent-task"
B=$(mktemp -d); export HOME=$B/home; mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1
R=$B/repo; mkdir -p $R; git -C $R init -q -b main; echo hi > $R/a.txt
git -C $R add -A; git -C $R -c user.name=t -c user.email=t@t commit -qm init
cd $R
DBF=$HOME/.agent-os/v2/db/agentos.sqlite
sql(){ python3 -c "import sqlite3,sys;print('\n'.join('|'.join(map(str,r)) for r in sqlite3.connect(sys.argv[1]).execute(sys.argv[2])))" "$DBF" "$1"; }
pass=0; fail=0; ok(){ if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

# start prints an id; same request in the same repo resumes; --new opens another
T=$("$AT" start "fix the slow login screen" 2>/dev/null)
ok "start prints an id" '[[ "$T" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]]'
ok "start writes request and checklist" '[ -f $HOME/.agent-os/v2/tasks/$T/request.txt ] && grep -q metric-before $HOME/.agent-os/v2/tasks/$T/checklist.json'
T2=$("$AT" start "fix the slow login screen" 2>/dev/null)
ok "start again resumes the open task" '[ "$T2" = "$T" ]'
T3=$("$AT" start "fix the slow login screen" --new 2>/dev/null)
ok "start --new opens a separate task" '[ -n "$T3" ] && [ "$T3" != "$T" ]'

# status / context show the task, with and without an id
ok "status shows the task" '"$AT" status $T | grep -q "\"id\": \"$T\""'
ok "status without id uses latest open task in repo" '"$AT" status | grep -q "\"repo\": \"$(cd $R && pwd -P)\""'
ok "context shows the task and request" 'out=$("$AT" context $T) && [[ "$out" == *"\"task_id\": \"$T\""* && "$out" == *"slow login"* ]] && [ -f $HOME/.agent-os/v2/tasks/$T/context.json ]'

# event appends
before=$(sql "SELECT COUNT(*) FROM events WHERE task_id='$T'")
"$AT" event $T DECISION --payload '{"note":"use cache"}' >/dev/null
ok "event appends to db and ndjson" '[ $(sql "SELECT COUNT(*) FROM events WHERE task_id=\"$T\" AND type=\"DECISION\"") -eq 1 ] && [ $(sql "SELECT COUNT(*) FROM events WHERE task_id=\"$T\"") -eq $((before+1)) ] && grep -q "use cache" $HOME/.agent-os/v2/tasks/$T/events.ndjson'
ok "event with bad JSON fails clearly" 'err=$("$AT" event $T X --payload "{nope" 2>&1 >/dev/null); [ $? -ne 0 ] && [[ "$err" == *"not valid JSON"* ]]'

# failure memory
"$AT" fail remember "ModuleNotFoundError: No module named requests at /Users/someone/app.py line 12" "pip install requests in the venv" >/dev/null
ok "fail search finds the remembered fix" '"$AT" fail search "No module named requests" | grep -q "pip install requests"'
ok "fail search with no match prints []" '[ "$("$AT" fail search "zzzqqq unrelated")" = "[]" ]'

# proof
echo "log" > $B/after.log
"$AT" proof metric $T before login_ms 900 ms >/dev/null
"$AT" proof metric $T after login_ms 300 ms >/dev/null
"$AT" proof artifact $T after login_log $B/after.log >/dev/null
ok "proof metric/artifact recorded" '[ $(sql "SELECT COUNT(*) FROM proof WHERE task_id=\"$T\"") -eq 3 ] && [ "$(sql "SELECT kind FROM proof WHERE task_id=\"$T\" AND name=\"login_log\"")" = artifact-after ]'
ok "proof artifact with missing file fails" '! "$AT" proof artifact $T after x $B/nope.log 2>/dev/null'
out=$("$AT" proof capture $T --run "true"); rc=$?
ok "proof capture lists evidence the checklist still needs" '[ $rc -eq 1 ] && [[ "$out" == *"artifact-before (required"* ]]'
"$AT" proof artifact $T before login_log_before $B/after.log >/dev/null
out=$("$AT" proof capture $T --run "true"); rc=$?
ok "proof capture records entries and is complete" '[ $rc -eq 0 ] && [[ "$out" == *"\"complete\": true"* && "$out" == *"login_ms"* ]] && [ -f $HOME/.agent-os/v2/tasks/$T/proof.json ]'
"$AT" proof capture $T3 >/dev/null 2>&1; rc=$?
ok "proof capture with no evidence exits 1" '[ $rc -eq 1 ]'
"$AT" proof capture $T --run "false" >/dev/null 2>&1; rc=$?
ok "proof capture with failing check exits 1" '[ $rc -eq 1 ]'

# handoff
H=$("$AT" handoff $T 2>/dev/null)
ok "handoff prints a resumable brief" '[[ "$H" == *"# Handoff: task $T"* && "$H" == *"slow login"* && "$H" == *"agent-task context $T"* && "$H" == *"DECISION"* ]]'
ok "handoff writes handoff.md" 'grep -q "Handoff: task $T" $HOME/.agent-os/v2/tasks/$T/handoff.md'

# finish
out=$("$AT" finish $T --outcome success --run "true")
ok "finish --outcome success writes the outcome" '[[ "$out" == *"\"outcome\": \"success\""* ]] && [ "$(sql "SELECT outcome FROM metrics WHERE task_id=\"$T\"")" = success ] && [ "$(sql "SELECT status FROM tasks WHERE id=\"$T\"")" = completed ]'
ok "status shows the outcome" '"$AT" status $T | grep -q "\"outcome\": \"success\""'
T4=$("$AT" start "fix the slow login screen" 2>/dev/null)
ok "start after finish opens a new task" '[ "$T4" != "$T" ]'

# errors
err=$("$AT" status 20200101-000000-deadbeef 2>&1); rc=$?
ok "unknown id: non-zero exit, clear message" '[ $rc -ne 0 ] && [[ "$err" == *"unknown task"* && "$err" != *Traceback* ]]'
err=$("$AT" status "fix the login bug" 2>&1); rc=$?
ok "free text instead of id: clear error" '[ $rc -ne 0 ] && [[ "$err" == *"is not a task id"* && "$err" != *Traceback* ]]'
mkdir -p $B/empty; err=$(cd $B/empty && "$AT" handoff 2>&1); rc=$?
ok "no id and no open task: clear error" '[ $rc -ne 0 ] && [[ "$err" == *"no open task"* && "$err" != *Traceback* ]]'

# help and hygiene
ok "--help lists the subcommands" '(h=$("$AT" --help) && for c in init start status context event handoff "fail search" "proof capture" finish; do [[ "$h" == *"$c"* ]] || exit 1; done)'
ok "every subcommand has --help" '(for c in init start status context event handoff fail "fail search" "fail remember" proof "proof metric" "proof artifact" "proof capture" finish; do "$AT" $c --help >/dev/null || exit 1; done)'
ok "no network code" '! grep -nE "urllib|http\.client|https?://|requests" "$AT"'
ok "no private machine or model references" '! grep -niE "luna|openai|agent-cap|agent-intel|agent-ops|agent-mode|agent-storage|/Users/[a-z]" "$AT" | grep -v "(?:Users|home)"'

echo "passed=$pass failed=$fail"
cd /; [ -n "${KEEP:-}" ] && echo "kept $B" || rm -rf "$B"
[ $fail -eq 0 ]
