#!/bin/bash
# Regression tests for the telemetry pipeline:
#   ~/bin/agent-telemetry-hook (shell spool writer), ~/bin/agent-telemetry-ingest (spool -> DB),
#   ~/bin/agent-usage, ~/bin/agent-session-distill (deterministic parts only).
# Runs against a throwaway DB and spool: AGENTOS_TELEMETRY_DB / AGENTOS_TELEMETRY_SPOOL (default: new temp paths).
# q() ingests the spool before every query, so the row checks below hold for hook + ingest together.
# Never calls a model.
#   regression.sh            run all checks; exit 1 on the first failure
#   KEEP=1 regression.sh     keep the temp dir for inspection
set -u
HOOK="$HOME/bin/agent-telemetry-hook"
USAGE="$HOME/bin/agent-usage"
DISTILL="$HOME/bin/agent-session-distill"
INGEST="$HOME/bin/agent-telemetry-ingest"
PY=/usr/bin/python3
TMP=$(mktemp -d -t agentos-telemetry-reg)
export AGENTOS_TELEMETRY_DB="${AGENTOS_TELEMETRY_DB:-$TMP/test.sqlite}"
export AGENTOS_CAP_STATS="$TMP/capability-stats.json"
export AGENTOS_DISTILL_LOG="$TMP/distill.log"
export AGENTOS_TELEMETRY_ERRLOG="$TMP/telemetry-errors.log"
export AGENTOS_TELEMETRY_SPOOL="$TMP/spool"
export AGENTOS_TELEMETRY_MIN_AGE=0   # tests write sequentially; production claims files >= 1 s old
unset AGENTOS_DISTILL AGENTOS_TELEMETRY_DISABLE AGENTOS_TELEMETRY_TEST_CRASH
# A second account the way a user configures one; ~/.claude is always the first.
export AGENT_CLAUDE_DIRS="$HOME/.claude_second"
pass=0
fail() { echo "FAIL: $*"; [ -n "${KEEP:-}" ] || rm -rf "$TMP"; exit 1; }
ok() { pass=$((pass + 1)); echo "ok   $*"; }
ingest() { "$INGEST" --quiet --wait 30 "$@" || fail "ingest rc=$?"; }
q() { ingest; sqlite3 "$AGENTOS_TELEMETRY_DB" "$1"; }
qraw() { sqlite3 "$AGENTOS_TELEMETRY_DB" "$1"; }   # no ingest first
spooled() { ls "$AGENTOS_TELEMETRY_SPOOL" 2>/dev/null | grep -c '^e\.'; }
TP1="$HOME/.claude/projects/-tmp-x/aaaa.jsonl"
TP2="$HOME/.claude_second/projects/-tmp-x/bbbb.jsonl"

# Feed one payload; the hook must exit 0 and print nothing.
feed() {
  local out rc
  out=$(printf '%s' "$1" | "$HOOK"); rc=$?
  [ "$rc" = 0 ] || fail "hook rc=$rc for: ${1:0:80}"
  [ -z "$out" ] || fail "hook wrote stdout for: ${1:0:80}"
}

# 0. static checks
for f in "$INGEST" "$USAGE" "$DISTILL"; do
  "$PY" -c "import py_compile,sys; py_compile.compile(sys.argv[1], cfile='$TMP/x.pyc', doraise=True)" "$f" \
    || fail "py_compile $f"
done
/bin/sh -n "$HOOK" && /bin/dash -n "$HOOK" || fail "hook shell syntax"
[ -x "$HOOK" ] && [ "$(head -c 2 "$HOOK")" != '#!' ] || fail "hook must be executable and shebang-less (runs in-process in /bin/sh)"
! grep -Eq '(^|[^-])(python|jq)( |$)' <(grep -v '^#' "$HOOK") || fail "hook hot path must not call python or jq"
ok "py_compile (python 3.9) of ingest, agent-usage, distill; hook: sh+dash syntax, no shebang, no python/jq"
for f in "$HOME/.claude/settings.json" "$HOME/.claude_second/settings.json"; do
  "$PY" -m json.tool "$f" >/dev/null || fail "invalid JSON $f"
  "$PY" - "$f" <<'EOF' || fail "hook not registered in $1"
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
cmd = '"$HOME/bin/agent-telemetry-hook"'
for ev in ("PreToolUse", "Stop", "StopFailure", "SessionEnd"):
    assert any(h.get("command") == cmd for g in d.get(ev, []) for h in g.get("hooks", [])), ev
