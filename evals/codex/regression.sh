#!/usr/bin/env bash
# Regression tests for the optional Codex add-on (bin/codex-ha, bin/agent-codex).
# Runs entirely in a throwaway HOME with a stub `codex` on PATH: the real
# Codex CLI, real ~/.codex and real ~/.agent-os are never touched.
#
#   bash evals/codex/regression.sh       exit non-zero on any failure
#   KEEP=1 bash evals/codex/regression.sh  keep the temp dir for inspection
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/codex-eval.XXXXXX")" && T="$(cd "$T" && pwd -P)"
[ "${KEEP:-0}" = 1 ] && echo "temp dir: $T" || trap 'rm -rf "$T"' EXIT

PY="$(command -v python3)" || { echo "FAIL python3 not found"; exit 1; }
export HOME="$T/home"
mkdir -p "$HOME/bin" "$T/stub" "$T/tools" "$T/work"
export CODEX_STUB_LOG="$T/codex.log"
export STORAGE_MARKER="$T/agent-storage-ran"
unset CODEX_HA_MODEL CODEX_HA_EFFORT CODEX_HA_HOMES CODEX_HA_ALL_MCPS CODEX_HOME AGENT_CODEX_JOBS

# python3 only (no real codex can leak in through its directory).
ln -s "$PY" "$T/tools/python3"

# Stub codex: logs argv + CODEX_HOME; `login status` succeeds only when
# $CODEX_HOME/LOGGED_IN exists; `exec` prints a fake result.
cat > "$T/stub/codex" <<'X'
#!/bin/sh
{ printf 'CODEX_HOME=%s ARGV:' "${CODEX_HOME-}"; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >> "$CODEX_STUB_LOG"
if [ "${1-}" = login ] && [ "${2-}" = status ]; then
  if [ -f "${CODEX_HOME-/nonexistent}/LOGGED_IN" ]; then echo "Logged in using ChatGPT"; exit 0; fi
  echo "Not logged in"; exit 1
fi
for a in "$@"; do
  if [ "$a" = exec ]; then echo "STUB_CODEX_RESULT done"; exit 0; fi
done
echo "stub codex: unexpected args" >&2; exit 2
X
# Stub agent-storage: must never run.
cat > "$T/stub/agent-storage" <<'X'
#!/bin/sh
touch "$STORAGE_MARKER"
X
chmod +x "$T/stub/codex" "$T/stub/agent-storage"

# Scripts under test, also reachable as $HOME/bin/* for anything that insists.
ln -s "$REPO/bin/codex-ha" "$HOME/bin/codex-ha"
ln -s "$REPO/bin/agent-codex" "$HOME/bin/agent-codex"

SYS=/usr/bin:/bin:/usr/sbin:/sbin
WITH_CODEX="$REPO/bin:$T/stub:$T/tools:$SYS"
NO_CODEX="$REPO/bin:$T/tools:$SYS"

pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1${2:+: $2}"; fail=$((fail+1)); }
reset_home() { rm -rf "$HOME/.codex" "$HOME/.codex_second" "$HOME/.codex-ha" "$HOME/.agent-os"; : > "$CODEX_STUB_LOG"; }
ready() { (cd "$T/work" && PATH="$1" codex-ha ready 2>&1); }

# --- no codex binary -> 75
reset_home; mkdir -p "$HOME/.codex"; touch "$HOME/.codex/LOGGED_IN"
if PATH="$NO_CODEX" command -v codex >/dev/null 2>&1; then
  bad no_codex_binary_ready_75 "a codex binary exists in $SYS; cannot test"
else
  out="$(ready "$NO_CODEX")"; rc=$?
  if [ "$rc" = 75 ] && grep -q AGENT_CODEX_HA_EXHAUSTED <<<"$out" && grep -q "codex CLI not found" <<<"$out"; then
    ok no_codex_binary_ready_75
  else bad no_codex_binary_ready_75 "rc=$rc out=$out"; fi
fi

# --- no ~/.codex at all -> 75
reset_home
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 75 ] && grep -q "does not exist" <<<"$out" && ok no_codex_home_ready_75 || bad no_codex_home_ready_75 "rc=$rc out=$out"

