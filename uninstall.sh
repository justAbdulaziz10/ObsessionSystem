#!/usr/bin/env bash
# Reverse install.sh.
#
#   ./uninstall.sh            remove what install.sh created, the CLAUDE.md block,
#                             the hooks it added and core.hooksPath
#   ./uninstall.sh --purge    also delete ~/.agent-os (config, task records, telemetry)
#   ./uninstall.sh --dry-run  print what would change, change nothing
#
# Only paths listed in ~/.agent-os/install-manifest.tsv are removed, and only
# if unchanged since install: a link still pointing where it did, a copy
# (install.sh --copy) with the same content. Anything else is kept and reported.
# Files it edits (CLAUDE.md, settings.json) are backed up first, in every Claude
# config dir the manifest lists, plus $CLAUDE_CONFIG_DIR and $AGENT_CLAUDE_DIRS.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HOME/.agent-os/install-manifest.tsv"
CLAUDE_DIRS=()
add_dir() {
  local c="${1/#\~/$HOME}" s
  c="${c%/}"; [ -n "$c" ] || return 0
  for s in ${CLAUDE_DIRS[@]+"${CLAUDE_DIRS[@]}"}; do
    if [ "$s" = "$c" ] || [ "$s" -ef "$c" ]; then return 0; fi
  done
  CLAUDE_DIRS+=("$c")
}
add_dir "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
IFS=: read -ra _extra <<<"${AGENT_CLAUDE_DIRS:-}"
for _c in ${_extra[@]+"${_extra[@]}"}; do add_dir "$_c"; done
if [ -f "$MANIFEST" ]; then
  while IFS=$'\t' read -r _k _c _; do [ "$_k" = config ] && add_dir "$_c"; done < "$MANIFEST"
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0 PURGE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done
run() { if [ "$DRY" = 1 ]; then printf '    $ %s\n' "$*"; else "$@"; fi; }
gone() { printf '  - %s\n' "${1/#$HOME/~}"; }
kept() { printf '  = %s\n' "${1/#$HOME/~}"; }
# treesum PATH: the same function as in install.sh; keep them identical.
treesum() {
  if [ -d "$1" ]; then
    (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then printf 'L %s %s\n' "$f" "$(readlink "$f")"
      elif [ -d "$f" ]; then printf 'D %s\n' "$f"
      else printf 'F %s ' "$f"; cksum < "$f"; fi
    done) | cksum
  else cksum < "$1"; fi
}

if [ -f "$MANIFEST" ]; then
  # Reverse order of creation, so links inside a copied directory go first.
  while IFS=$'\t' read -r kind dest value; do
    case "$kind" in
      link)
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$value" ]; then run rm "$dest"; gone "$dest"
        elif [ -e "$dest" ] || [ -L "$dest" ]; then kept "$dest (changed since install, left alone)"; fi ;;
      copy)
        if [ -L "$dest" ]; then kept "$dest (now a link, left alone)"
        elif [ -e "$dest" ] && [ "$(treesum "$dest")" = "$value" ]; then run rm -rf "$dest"; gone "$dest"
        elif [ -e "$dest" ]; then kept "$dest (edited since install, left alone)"; fi ;;
    esac
  done < <(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' "$MANIFEST")
  run rm "$MANIFEST"
else
  echo "No install manifest; removing links that point into this checkout."
  roots=("$HOME/bin" "$HOME/.agent-os" "$HOME/.agents/skills")
  for c in "${CLAUDE_DIRS[@]}"; do roots+=("$c/agents" "$c/skills"); done
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    find -H "$root" -maxdepth 2 -type l 2>/dev/null | while read -r l; do
      case "$(readlink "$l")" in "$REPO"/*) run rm "$l"; gone "$l" ;; esac
    done
  done
fi

# clean_claude_dir DIR: remove the rules import block and our hooks from one config dir.
clean_claude_dir() {
  local MD="$1/CLAUDE.md" S="$1/settings.json"
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

  [ -f "$S" ] || return 0
  if [ "$DRY" = 1 ]; then printf '    remove our hook entries from %s\n' "${S/#$HOME/~}"; return 0; fi
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
}

for c in "${CLAUDE_DIRS[@]}"; do clean_claude_dir "$c"; done

if [ "$(git config --global core.hooksPath || true)" = "$HOME/.agent-os/git-hooks" ]; then
  run git config --global --unset core.hooksPath; gone "git core.hooksPath"
fi

if [ "$PURGE" = 1 ] && [ -d "$HOME/.agent-os" ]; then run rm -rf "$HOME/.agent-os"; gone "$HOME/.agent-os"; fi
echo "Done."
