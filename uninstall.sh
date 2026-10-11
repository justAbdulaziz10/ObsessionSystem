#!/usr/bin/env bash
# Reverse install.sh.
#
#   ./uninstall.sh            remove what install.sh created, the CLAUDE.md block,
#                             the hooks it added and core.hooksPath
#   ./uninstall.sh --purge    also delete ~/.agent-os (config, task records, telemetry)
#   ./uninstall.sh --dry-run  print what would change, change nothing
#
# Only paths listed in ~/.agent-os/install-manifest.tsv are removed. A copied
# file (install.sh --copy) you have since edited is kept and reported.
# Files it edits (CLAUDE.md, settings.json) are backed up first.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MANIFEST="$HOME/.agent-os/install-manifest.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0 PURGE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done
run() { if [ "$DRY" = 1 ]; then printf '    $ %s\n' "$*"; else "$@"; fi; }
gone() { printf '  - %s\n' "${1/#$HOME/~}"; }
kept() { printf '  = %s\n' "${1/#$HOME/~}"; }

if [ -f "$MANIFEST" ]; then
  # Reverse order of creation, so links inside a copied directory go first.
  while IFS=$'\t' read -r kind dest src; do
    case "$kind" in
      link)
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then run rm "$dest"; gone "$dest"
        elif [ -e "$dest" ] || [ -L "$dest" ]; then kept "$dest (changed since install, left alone)"; fi ;;
      copy)
        if [ ! -e "$dest" ]; then continue; fi
        if [ -e "$src" ] && diff -rq "$src" "$dest" >/dev/null 2>&1; then run rm -rf "$dest"; gone "$dest"
        else kept "$dest (copy differs from the checkout or the checkout is gone; remove it yourself)"; fi ;;
    esac
  done < <(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' "$MANIFEST")
  run rm "$MANIFEST"
else
  echo "No install manifest; removing links that point into this checkout."
  for root in "$HOME/bin" "$HOME/.agent-os" "$HOME/.agents/skills" "$CLAUDE/agents" "$CLAUDE/skills"; do
    [ -d "$root" ] || continue
    find -H "$root" -maxdepth 2 -type l 2>/dev/null | while read -r l; do
      case "$(readlink "$l")" in "$REPO"/*) run rm "$l"; gone "$l" ;; esac
    done
  done
fi

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

S="$CLAUDE/settings.json"
if [ -f "$S" ] && [ "$DRY" = 0 ]; then
  python3 - "$S" "$REPO/templates/claude/settings.hooks.json" "$STAMP" <<'PY'
import json, os, shutil, sys
dst, src, stamp = sys.argv[1:]
ours = {h["command"] for gs in json.load(open(src))["hooks"].values() for g in gs for h in g["hooks"]}
cur = json.load(open(dst))
hooks = cur.get("hooks", {})
changed = False
for event in list(hooks):
    groups = [g for g in hooks[event] if not any(h.get("command") in ours for h in g.get("hooks", []))]
    if len(groups) != len(hooks[event]):
        changed = True
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]
if not changed:
    sys.exit(0)
shutil.copy2(dst, f"{dst}.bak-{stamp}")
if not hooks:
    cur.pop("hooks", None)
shown = dst.replace(os.path.expanduser("~"), "~", 1)
if cur:
    with open(dst, "w") as f:
        json.dump(cur, f, indent=2)
        f.write("\n")
else:
    os.remove(dst)  # nothing left but what install.sh added
print(f"  - {shown} (hooks; backup {shown}.bak-{stamp})")
PY
elif [ -f "$S" ]; then
  printf '    remove our hook entries from %s\n' "${S/#$HOME/~}"
fi

if [ "$(git config --global core.hooksPath || true)" = "$HOME/.agent-os/git-hooks" ]; then
  run git config --global --unset core.hooksPath; gone "git core.hooksPath"
fi

if [ "$PURGE" = 1 ] && [ -d "$HOME/.agent-os" ]; then run rm -rf "$HOME/.agent-os"; gone "$HOME/.agent-os"; fi
echo "Done."
