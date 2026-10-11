#!/usr/bin/env bash
# Install ObsessionSystem for the current user.
#
#   ./install.sh                   commands, policy, skills, agents, CLAUDE.md import
#   ./install.sh --with-hooks      also add the Claude Code hooks to settings.json
#   ./install.sh --with-git-hooks  also set git's global core.hooksPath (pre-push guard)
#   ./install.sh --copy            copy files instead of symlinking to this checkout
#   ./install.sh --dry-run         print what would change, change nothing
#
# It never overwrites a file you already have: an existing path is left alone
# and reported. Files it edits (CLAUDE.md, settings.json) are backed up first.
# ./uninstall.sh reverses everything except your data in ~/.agent-os.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AOS="$HOME/.agent-os"
BIN="$HOME/bin"
SKILLS="$HOME/.agents/skills"
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

tilde() { printf '%s' "${1/#$HOME/~}"; }
ok()   { printf '  + %s\n' "$*"; }
keep() { printf '  = %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '    $ %s\n' "$*"; else "$@"; fi; }

# place SRC DEST: symlink (or copy) SRC to DEST unless DEST already exists.
place() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then keep "$(tilde "$dest") (already linked)"; return; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then keep "$(tilde "$dest") exists, left alone"; return; fi
  run mkdir -p "$(dirname "$dest")"
  if [ "$COPY" = 1 ]; then run cp -R "$src" "$dest"; else run ln -s "$src" "$dest"; fi
  ok "$(tilde "$dest")"
}

# seed SRC DEST: copy a starting file once. After that it is yours.
seed() {
  if [ -e "$2" ]; then keep "$(tilde "$2") exists, left alone"; return; fi
  run mkdir -p "$(dirname "$2")"; run cp "$1" "$2"; ok "$(tilde "$2")"
}

backup() { [ -f "$1" ] && run cp "$1" "$1.bak-$STAMP" && ok "backup $(tilde "$1").bak-$STAMP"; return 0; }

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

echo "Skills -> ~/.agents/skills, linked into $(tilde "$CLAUDE")/skills"
for d in "$REPO"/skills/*/; do
  n="$(basename "$d")"
  place "${d%/}" "$SKILLS/$n"
  place "$SKILLS/$n" "$CLAUDE/skills/$n"
done

echo "Agents -> $(tilde "$CLAUDE")/agents"
for f in "$REPO"/agents/*.md; do place "$f" "$CLAUDE/agents/$(basename "$f")"; done

echo "Rules -> $(tilde "$CLAUDE")/CLAUDE.md"
MD="$CLAUDE/CLAUDE.md"
if [ -f "$MD" ] && grep -qF "$BEGIN" "$MD"; then
  keep "$(tilde "$MD") already imports the rules"
else
  backup "$MD"
  if [ "$DRY" = 1 ]; then
    printf '    append to %s:\n      %s\n      %s\n      %s\n' "$(tilde "$MD")" "$BEGIN" "$(cat "$REPO/templates/claude/CLAUDE.md")" "$END"
  else
    mkdir -p "$CLAUDE"
    { [ -s "$MD" ] && printf '\n'; printf '%s\n' "$BEGIN"; cat "$REPO/templates/claude/CLAUDE.md"; printf '%s\n' "$END"; } >> "$MD"
  fi
  ok "$(tilde "$MD"): import block for ~/.agent-os/policy/RULES.md"
fi

if [ "$HOOKS" = 1 ]; then
  echo "Claude Code hooks -> settings.json"
  # A second Claude config dir (~/.claude_second) gets the same hooks if it exists.
  for CDIR in "$CLAUDE" "$HOME/.claude_second"; do
    if [ "$CDIR" != "$CLAUDE" ] && { [ ! -d "$CDIR" ] || [ "$CDIR" -ef "$CLAUDE" ]; }; then continue; fi
    S="$CDIR/settings.json"
    if [ "$DRY" = 1 ]; then printf '    merge templates/claude/settings.hooks.json into %s\n' "$(tilde "$S")"; continue; fi
    mkdir -p "$CDIR"
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
print(f"  + {shown}: hooks merged, existing hooks kept")
PY
  done
fi

if [ "$GITHOOKS" = 1 ]; then
  echo "Global git hooks"
  place "$REPO/git-hooks" "$AOS/git-hooks"
  cur="$(git config --global core.hooksPath || true)"
  if [ -n "$cur" ] && [ "$cur" != "$AOS/git-hooks" ]; then
    keep "core.hooksPath is already $cur, left alone"
  else
    run git config --global core.hooksPath "$AOS/git-hooks"
    ok "core.hooksPath = ~/.agent-os/git-hooks"
  fi
fi

echo
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add ~/bin to your PATH, e.g.:  echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc" ;; esac
echo "Done. Start a new Claude Code session to load the rules and skills."
