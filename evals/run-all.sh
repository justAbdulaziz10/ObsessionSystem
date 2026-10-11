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

export HOME="$T" PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
git config --global user.name ci
git config --global user.email ci@example.invalid
git config --global init.defaultBranch main
# Both account slots exist, as the telemetry and overnight suites expect.
mkdir -p "$T/.claude" "$T/.claude_second"

"$REPO/install.sh" --with-claude-hooks >/dev/null || { echo "FAIL install"; exit 1; }

cd "$REPO"
fails=0
run() { # $1 label, rest: command
  local label=$1; shift
  printf '=== %s\n' "$label"
  if "$@"; then printf 'ok  %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fails=$((fails+1)); fi
}
run ship        zsh  evals/ship/regression.sh
run autopilot   zsh  evals/autopilot/worktrees.sh
run overnight   bash evals/overnight/regression.sh
run telemetry   bash evals/telemetry/regression.sh
run skill-lint  agent-skill-lint

echo
[ "$fails" = 0 ] && echo "all suites passed" || echo "$fails suite(s) failed"
exit "$fails"