# --- ~/.codex exists, not logged in -> 75 with reason
reset_home; mkdir -p "$HOME/.codex"
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 75 ] && grep -q AGENT_CODEX_HA_EXHAUSTED <<<"$out" && grep -q "not logged in" <<<"$out" \
  && ok not_logged_in_ready_75 || bad not_logged_in_ready_75 "rc=$rc out=$out"
grep -qF "CODEX_HOME=$HOME/.codex ARGV: [login] [status]" "$CODEX_STUB_LOG" \
  && ok login_status_uses_codex_home || bad login_status_uses_codex_home "$(cat "$CODEX_STUB_LOG")"
out="$(cd "$T/work" && PATH="$WITH_CODEX" codex-ha status 2>&1)"
grep -q "codex1 ~/.codex: NOT READY: not logged in (run: codex login)" <<<"$out" \
  && ! grep -qi "AVAILABLE\|codex2" <<<"$out" && ok status_reports_not_logged_in || bad status_reports_not_logged_in "$out"

# --- logged in -> ready 0 listing codex1; second home absent -> not listed
reset_home; mkdir -p "$HOME/.codex"; touch "$HOME/.codex/LOGGED_IN"
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "CODEX_HA_READY codex1" ] && ok logged_in_ready_codex1 || bad logged_in_ready_codex1 "rc=$rc out=$out"
[ "$rc" = 0 ] && ! grep -q codex2 <<<"$out" && ok second_home_absent_not_listed || bad second_home_absent_not_listed "$out"

# --- second home present + logged in -> listed
mkdir -p "$HOME/.codex_second"; touch "$HOME/.codex_second/LOGGED_IN"
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 0 ] && grep -q "codex1,codex2" <<<"$out" && ok second_home_logged_in_listed || bad second_home_logged_in_listed "rc=$rc out=$out"

# --- second home present but not logged in -> not ready, not listed
rm -f "$HOME/.codex_second/LOGGED_IN"
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "CODEX_HA_READY codex1" ] && ok second_home_not_logged_in_excluded || bad second_home_not_logged_in_excluded "rc=$rc out=$out"

# --- cooldown still excludes a logged-in account
rm -rf "$HOME/.codex_second"
mkdir -p "$HOME/.codex-ha"
"$PY" -c 'import json,sys,time; json.dump({"preferred":"codex1","accounts":{"codex1":{"blocked_until":time.time()+3600}}}, open(sys.argv[1],"w"))' "$HOME/.codex-ha/state.json"
out="$(ready "$WITH_CODEX")"; rc=$?
[ "$rc" = 75 ] && grep -q "cooldown" <<<"$out" && ok cooldown_excludes_account || bad cooldown_excludes_account "rc=$rc out=$out"

exec_line() { grep 'ARGV:.*\[exec\]' "$CODEX_STUB_LOG" | tail -n 1; }
run_task() { (cd "$T/work" && PATH="$WITH_CODEX" "$@" codex-ha run "say hi" >"$T/run.out" 2>&1); }

# --- default exec passes no --model and no effort override
reset_home; mkdir -p "$HOME/.codex"; touch "$HOME/.codex/LOGGED_IN"
run_task env; rc=$?; line="$(exec_line)"
if [ "$rc" = 0 ] && [ -n "$line" ] && ! grep -q -- "--model" <<<"$line" && ! grep -q "model_reasoning_effort" <<<"$line"; then
  ok default_exec_no_model
else bad default_exec_no_model "rc=$rc line=$line"; fi
grep -q '\[--ask-for-approval\] \[never\] \[exec\] \[--ephemeral\] \[--sandbox\] \[workspace-write\] \[--skip-git-repo-check\] \[--\] \[say hi\]' <<<"$line" \
  && ok default_exec_exact_flags || bad default_exec_exact_flags "$line"
grep -q "STUB_CODEX_RESULT" "$T/run.out" && ok run_streams_codex_output || bad run_streams_codex_output "$(cat "$T/run.out")"