assert any(g.get("matcher") == "^(Skill|Agent|Task|Read)$|^mcp__" for g in d["PreToolUse"]
           if any(h.get("command") == cmd for h in g.get("hooks", [])))
EOF
done
ok "settings.json valid, hook registered on 4 events in both accounts"

# 1. PreToolUse kinds
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"'"$HOME"'/bin","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"agent-work-loop","args":"secret user text"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"do things"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"prompt":"x"}}'
feed '{"session_id": "s1", "transcript_path": "'"$TP1"'", "cwd": "/tmp", "hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": {"file_path": "'"$HOME"'/.agents/skills/graphify/SKILL.md"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"'"$HOME"'/.claude/plugins/cache/mkt/hookify/1.2.0/skills/writing-rules/SKILL.md"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"'"$HOME"'/.claude/agents/agent-risk-reviewer.md"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/plain.py"}}'
feed '{"session_id": "s1", "transcript_path": "'"$TP1"'", "cwd": "/tmp", "hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": {"file_path": "/tmp/notes/SKILL.md.txt"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"mcp__claude_ai_Gmail__search_threads","tool_input":{"q":"x"}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"mcp__plugin_lazyweb_lazyweb__lazyweb_execute","tool_input":{}}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
got=$(q "select kind||'|'||name||'|'||detail||'|'||account from usage order by id" | tr '\n' ';')
want="skill|agent-work-loop||claude;agent|Explore||claude;agent|general-purpose||claude;read_skill|graphify||claude;read_skill|writing-rules|plugin:hookify|claude;read_agent|agent-risk-reviewer||claude;mcp|claude_ai_Gmail|search_threads|claude;mcp|plugin_lazyweb_lazyweb|lazyweb_execute|claude;"
[ "$got" = "$want" ] || fail "usage rows: got [$got] want [$want]"
ok "PreToolUse: skill, agent (Agent+Task), read_skill (user+plugin), read_agent, mcp; plain Read/Bash ignored"
[ "$(q "select repo from usage where id=1")" = "" ] || [ -d "$HOME/bin/.git" ] || fail "repo for non-repo cwd"
[ "$(q "select count(*) from usage where detail like '%secret%'")" = 0 ] || fail "skill args leaked into DB"
ok "no free text (skill args, prompts) stored"

# 2. account from transcript path / CLAUDE_CONFIG_DIR
feed '{"session_id":"s2","transcript_path":"'"$TP2"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"x"}}'
[ "$(q "select account from usage where session_id='s2'")" = claude_second ] || fail "account claude_second from transcript path"
printf '%s' '{"session_id":"s3","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"y"}}' \
  | CLAUDE_CONFIG_DIR="$HOME/.claude_second" "$HOOK"
[ "$(q "select account from usage where session_id='s3'")" = claude_second ] || fail "account from CLAUDE_CONFIG_DIR"
printf '%s' '{"session_id":"s4","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"y"}}' \
  | env -u CLAUDE_CONFIG_DIR "$HOOK"
[ "$(q "select account from usage where session_id='s4'")" = claude ] || fail "default account claude"
mkdir -p "$TMP/work-claude"
feed '{"session_id":"s2b","transcript_path":"'"$TMP"'/work-claude/projects/-tmp-x/cccc.jsonl","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"x"}}'
AGENT_CLAUDE_DIRS="$HOME/.claude_second:$TMP/work-claude" ingest
[ "$(qraw "select account from usage where session_id='s2b'")" = work-claude ] || fail "account label from an AGENT_CLAUDE_DIRS entry"
feed '{"session_id":"s2c","transcript_path":"'"$TP2"'","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"x"}}'
env -u AGENT_CLAUDE_DIRS -u CLAUDE_CONFIG_DIR "$INGEST" --quiet --wait 30 || fail "ingest rc=$?"
[ "$(qraw "select account from usage where session_id='s2c'")" = claude ] || fail "transcript outside known dirs, no header: want claude"
ok "account: config dir holding the transcript (~/.claude, CLAUDE_CONFIG_DIR, AGENT_CLAUDE_DIRS), then header CLAUDE_CONFIG_DIR, default claude"

