#!/usr/bin/env bash
# install.sh / uninstall.sh scenarios, each in its own throwaway HOME with a
# fresh copy of the checkout. Run by evals/run-all.sh; safe to run alone.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CODEX_HOME AGENT_CLAUDE_DIRS GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
export GIT_CONFIG_NOSYSTEM=1
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/os-install.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TOP"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
sum() { cksum | cut -d' ' -f1; }
fresh() {
  HOME="$(mktemp -d "$TOP/home.XXXXXX")"; export HOME
  R="$HOME/checkout"; mkdir -p "$R"
  for p in bin policy skills agents templates git-hooks install.sh uninstall.sh; do cp -R "$SRC/$p" "$R/"; done
}

echo "-- 1. plain install, idempotent, full uninstall leaves nothing"
fresh
"$R/install.sh" --with-hooks --with-git-hooks >/dev/null
check "manifest exists" '[ -s "$HOME/.agent-os/install-manifest.tsv" ]'
check "skill linked twice" '[ -L "$HOME/.agents/skills/correct" ] && [ -L "$HOME/.claude/skills/correct" ]'
before="$(sort "$HOME/.agent-os/install-manifest.tsv" | sum)"
out="$("$R/install.sh" --with-hooks --with-git-hooks)"
check "second install changes nothing" '! grep -q "^  + " <<<"$out"'
check "manifest unchanged" '[ "$(sort "$HOME/.agent-os/install-manifest.tsv" | sum)" = "$before" ]'
check "no settings backup on rerun" '[ -z "$(ls "$HOME/.claude/" | grep settings.json.bak)" ]'
"$R/uninstall.sh" >/dev/null
check "no links left" '[ -z "$(find "$HOME" -type l -not -path "$R/*" 2>/dev/null)" ]'
check "settings.json removed" '[ ! -e "$HOME/.claude/settings.json" ]'
check "CLAUDE.md removed" '[ ! -e "$HOME/.claude/CLAUDE.md" ]'
check "hooksPath unset" '[ -z "$(git config --global core.hooksPath)" ]'
check "user data kept" '[ -f "$HOME/.agent-os/config.json" ]'

echo "-- 2. pre-existing user link to ~/.agents/skills/<n> survives uninstall"
fresh
mkdir -p "$HOME/.agents/skills/correct" "$HOME/.claude/skills"
ln -s "$HOME/.agents/skills/correct" "$HOME/.claude/skills/correct"
"$R/install.sh" >/dev/null
"$R/uninstall.sh" >/dev/null
check "user's claude link kept" '[ -L "$HOME/.claude/skills/correct" ]'
check "user's skill dir kept" '[ -d "$HOME/.agents/skills/correct" ] && [ ! -L "$HOME/.agents/skills/correct" ]'

echo "-- 3. ~/.claude/skills is a symlink to ~/.agents/skills"
fresh
mkdir -p "$HOME/.agents/skills" "$HOME/.claude"
ln -s "$HOME/.agents/skills" "$HOME/.claude/skills"
"$R/install.sh" >/dev/null
check "no self-link loop" '[ -L "$HOME/.agents/skills/correct" ] && [ "$(readlink "$HOME/.agents/skills/correct")" = "$R/skills/correct" ]'
"$R/uninstall.sh" >/dev/null
check "skills removed" '[ -z "$(ls -A "$HOME/.agents/skills")" ]'
check "user's dir link kept" '[ -L "$HOME/.claude/skills" ]'

echo "-- 4. moved checkout: reinstall relinks, uninstall cleans"
fresh
"$R/install.sh" >/dev/null
mv "$R" "$HOME/moved"; R="$HOME/moved"
check "links dangle after move" '[ ! -e "$HOME/bin/agent-ship" ]'
"$R/install.sh" >/dev/null
check "relinked to new place" '[ "$(readlink "$HOME/bin/agent-ship")" = "$R/bin/agent-ship" ]'
"$R/uninstall.sh" >/dev/null
check "no links left" '[ -z "$(find "$HOME" -type l -not -path "$R/*" 2>/dev/null)" ]'

