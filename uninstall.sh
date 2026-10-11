#!/usr/bin/env bash
# Removes what install.sh linked from this checkout. Keeps your data:
# ~/.agent-os state (config, decisions, lessons, telemetry, task DB) stays unless you pass --purge.
#   ./uninstall.sh [--dry-run] [--purge]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0 PURGE=0
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --purge) PURGE=1 ;; *) echo "unknown option: $a" >&2; exit 2 ;; esac; done
run() { if [ "$DRY" = 1 ]; then echo "  \$ $*"; else "$@"; fi; }

# Every symlink under these roots that points into this checkout.
for root in "$HOME/bin" "$HOME/.agent-os" "$HOME/.agents/skills" "$HOME/.claude/agents" "$HOME/.claude"; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 3 -type l 2>/dev/null | while read -r l; do
    case "$(readlink "$l")" in "$REPO"/*) run rm "$l"; echo "  - ${l/#$HOME/~}" ;; esac
  done
done

if [ "$(git config --global core.hooksPath || true)" = "$HOME/.agent-os/git-hooks" ]; then
  run git config --global --unset core.hooksPath; echo "  - core.hooksPath"
fi

if [ "$(uname)" = Darwin ]; then
  for p in "$HOME"/Library/LaunchAgents/com.agentos.*.plist; do
    [ -e "$p" ] || continue
    run launchctl unload -w "$p" 2>/dev/null || true; run rm "$p"; echo "  - $(basename "$p")"
  done
fi

echo "Claude hooks in ~/.claude/settings.json were left in place; remove the agent-* entries by hand (a .bak was made at install)."
if [ "$PURGE" = 1 ]; then run rm -rf "$HOME/.agent-os"; echo "  - ~/.agent-os (purged)"; fi
echo "Done."
