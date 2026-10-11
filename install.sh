#!/usr/bin/env bash
# Install ObsessionSystem for the current user.
#
#   ./install.sh                   commands, policy, skills, agents, CLAUDE.md import
#   ./install.sh --with-hooks      also add the Claude Code hooks to settings.json
#   ./install.sh --with-git-hooks  also set git's global core.hooksPath (pre-push guard)
#   ./install.sh --copy            copy files instead of symlinking to this checkout
#   ./install.sh --dry-run         print what would change, change nothing
#
# Claude Code files go to $CLAUDE_CONFIG_DIR (default ~/.claude) and to each
# directory in $AGENT_CLAUDE_DIRS (colon-separated), e.g. a second account.
#
# It never overwrites a file you already have: an existing path is left alone
# and reported. Files it edits (CLAUDE.md, settings.json) are backed up first.
# Everything it creates is listed in ~/.agent-os/install-manifest.tsv, which
# ./uninstall.sh uses to remove exactly that and nothing else.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AOS="$HOME/.agent-os"
BIN="$HOME/bin"
SKILLS="$HOME/.agents/skills"
# Claude Code config dirs: $CLAUDE_CONFIG_DIR (default ~/.claude), then each
# entry of $AGENT_CLAUDE_DIRS, once each.
CLAUDE_DIRS=()
IFS=: read -ra _extra <<<"${AGENT_CLAUDE_DIRS:-}"
for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ${_extra[@]+"${_extra[@]}"}; do
  [ -n "$_c" ] || continue
  _c="${_c/#\~/$HOME}"; _c="${_c%/}"
  for _s in ${CLAUDE_DIRS[@]+"${CLAUDE_DIRS[@]}"}; do
    if [ "$_s" = "$_c" ] || [ "$_s" -ef "$_c" ]; then continue 2; fi
  done
  CLAUDE_DIRS+=("$_c")
done

MANIFEST="$AOS/install-manifest.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)"
BEGIN='<!-- obsession-system:begin -->'
END='<!-- obsession-system:end -->'

DRY=0 COPY=0 HOOKS=0 GITHOOKS=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --copy) COPY=1 ;;
    --with-hooks) HOOKS=1 ;;
    --with-git-hooks) GITHOOKS=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

