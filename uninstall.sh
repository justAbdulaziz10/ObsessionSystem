#!/usr/bin/env bash
# Reverse install.sh.
#
#   ./uninstall.sh            remove links, the CLAUDE.md block, hooks and core.hooksPath
#   ./uninstall.sh --purge    also delete ~/.agent-os (config, task records, telemetry)
#   ./uninstall.sh --dry-run  print what would change, change nothing
#
# Files it edits (CLAUDE.md, settings.json) are backed up first. Copies made
# with install.sh --copy are not links and must be removed by hand.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0 PURGE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done
run() { if [ "$DRY" = 1 ]; then printf '    $ %s\n' "$*"; else "$@"; fi; }
gone() { printf '  - %s\n' "${1/#$HOME/~}"; }

# Links that point into this checkout, and skill links in the Claude dir that point at those.
for root in "$HOME/bin" "$HOME/.agent-os" "$HOME/.agents/skills" "$CLAUDE/agents" "$CLAUDE/skills"; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 2 -type l 2>/dev/null | while read -r l; do
    t="$(readlink "$l")"
    ours=0
    case "$t" in
      "$REPO"/*) ours=1 ;;
      "$HOME/.agents/skills/"*) if [ -d "$REPO/skills/$(basename "$t")" ]; then ours=1; fi ;;
    esac
    if [ "$ours" = 1 ]; then run rm "$l"; gone "$l"; fi
  done
done

MD="$CLAUDE/CLAUDE.md"
if [ -f "$MD" ] && grep -qF '<!-- obsession-system:begin -->' "$MD"; then
  run cp "$MD" "$MD.bak-$STAMP"
  [ "$DRY" = 1 ] || python3 - "$MD" <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"\n?<!-- obsession-system:begin -->.*?<!-- obsession-system:end -->\n?", "\n", s, flags=re.S)
if s.strip():
    open(p, "w").write(s.strip("\n") + "\n")
else:
    os.remove(p)  # the file held nothing but our block
PY
  gone "$MD (import block)"
fi

for CDIR in "$CLAUDE" "$HOME/.claude_second"; do
  S="$CDIR/settings.json"
  [ -f "$S" ] && grep -q '/bin/agent-' "$S" || continue
  run cp "$S" "$S.bak-$STAMP"
  [ "$DRY" = 1 ] || python3 - "$S" "$REPO/templates/claude/settings.hooks.json" <<'PY'
import json, os, sys
dst, src = sys.argv[1], sys.argv[2]
ours = {h["command"] for gs in json.load(open(src))["hooks"].values() for g in gs for h in g["hooks"]}
cur = json.load(open(dst))
hooks = cur.get("hooks", {})
for event in list(hooks):
    groups = [g for g in hooks[event] if not any(h.get("command") in ours for h in g.get("hooks", []))]
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]
if not hooks:
    cur.pop("hooks", None)
if not cur:
    os.remove(dst)  # nothing left but what install.sh added
    sys.exit(0)
with open(dst, "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
PY
  gone "$S (hooks)"
done

if [ "$(git config --global core.hooksPath || true)" = "$HOME/.agent-os/git-hooks" ]; then
  run git config --global --unset core.hooksPath; gone "git core.hooksPath"
fi

if [ "$PURGE" = 1 ] && [ -d "$HOME/.agent-os" ]; then run rm -rf "$HOME/.agent-os"; gone "$HOME/.agent-os"; fi
echo "Done."