# 3. session events
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"Stop","last_assistant_message":"done"}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 secret detail","last_assistant_message":"API Error"}'
feed '{"session_id":"s1","transcript_path":"'"$TP1"'","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
got=$(q "select account||'|'||stops||'|'||stop_failures||'|'||last_error||'|'||end_reason||'|'||tool_counts||'|'||transcript_path from sessions where session_id='s1'")
want="claude|2|1|rate_limit|prompt_input_exit|{\"agent\": 2, \"mcp\": 2, \"read_agent\": 1, \"read_skill\": 2, \"skill\": 1}|$TP1"
[ "$got" = "$want" ] || fail "sessions row: got [$got] want [$want]"
[ "$(q "select count(*) from sessions where last_error like '%secret%'")" = 0 ] || fail "error text leaked"
ok "Stop/StopFailure/SessionEnd upsert: stops, failures, error type only, end reason, tool counts"

# 4. malformed / hostile input: exit 0, no stdout, nothing recorded
before=$(q "select count(*) from usage")
feed 'garbage{'
feed ''
feed '[1,2,3]'
feed '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":"not-a-dict"}'
feed '{"hook_event_name":"Stop"}'
feed '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":12}}'
out=$(printf '%s' '{"session_id":"s9","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"z"}}' \
  | AGENTOS_DISTILL=1 "$HOOK"); [ -z "$out" ] || fail "stdout with AGENTOS_DISTILL"
out=$(printf '%s' '{"session_id":"s9","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"z"}}' \
  | AGENTOS_TELEMETRY_SPOOL="/nonexistent-dir/spool" "$HOOK" 2>&1); [ $? = 0 ] && [ -z "$out" ] || fail "unwritable spool must exit 0 silently"
grep -q "cannot write a spool file in /nonexistent-dir/spool" "$AGENTOS_TELEMETRY_ERRLOG" || fail "unwritable spool not logged"
[ "$(q "select count(*) from usage")" = "$before" ] || fail "malformed/disabled input recorded rows"
[ "$(spooled)" = 0 ] || fail "malformed files left in the spool"
[ "$(grep -c 'agent-telemetry-ingest: discarded' "$AGENTOS_TELEMETRY_ERRLOG")" -ge 2 ] || fail "discarded payloads were not logged"
ok "malformed JSON, empty, non-object, bad types, AGENTOS_DISTILL=1, unwritable spool: exit 0, silent, no rows, logged"

# 5. agent-usage
"$USAGE" skills --days 1 | grep -q "agent-work-loop" || fail "agent-usage skills"
"$USAGE" agents --days 1 | grep -q "Explore" || fail "agent-usage agents"
"$USAGE" mcp --days 1 | grep -q "claude_ai_Gmail" || fail "agent-usage mcp"
"$USAGE" unused --json | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d['installed'] > 0 and 'graphify' not in [x['name'] for x in d['unused']]" \
  || fail "agent-usage unused"
"$USAGE" sessions --json | "$PY" -c "import json,sys; assert any(r['session_id']=='s1' for r in json.load(sys.stdin))" || fail "agent-usage sessions"
printf '%s\n' '{"skill:graphify": {"success": 3, "failure": 1, "seconds": 2.0, "last_used": "x"}}' > "$AGENTOS_CAP_STATS"
"$USAGE" sync-stats --days 1 >/dev/null || fail "sync-stats"
"$PY" - "$AGENTOS_CAP_STATS" <<'EOF' || fail "capability-stats merge"
import json, sys
d = json.load(open(sys.argv[1]))
g = d["skill:graphify"]
assert (g["success"], g["failure"], g["seconds"], g["last_used"]) == (3, 1, 2.0, "x"), g  # manual outcome fields untouched
assert g["loads"] == 1 and g["loads_window_days"] == 1
assert d["skill:writing-rules"]["loads"] == 1 and d["skill:writing-rules"]["success"] == 0
assert d["agent:explore"]["loads"] == 1 and d["mcp:gmail"]["loads"] == 1 and d["mcp:lazyweb"]["loads"] == 1
EOF
ok "agent-usage skills/agents/mcp/unused/sessions; sync-stats merges loads, keeps success/failure"