tilde() { printf '%s' "${1/#$HOME/~}"; }
ok()   { printf '  + %s\n' "$*"; }
keep() { printf '  = %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '    $ %s\n' "$*"; else "$@"; fi; }

# The manifest has one line per thing this installer created, kind<TAB>path<TAB>value:
#   link    path  link target
#   copy    path  checksum of the copied content (uninstall removes it only if unchanged)
#   config  dir   -   (a Claude config dir that got the import block and hooks)
recorded() { # recorded KIND PATH: print the value, fail if there is no such line
  [ -f "$MANIFEST" ] && K="$1" P="$2" awk -F'\t' '$1 == ENVIRON["K"] && $2 == ENVIRON["P"] { v = $3; f = 1 } END { if (f) print v; exit !f }' "$MANIFEST"
}
record() {
  [ "$DRY" = 1 ] && return 0
  mkdir -p "$AOS"
  if [ -f "$MANIFEST" ]; then
    P="$2" awk -F'\t' '$2 != ENVIRON["P"]' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  fi
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MANIFEST"
}
# treesum PATH: checksum of a file, or of every file name and content under a directory.
# uninstall.sh has the same function; keep them identical.
treesum() {
  if [ -d "$1" ]; then
    (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then printf 'L %s %s\n' "$f" "$(readlink "$f")"
      elif [ -d "$f" ]; then printf 'D %s\n' "$f"
      else printf 'F %s ' "$f"; cksum < "$f"; fi
    done) | cksum
  else cksum < "$1"; fi
}

# place SRC DEST: symlink (or copy) SRC to DEST unless something else is already there.
# What this installer made earlier and nobody changed since is updated: a link after the
# checkout moved, an unedited copy after the checkout changed.
place() {
  local src="$1" dest="$2" was
  if [ "$COPY" = 0 ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then keep "$(tilde "$dest") (already linked)"; return; fi
  if [ -L "$dest" ] && was="$(recorded link "$dest")" && [ "$(readlink "$dest")" = "$was" ]; then
    run rm "$dest"
  elif [ -e "$dest" ] && [ ! -L "$dest" ] && was="$(recorded copy "$dest")" && [ "$(treesum "$dest")" = "$was" ]; then
    if [ "$COPY" = 1 ] && [ "$(treesum "$src")" = "$was" ]; then keep "$(tilde "$dest") (already copied)"; return; fi
    run rm -rf "$dest"
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    keep "$(tilde "$dest") exists, left alone"; return
  fi
  run mkdir -p "$(dirname "$dest")"
  if [ "$COPY" = 1 ]; then
    run cp -R "$src" "$dest"
    [ "$DRY" = 1 ] || record copy "$dest" "$(treesum "$dest")"
  else
    run ln -s "$src" "$dest"; record link "$dest" "$src"
  fi
  ok "$(tilde "$dest")"
}

# seed SRC DEST: copy a starting file once. After that it is yours (not in the manifest).
seed() {
  if [ -e "$2" ]; then keep "$(tilde "$2") exists, left alone"; return; fi
  run mkdir -p "$(dirname "$2")"; run cp "$1" "$2"; ok "$(tilde "$2")"
}

for t in python3 git; do command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 1; }; done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || { echo "Python 3.9 or newer is required" >&2; exit 1; }
[ "$DRY" = 1 ] && echo "Dry run: nothing will change."

echo "Commands -> ~/bin"
for f in "$REPO"/bin/*; do place "$f" "$BIN/$(basename "$f")"; done

echo "Policy -> ~/.agent-os/policy"
for f in "$REPO"/policy/*.md; do place "$f" "$AOS/policy/$(basename "$f")"; done

echo "Starting files (created once, then yours)"
seed "$REPO/templates/config.json" "$AOS/config.json"
seed "$REPO/templates/delivery-profiles.json" "$AOS/delivery/profiles.json"
seed "$REPO/templates/LESSONS.md" "$AOS/LESSONS.md"

echo "Skills -> ~/.agents/skills"
for d in "$REPO"/skills/*/; do place "${d%/}" "$SKILLS/$(basename "$d")"; done

# setup_claude_dir DIR: skills, agents, the rules import and (opt-in) hooks for one config dir.
setup_claude_dir() {
  local CLAUDE="$1" n f MD S sep
  echo "Claude Code -> $(tilde "$CLAUDE")"
  record config "$CLAUDE" -   # so uninstall.sh finds this dir even without AGENT_CLAUDE_DIRS
  for f in "$REPO"/skills/*/; do
    n="$(basename "$f")"
    [ ! "$SKILLS" -ef "$CLAUDE/skills" ] || continue
    # Links go through ~/.agents/skills; copies come straight from the checkout.
    if [ "$COPY" = 1 ]; then place "${f%/}" "$CLAUDE/skills/$n"; else place "$SKILLS/$n" "$CLAUDE/skills/$n"; fi
  done
  for f in "$REPO"/agents/*.md; do place "$f" "$CLAUDE/agents/$(basename "$f")"; done

  MD="$CLAUDE/CLAUDE.md"
  if [ -f "$MD" ] && grep -qF "$BEGIN" "$MD"; then
    keep "$(tilde "$MD") already imports the rules"
  else
    if [ -f "$MD" ]; then run cp "$MD" "$MD.bak-$STAMP"; ok "backup $(tilde "$MD").bak-$STAMP"; fi
    if [ "$DRY" = 1 ]; then
      printf '    append to %s:\n      %s\n      %s\n      %s\n' "$(tilde "$MD")" "$BEGIN" "$(cat "$REPO/templates/claude/CLAUDE.md")" "$END"
    else
      mkdir -p "$CLAUDE"
      sep=""; [ -s "$MD" ] && sep=$'\n'
      { printf '%s%s\n' "$sep" "$BEGIN"; cat "$REPO/templates/claude/CLAUDE.md"; printf '%s\n' "$END"; } >> "$MD"
    fi
    ok "$(tilde "$MD"): import block for ~/.agent-os/policy/RULES.md"
  fi

  [ "$HOOKS" = 1 ] || return 0
  S="$CLAUDE/settings.json"
  if [ "$DRY" = 1 ]; then
    printf '    merge templates/claude/settings.hooks.json into %s\n' "$(tilde "$S")"
    return 0
  fi
  mkdir -p "$CLAUDE"
  python3 - "$S" "$REPO/templates/claude/settings.hooks.json" "$STAMP" <<'PY'
import json, os, shutil, sys
dst, src, stamp = sys.argv[1:]
cur = json.load(open(dst)) if os.path.exists(dst) and os.path.getsize(dst) else {}
add = json.load(open(src))["hooks"]
hooks = cur.setdefault("hooks", {})
changed = False
for event, groups in add.items():
    have = hooks.setdefault(event, [])
    known = {h.get("command") for g in have for h in g.get("hooks", [])}
    for g in groups:
        if not any(h["command"] in known for h in g["hooks"]):
            have.append(g)
            changed = True
shown = dst.replace(os.path.expanduser("~"), "~", 1)
if not changed:
    print(f"  = {shown} already has the hooks")
    sys.exit(0)
if os.path.exists(dst):
    shutil.copy2(dst, f"{dst}.bak-{stamp}")
    print(f"  + backup {shown}.bak-{stamp}")
with open(dst, "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
print(f"  + {shown}: hooks merged (existing hooks kept)")
PY
}

for c in "${CLAUDE_DIRS[@]}"; do setup_claude_dir "$c"; done

if [ "$GITHOOKS" = 1 ]; then
  echo "Global git hooks"
  place "$REPO/git-hooks" "$AOS/git-hooks"
  cur="$(git config --global core.hooksPath || true)"
  if [ "$cur" = "$AOS/git-hooks" ]; then
    keep "core.hooksPath already set"
  elif [ -n "$cur" ]; then
    keep "core.hooksPath is already $cur, left alone"
  else
    run git config --global core.hooksPath "$AOS/git-hooks"
    ok "core.hooksPath = ~/.agent-os/git-hooks"
  fi
fi

echo
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add ~/bin to your PATH, e.g.:  echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc" ;; esac
echo "Done. Start a new Claude Code session to load the rules and skills."
