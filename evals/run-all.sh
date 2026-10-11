#!/usr/bin/env bash
# Install into a throwaway $HOME and run every regression suite against it.
# Used by CI and safe to run locally: nothing outside the temp dir is touched.
#
#   evals/run-all.sh            run all suites, exit non-zero on any failure
#   KEEP=1 evals/run-all.sh     keep the temp home for inspection
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/os-ci.XXXXXX")"
[ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$T"' EXIT

# Point everything at the temp home. Variables that name config directories
# would otherwise send the installer and the suites to the real ones.
unset CLAUDE_CONFIG_DIR CODEX_HOME AGENT_SHIP_DIR AGENT_CODEX_JOBS CODEX_HA_HOMES GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
for v in $(env | sed -n 's/^\(AGENTOS_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T" PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
git config --global user.name ci
git config --global user.email ci@example.invalid
git config --global init.defaultBranch main
# A second Claude config dir; the telemetry suite names it in AGENT_CLAUDE_DIRS.
mkdir -p "$T/.claude" "$T/.claude_second"

"$REPO/install.sh" --with-hooks --with-git-hooks >/dev/null || { echo "FAIL install"; exit 1; }

cd "$REPO"
fails=0
run() { # $1 label, rest: command
  local label=$1; shift
  printf '=== %s\n' "$label"
  if "$@"; then printf 'ok  %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fails=$((fails+1)); fi
}
run ship        zsh  evals/ship/regression.sh
run tasks       bash evals/tasks/regression.sh
run codex       bash evals/codex/regression.sh
run overnight   bash evals/overnight/regression.sh
run telemetry   bash evals/telemetry/regression.sh
run install     bash evals/install/regression.sh
run skill-lint  agent-skill-lint

echo
[ "$fails" = 0 ] && echo "all suites passed" || echo "$fails suite(s) failed"
exit "$fails"