# 6. distill: deterministic transcript parsing + redaction (no model call)
FX="$TMP/fixture-session.jsonl"
"$PY" - "$FX" <<'EOF'
import json, sys
rows = []
def a(content): rows.append({"type": "assistant", "cwd": "/tmp/proj", "message": {"role": "assistant", "content": content}})
def u(content): rows.append({"type": "user", "cwd": "/tmp/proj", "message": {"role": "user", "content": content}})
a([{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "cd /tmp/proj && flutter test test/a_test.dart"}}])
u([{"type": "tool_result", "tool_use_id": "t1", "is_error": True,
    "content": "Exit code 1\nError: token=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 sk-ant-api03-SECRETSECRET AIzaSyA1234567890abcdefghijklmnopqrs "  # agent-ship: allow-secret
               "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijklmnop me@example.com\n"  # agent-ship: allow-secret
               "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\n-----END PRIVATE KEY-----\nPub get failed: run flutter pub get"}])  # agent-ship: allow-secret
a([{"type": "text", "text": "Dependencies are missing; running pub get first."}])
a([{"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "flutter pub get"}}])
u([{"type": "tool_result", "tool_use_id": "t2", "content": "Got dependencies!"}])
a([{"type": "tool_use", "id": "t3", "name": "Bash", "input": {"command": "flutter test test/a_test.dart"}}])
u([{"type": "tool_result", "tool_use_id": "t3", "content": "All tests passed!"}])
# noise: grep no-match then grep again; edit-before-read guard
a([{"type": "tool_use", "id": "t4", "name": "Bash", "input": {"command": "grep -rn foo ."}}])
u([{"type": "tool_result", "tool_use_id": "t4", "is_error": True, "content": "Exit code 1"}])
a([{"type": "tool_use", "id": "t5", "name": "Bash", "input": {"command": "grep -rn bar ."}}])
u([{"type": "tool_result", "tool_use_id": "t5", "content": "x"}])
a([{"type": "tool_use", "id": "t6", "name": "Edit", "input": {"file_path": "/tmp/proj/a.dart"}}])
u([{"type": "tool_result", "tool_use_id": "t6", "is_error": True, "content": "<tool_use_error>File has not been read yet. Read it first</tool_use_error>"}])
a([{"type": "tool_use", "id": "t7", "name": "Edit", "input": {"file_path": "/tmp/proj/a.dart"}}])
u([{"type": "tool_result", "tool_use_id": "t7", "content": "ok"}])
rows.append({"type": "assistant", "isApiErrorMessage": True, "message": {"role": "assistant", "content": [{"type": "text", "text": "API Error"}]}})
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
EOF
q "insert into sessions(session_id,account,cwd,transcript_path,last_seen,stops,stop_failures) values('fx','claude','/tmp/proj','$FX',strftime('%Y-%m-%dT%H:%M:%S','now','localtime')||'.000+03:00',1,1)"
"$DISTILL" --dry-run --json --show-snippet --transcript "$FX" > "$TMP/distill.json" || fail "distill dry-run rc"
"$PY" - "$TMP/distill.json" <<'EOF' || fail "distill parse/redaction"
import json, sys
d = json.load(open(sys.argv[1]))
c = [x for x in d["candidates"] if x["session_id"] == "fx"]
assert len(c) == 1, d["candidates"]
c = c[0]
assert c["resolved_pairs"] == 1 and c["best"] == ["Bash", "flutter test"], c   # grep + edit-guard noise ignored
assert c["api_errors"] == 1 and c["stop_failures"] == 1 and c["tool_errors"] == 3, c
r = d["results"][0]
assert r["result"] == "not-asked (dry-run)" and "model" not in r
s = r["snippet"]
for bad in ("ghp_ABCDEF", "sk-ant-api03", "AIzaSy", "eyJhbGci", "me@example.com", "MIIEvQ", "BEGIN PRIVATE KEY"):
    assert bad not in s, bad
assert "flutter pub get" in s and "running pub get first" in s
EOF
[ "$(q "select coalesce(distilled_at,'') from sessions where session_id='fx'")" = "" ] || fail "dry-run marked session"
[ ! -s "$AGENTOS_DISTILL_LOG" ] || fail "dry-run wrote the distill log"
ok "distill: resolved pair found, noise ignored, secrets/emails/PEM/JWT redacted, dry-run writes nothing"

# 7. spool files: private, plain Reads and disabled runs write nothing, header carries account + mode
ingest
feed '{"session_id":"s7","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/plain.py"}}'
printf '%s' '{"session_id":"s7","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"z"}}' | AGENTOS_TELEMETRY_DISABLE=1 "$HOOK"
[ "$(spooled)" = 0 ] || fail "plain Read / disabled run wrote a spool file"
printf '%s' '{"session_id":"s7","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"s7skill"}}' \
  | CLAUDE_CONFIG_DIR="$HOME/.claude_second" "$HOOK"
f=$(ls "$AGENTOS_TELEMETRY_SPOOL"/e.* 2>/dev/null | head -1)
[ -n "$f" ] || fail "no spool file for a Skill event"
[ "$(stat -f %Lp "$f")" = 600 ] && [ "$(stat -f %Lp "$AGENTOS_TELEMETRY_SPOOL")" = 700 ] || fail "spool modes: file $(stat -f %Lp "$f") dir $(stat -f %Lp "$AGENTOS_TELEMETRY_SPOOL")"
head -1 "$f" | grep -q "^AOS1	$HOME/.claude_second	" || fail "spool header: $(head -1 "$f")"
[ "$(q "select account||'|'||mode from usage where session_id='s7'")" = "claude_second|$(cat "$HOME/.agent-os/mode" 2>/dev/null || echo owner)" ] || fail "account/mode from spool header"
[ "$(spooled)" = 0 ] || fail "ingest left spool files"
ok "spool file 600 in 700 dir; header keeps CLAUDE_CONFIG_DIR + mode; plain Read/disabled write nothing; ingest empties spool"

# 8. concurrent writers: 4 sessions x 2 accounts x 30 events in parallel -> exactly 240 rows, no loss, no dupes
CS="$TMP/spool-concurrent"
for sess in a b c d; do
  for acct in claude claude_second; do
    ( for i in $(seq 1 30); do
        printf '%s' '{"session_id":"c-'$sess'-'$acct'","transcript_path":"'"$HOME"'/.'$acct'/projects/x/'$sess'.jsonl","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"mcp__srv'$i'__tool","tool_input":{"blob":"'"$(printf '%0900d' 0)"'"}}' \
          | AGENTOS_TELEMETRY_SPOOL="$CS" "$HOOK" || echo HOOKFAIL
      done ) > "$TMP/conc.$sess.$acct" &
  done
done
wait
cat "$TMP"/conc.* | grep -q HOOKFAIL && fail "hook failed under concurrency"
[ "$(ls "$CS" | grep -c '^e\.')" = 240 ] || fail "concurrent writers: $(ls "$CS" | grep -c '^e\.') spool files, want 240"
AGENTOS_TELEMETRY_SPOOL="$CS" "$INGEST" --quiet --wait 30 || fail "ingest after concurrent writers"
[ "$(qraw "select count(*) from usage where session_id like 'c-%'")" = 240 ] || fail "concurrent rows: $(qraw "select count(*) from usage where session_id like 'c-%'")"
[ "$(qraw "select count(distinct session_id||name) from usage where session_id like 'c-%'")" = 240 ] || fail "concurrent rows duplicated or lost"
[ "$(qraw "select count(*) from usage where session_id like 'c-%-claude_second' and account='claude_second'")" = 120 ] || fail "concurrent account split"
ok "8 parallel writers (both accounts) x 30 events: 240 files, 240 rows, none lost or duplicated"

# 9. double ingest + crash safety: two concurrent ingesters, crash before COMMIT, crash after COMMIT
base=$(qraw "select count(*) from usage")
for i in $(seq 1 20); do
  feed '{"session_id":"s9","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"dbl'$i'"}}'
done
"$INGEST" --quiet --wait 30 & "$INGEST" --quiet --wait 30 & "$INGEST" --quiet --wait 30 & wait
[ "$(qraw "select count(*) from usage")" = $((base + 20)) ] || fail "3 concurrent ingesters: $(qraw "select count(*) from usage") rows, want $((base + 20))"
ingest; [ "$(qraw "select count(*) from usage")" = $((base + 20)) ] || fail "re-ingest duplicated rows"
for i in 1 2 3; do feed '{"session_id":"s9","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"crashA'$i'"}}'; done
AGENTOS_TELEMETRY_TEST_CRASH=before-commit "$INGEST" --quiet; [ $? = 3 ] || fail "crash injection before-commit did not fire"
[ "$(qraw "select count(*) from usage where name like 'crashA%'")" = 0 ] || fail "rows visible after crash before COMMIT"
ls -d "$AGENTOS_TELEMETRY_SPOOL"/batch.* >/dev/null 2>&1 || fail "claimed batch missing after crash before COMMIT"
ingest; [ "$(qraw "select count(*) from usage where name like 'crashA%'")" = 3 ] || fail "batch not recovered after crash before COMMIT"
for i in 1 2 3; do feed '{"session_id":"s9","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"crashB'$i'"}}'; done
AGENTOS_TELEMETRY_TEST_CRASH=after-commit "$INGEST" --quiet; [ $? = 3 ] || fail "crash injection after-commit did not fire"
[ "$(qraw "select count(*) from usage where name like 'crashB%'")" = 3 ] || fail "rows missing after COMMIT"
ls -d "$AGENTOS_TELEMETRY_SPOOL"/batch.* >/dev/null 2>&1 || fail "batch dir should survive a crash after COMMIT"
ingest; ingest
[ "$(qraw "select count(*) from usage where name like 'crashB%'")" = 3 ] || fail "batch re-inserted after crash after COMMIT (duplicates)"
! ls -d "$AGENTOS_TELEMETRY_SPOOL"/batch.* >/dev/null 2>&1 && [ "$(spooled)" = 0 ] || fail "spool not emptied after recovery"
[ "$(qraw "select count(*) from telemetry_ingest")" = 0 ] || fail "ingest markers not cleaned up"
ok "3 concurrent ingesters insert once; crash before COMMIT recovers; crash after COMMIT replays without duplicates"

# 10. ingest failure keeps the spool; min-age defers fresh files; Stop triggers a detached ingest
feed '{"session_id":"s10","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"kept"}}'
AGENTOS_TELEMETRY_DB="/nonexistent-dir/x.sqlite" "$INGEST" --quiet 2>/dev/null; [ $? = 1 ] || fail "ingest into unwritable DB must exit 1"
grep -q "agent-telemetry-ingest: ingest failed" "$AGENTOS_TELEMETRY_ERRLOG" || fail "ingest failure not logged"
[ "$(qraw "select count(*) from usage where name='kept'")" = 0 ] || fail "row from failed ingest"
ingest; [ "$(qraw "select count(*) from usage where name='kept'")" = 1 ] || fail "spool lost after a failed ingest"
feed '{"session_id":"s10","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"young"}}'
"$INGEST" --quiet --min-age 60 || fail "ingest --min-age"
[ "$(spooled)" = 1 ] && [ "$(qraw "select count(*) from usage where name='young'")" = 0 ] || fail "min-age did not defer a fresh file"
t0=$("$PY" -c 'import time; print(time.time())')
feed '{"session_id":"s10","transcript_path":"'"$TP2"'","cwd":"/tmp","hook_event_name":"Stop","last_assistant_message":"secret answer text"}'
dt=$("$PY" -c "import time; print(int((time.time()-$t0)*1000))")
for i in $(seq 1 50); do [ "$(qraw "select count(*) from sessions where session_id='s10' and stops=1")" = 1 ] && break; sleep 0.2; done
[ "$(qraw "select count(*) from sessions where session_id='s10' and stops=1")" = 1 ] || fail "Stop did not trigger a detached ingest"
[ "$(qraw "select count(*) from usage where name='young'")" = 1 ] || fail "detached ingest skipped the deferred file"
[ "$(qraw "select count(*) from sessions where session_id='s10' and (tool_counts like '%secret%' or last_error like '%secret%')")" = 0 ] || fail "Stop text leaked"
[ "$dt" -lt 1000 ] || fail "Stop hook took ${dt} ms (detached ingest must not add latency)"
ok "failed ingest keeps spool + logs; min-age defers fresh files; Stop hook returns in ${dt} ms and a detached ingest lands it"

sleep 0.3; ingest   # let any detached ingester finish before the temp dir goes away
echo "PASS: $pass checks (db: $AGENTOS_TELEMETRY_DB)"
[ -n "${KEEP:-}" ] || rm -rf "$TMP"