# --- CODEX_HA_MODEL / CODEX_HA_EFFORT env overrides
: > "$CODEX_STUB_LOG"
run_task env CODEX_HA_MODEL=foo CODEX_HA_EFFORT=high; rc=$?; line="$(exec_line)"
[ "$rc" = 0 ] && grep -q '\[--model\] \[foo\]' <<<"$line" && ok env_model_passed || bad env_model_passed "rc=$rc line=$line"
grep -q '\[-c\] \[model_reasoning_effort="high"\]' <<<"$line" && ok env_effort_passed || bad env_effort_passed "$line"

# --- config.json codex_model / codex_effort used when env unset; env wins over config
mkdir -p "$HOME/.agent-os"
cat > "$HOME/.agent-os/config.json" <<'X'
{"codex_model": "cfg-model", "codex_effort": "medium", "worker_disabled_mcps": ["mailbox"], "worker_disabled_plugins": ["foo@bar"]}
X
: > "$CODEX_STUB_LOG"
run_task env; rc=$?; line="$(exec_line)"
[ "$rc" = 0 ] && grep -q '\[--model\] \[cfg-model\]' <<<"$line" && grep -q 'model_reasoning_effort="medium"' <<<"$line" \
  && ok config_model_used || bad config_model_used "rc=$rc line=$line"
grep -q '\[mcp_servers.mailbox.enabled=false\]' <<<"$line" && grep -q '\[plugins."foo@bar".enabled=false\]' <<<"$line" \
  && ok config_worker_disabled_mcps || bad config_worker_disabled_mcps "$line"
: > "$CODEX_STUB_LOG"
run_task env CODEX_HA_MODEL=foo; line="$(exec_line)"
grep -q '\[--model\] \[foo\]' <<<"$line" && ! grep -q cfg-model <<<"$line" && ok env_model_beats_config || bad env_model_beats_config "$line"
echo '{"codex_model": null, "codex_effort": null}' > "$HOME/.agent-os/config.json"
: > "$CODEX_STUB_LOG"
run_task env; line="$(exec_line)"
! grep -q -- "--model\|model_reasoning_effort\|enabled=false" <<<"$line" && ok config_null_means_default || bad config_null_means_default "$line"

# --- agent-codex --detach --file, then --wait, with no agent-storage call
reset_home; mkdir -p "$HOME/.codex"; touch "$HOME/.codex/LOGGED_IN"; rm -f "$STORAGE_MARKER"
printf 'brief: say hi\n' > "$T/work/brief.md"
out="$(cd "$T/work" && PATH="$WITH_CODEX" agent-codex --detach --file brief.md 2>&1)"; rc=$?
job="$(sed -n 's/^AGENT_CODEX_STARTED job=\([^ ]*\).*/\1/p' <<<"$out")"
[ "$rc" = 0 ] && [ -n "$job" ] && [ ! -e "$T/work/brief.md" ] && ok agent_codex_detach || bad agent_codex_detach "rc=$rc out=$out"
wout=""; wrc=1
for _ in 1 2 3 4 5 6; do
  wout="$(cd "$T/work" && PATH="$WITH_CODEX" agent-codex --wait "$job" 30 2>&1)"; wrc=$?
  grep -q AGENT_CODEX_RUNNING <<<"$wout" || break
done
[ "$wrc" = 0 ] && grep -q "AGENT_CODEX_DONE job=$job exit=0" <<<"$wout" && grep -q STUB_CODEX_RESULT <<<"$wout" \
  && ok agent_codex_wait_done || bad agent_codex_wait_done "rc=$wrc out=$wout"
[ ! -e "$STORAGE_MARKER" ] && ok agent_codex_no_agent_storage || bad agent_codex_no_agent_storage "agent-storage was invoked"

# --- agent-codex --detach refuses with 75 when no account is ready
rm -f "$HOME/.codex/LOGGED_IN"
out="$(cd "$T/work" && PATH="$WITH_CODEX" agent-codex --detach "say hi" 2>&1)"; rc=$?
[ "$rc" = 75 ] && grep -q AGENT_CODEX_EXHAUSTED <<<"$out" && grep -q "not logged in" <<<"$out" \
  && ok agent_codex_detach_75 || bad agent_codex_detach_75 "rc=$rc out=$out"
[ ! -e "$STORAGE_MARKER" ] && ok agent_codex_never_agent_storage || bad agent_codex_never_agent_storage

echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