echo "-- 5. --copy: unchanged copies removed, edited copy kept"
fresh
"$R/install.sh" --copy >/dev/null
check "copied, not linked" '[ -f "$HOME/bin/agent-ship" ] && [ ! -L "$HOME/bin/agent-ship" ]'
echo "# mine" >> "$HOME/bin/agent-task"
out="$("$R/uninstall.sh")"
check "unchanged copy removed" '[ ! -e "$HOME/bin/agent-ship" ]'
check "edited copy kept" '[ -f "$HOME/bin/agent-task" ]'
check "edited copy reported" 'grep -q "agent-task (edited since install" <<<"$out"'
check "copied skill dir removed" '[ ! -e "$HOME/.agents/skills/correct" ]'

echo "-- 6. dry runs change nothing"
fresh
"$R/install.sh" --dry-run --with-hooks --with-git-hooks >/dev/null
# (macOS's system python3 may create ~/Library/Caches; that is not the installer.)
check "install dry-run wrote nothing" '[ -z "$(ls -A "$HOME" | grep -v -e "^checkout$" -e "^Library$")" ]'
"$R/install.sh" --with-hooks >/dev/null
snap="$(find "$HOME" -not -path "*/checkout/*" | sort | sum)"
"$R/uninstall.sh" --dry-run >/dev/null
check "uninstall dry-run wrote nothing" '[ "$(find "$HOME" -not -path "*/checkout/*" | sort | sum)" = "$snap" ]'

echo "-- 7. existing CLAUDE.md and settings.json are preserved"
fresh
mkdir -p "$HOME/.claude"
printf '# my rules\nbe nice\n' > "$HOME/.claude/CLAUDE.md"
printf '{"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "mine"}]}]}}\n' > "$HOME/.claude/settings.json"
"$R/install.sh" --with-hooks >/dev/null
check "block appended" 'grep -q "obsession-system:begin" "$HOME/.claude/CLAUDE.md" && grep -q "be nice" "$HOME/.claude/CLAUDE.md"'
"$R/uninstall.sh" >/dev/null
check "CLAUDE.md restored" '[ "$(cat "$HOME/.claude/CLAUDE.md")" = "$(printf "# my rules\nbe nice")" ]'
check "settings keeps user hook and model" 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"model\"]==\"x\" and d[\"hooks\"]==({\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"mine\"}]}]})" "$HOME/.claude/settings.json"'

echo "-- 8. uninstall without our hooks does not back up settings.json"
fresh
mkdir -p "$HOME/.claude"; echo '{"model": "x"}' > "$HOME/.claude/settings.json"
"$R/install.sh" >/dev/null
"$R/uninstall.sh" >/dev/null
check "no settings backup" '[ -z "$(ls "$HOME/.claude" | grep settings.json.bak)" ]'

echo "-- 9. pre-existing file in ~/bin is left alone"
fresh
mkdir -p "$HOME/bin"; echo mine > "$HOME/bin/agent-ship"
out="$("$R/install.sh")"
check "reported" 'grep -q "agent-ship exists, left alone" <<<"$out"'
"$R/uninstall.sh" >/dev/null
check "user file kept" '[ "$(cat "$HOME/bin/agent-ship")" = mine ]'

echo "-- 10. --purge"
fresh
"$R/install.sh" >/dev/null; "$R/uninstall.sh" --purge >/dev/null
check "agent-os gone" '[ ! -e "$HOME/.agent-os" ]'

echo "-- 11. AGENT_CLAUDE_DIRS: every listed dir is set up and cleaned, each once"
fresh
export AGENT_CLAUDE_DIRS="$HOME/.claude_second:~/.claude:$HOME/.claude_second/"
out="$("$R/install.sh" --with-hooks)"
check "second dir has skills and agents" '[ -L "$HOME/.claude_second/skills/correct" ] && [ -L "$HOME/.claude_second/agents/agent-risk-reviewer.md" ]'
check "second dir has rules and hooks" 'grep -q obsession-system "$HOME/.claude_second/CLAUDE.md" && grep -q agent-telemetry-hook "$HOME/.claude_second/settings.json"'
check "each dir set up once" '[ "$(grep -c "^Claude Code -> " <<<"$out")" = 2 ]'
"$R/uninstall.sh" >/dev/null
check "both dirs cleaned, backups kept" '[ -z "$(find "$HOME/.claude" "$HOME/.claude_second" -mindepth 1 \( -type l -o -type f \) -not -name "*.bak-*")" ] && ls "$HOME/.claude_second" | grep -q "settings.json.bak-"'
unset AGENT_CLAUDE_DIRS

echo "-- 12. --copy: an edited skill reached through a re-pointed skills dir is kept"
fresh
"$R/install.sh" --copy >/dev/null
rm -rf "$HOME/.claude/skills" && ln -s "$HOME/.agents/skills" "$HOME/.claude/skills"
echo "my note" >> "$HOME/.agents/skills/correct/SKILL.md"
"$R/uninstall.sh" >/dev/null
check "edited skill kept" 'grep -q "my note" "$HOME/.agents/skills/correct/SKILL.md"'
check "unedited skill removed" '[ ! -e "$HOME/.agents/skills/diagnosing-bugs" ]'
fresh
"$R/install.sh" --copy >/dev/null
mkdir "$HOME/.agents/skills/correct/my-notes"
"$R/uninstall.sh" >/dev/null
check "copy with an added empty folder kept" '[ -d "$HOME/.agents/skills/correct/my-notes" ]'

echo "-- 13. --copy: a changed checkout does not pin unedited copies"
fresh
"$R/install.sh" --copy >/dev/null
echo "# newer" >> "$R/bin/agent-ship"
out="$("$R/install.sh" --copy)"
check "reinstall updates the unedited copy" 'grep -q "# newer" "$HOME/bin/agent-ship"'
check "other copies left as they were" 'grep -q "agent-task (already copied)" <<<"$out"'
echo "# older checkout again" >> "$R/bin/agent-task"
"$R/uninstall.sh" >/dev/null
check "unedited copies removed after the checkout changed" '[ -z "$(ls -A "$HOME/bin")" ]'

echo "-- 14. a recorded link the user re-pointed is theirs"
fresh
"$R/install.sh" >/dev/null
echo mine > "$HOME/my-recall"; rm "$HOME/bin/agent-recall"; ln -s "$HOME/my-recall" "$HOME/bin/agent-recall"
"$R/install.sh" >/dev/null
check "reinstall leaves it" '[ "$(readlink "$HOME/bin/agent-recall")" = "$HOME/my-recall" ]'
"$R/uninstall.sh" >/dev/null
check "uninstall leaves it" '[ "$(readlink "$HOME/bin/agent-recall")" = "$HOME/my-recall" ]'

echo "-- 15. uninstall finds config dirs from the manifest, without AGENT_CLAUDE_DIRS"
fresh
AGENT_CLAUDE_DIRS="$HOME/.claude_second" "$R/install.sh" --with-hooks >/dev/null
"$R/uninstall.sh" >/dev/null
check "second dir block and hooks removed" '[ ! -e "$HOME/.claude_second/CLAUDE.md" ] && [ ! -e "$HOME/.claude_second/settings.json" ]'

echo "-- 16. a HOME with a space in it"
fresh
SP="$HOME/with space"; mkdir -p "$SP"; mv "$R" "$SP/"; R="$SP/checkout"; HOME="$SP"
"$R/install.sh" --with-hooks >/dev/null
check "installed" '[ -L "$HOME/bin/agent-ship" ] && [ -L "$HOME/.claude/skills/correct" ]'
"$R/uninstall.sh" >/dev/null
check "nothing left" '[ -z "$(find "$HOME" -type l -not -path "$R/*")" ] && [ ! -e "$HOME/.claude/settings.json" ]'

exit $fail
