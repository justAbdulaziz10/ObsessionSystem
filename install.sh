#!/usr/bin/env bash
# ObsessionSystem installer: sets up AgentOS for the current user.
#
# By default it only adds things. It never overwrites a file you already have
# (existing files are skipped or backed up), and it does not touch Claude
# settings, global git config, or launchd unless you pass the matching flag.
#
#   ./install.sh                      core: commands, policy, skills, agents
#   ./install.sh --with-claude-hooks  also merge the AgentOS hooks into ~/.claude/settings.json
#   ./install.sh --with-git-hooks     also set git core.hooksPath (pre-push secret/floor guard)
#   ./install.sh --with-launchd       also install the background services (macOS)
#   ./install.sh --all                everything above
#   ./install.sh --copy               copy files instead of symlinking to this checkout
#   ./install.sh --dry-run            print what would happen, change nothing
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AOS="$HOME/.agent-os"
BIN="$HOME/bin"
SKILLS="$HOME/.agents/skills"
STAMP="$(date +%Y%m%d-%H%M%S)"

DRY=0 COPY=0 HOOKS=0 GITHOOKS=0 LAUNCHD=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --copy) COPY=1 ;;
    --with-claude-hooks) HOOKS=1 ;;
    --with-git-hooks) GITHOOKS=1 ;;
    --with-launchd) LAUNCHD=1 ;;
    --all) HOOKS=1 GITHOOKS=1 LAUNCHD=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

c_ok=$'\033[32m' c_skip=$'\033[33m' c_dim=$'\033[2m' c_off=$'\033[0m'
[ -t 1 ] || { c_ok= c_skip= c_dim= c_off=; }
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s+%s %s\n' "$c_ok" "$c_off" "$*"; }
skip() { printf '  %s=%s %s\n' "$c_skip" "$c_off" "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  %s$ %s%s\n' "$c_dim" "$*" "$c_off"; else "$@"; fi; }

# place SRC DEST: symlink (or copy) unless DEST already exists.
place() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then skip "${dest/#$HOME/~} (already linked)"; return; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then skip "${dest/#$HOME/~} exists, kept yours"; return; fi
  run mkdir -p "$(dirname "$dest")"
  if [ "$COPY" = 1 ]; then run cp -R "$src" "$dest"; else run ln -s "$src" "$dest"; fi
  ok "${dest/#$HOME/~}"
}

# seed SRC DEST: copy a template once; never replace user data.
seed() {
  if [ -e "$2" ]; then skip "${2/#$HOME/~} exists, kept yours"; return; fi
  run mkdir -p "$(dirname "$2")"; run cp "$1" "$2"; ok "${2/#$HOME/~}"
}

say "ObsessionSystem → AgentOS installer"
[ "$DRY" = 1 ] && say "(dry run: nothing will change)"

need=(python3 git)
for t in "${need[@]}"; do command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 1; }; done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || { echo "python 3.9+ required" >&2; exit 1; }

say ""; say "Commands → ~/bin"
for f in "$REPO"/bin/*; do place "$f" "$BIN/$(basename "$f")"; done

say ""; say "Policy, agents, git hooks, evals → ~/.agent-os"
place "$REPO/docs/SYSTEM.md" "$AOS/SYSTEM.md"
for f in GLOBAL DELIVERY AUTONOMY; do place "$REPO/policy/$f.md" "$AOS/policy/$f.md"; done
place "$REPO/policy/claude/AGENTS.md" "$AOS/policy/claude/AGENTS.md"
place "$REPO/policy/V2.md" "$AOS/v2/policy/V2.md"
for f in "$REPO"/agents/*.md; do place "$f" "$AOS/team/agents/$(basename "$f")"; done
place "$REPO/git-hooks" "$AOS/git-hooks"
for d in "$REPO"/evals/*/; do place "${d%/}" "$AOS/evals/$(basename "$d")"; done

say ""; say "State files (created once, then yours)"
seed "$REPO/templates/config.json" "$AOS/config.json"
seed "$REPO/templates/models.json" "$AOS/models.json"
seed "$REPO/templates/delivery-profiles.json" "$AOS/delivery/profiles.json"
for f in DECISIONS LESSONS IMPROVEMENTS CHANGELOG; do seed "$REPO/templates/$f.md" "$AOS/$f.md"; done
if [ ! -e "$AOS/mode" ]; then run sh -c "printf 'owner\n' > '$AOS/mode'"; ok "~/.agent-os/mode (owner)"; fi
run mkdir -p "$AOS/runtime" "$AOS/v2/db" "$AOS/telemetry"

say ""; say "Skills → ~/.agents/skills"
for d in "$REPO"/skills/*/; do place "${d%/}" "$SKILLS/$(basename "$d")"; done
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null; then
  if [ ! -e "$HOME/.claude/skills" ]; then place "$SKILLS" "$HOME/.claude/skills"; else skip "~/.claude/skills exists; link individual skills yourself if needed"; fi
  for f in "$REPO"/agents/*.md; do place "$f" "$HOME/.claude/agents/$(basename "$f")"; done
  seed "$REPO/templates/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

if [ "$HOOKS" = 1 ]; then
  say ""; say "Claude Code hooks → settings.json (~/.claude, and ~/.claude_second if you use a failover account)"
  for CDIR in "$HOME/.claude" "$HOME/.claude_second"; do
  [ "$CDIR" = "$HOME/.claude" ] || [ -d "$CDIR" ] || continue
  S="$CDIR/settings.json"
  if [ "$DRY" = 1 ]; then say "  would merge templates/claude/settings.hooks.json into $S"; else
    mkdir -p "$CDIR"; [ -f "$S" ] && cp "$S" "$S.bak-$STAMP" && ok "backup: ${S/#$HOME/~}.bak-$STAMP"
    python3 - "$S" "$REPO/templates/claude/settings.hooks.json" <<'PY'
import json, os, sys
dst, src = sys.argv[1], sys.argv[2]
cur = json.load(open(dst)) if os.path.exists(dst) and os.path.getsize(dst) else {}
add = json.load(open(src))["hooks"]
hooks = cur.setdefault("hooks", {})
for event, groups in add.items():
    have = hooks.setdefault(event, [])
    known = {h.get("command") for g in have for h in g.get("hooks", [])}
    for g in groups:
        if not any(h["command"] in known for h in g["hooks"]):
            have.append(g)
json.dump(cur, open(dst, "w"), indent=2)
print("  + hooks merged into " + dst.replace(os.path.expanduser("~"), "~", 1) + " (existing hooks kept)")
PY
  fi
  done
fi

if [ "$GITHOOKS" = 1 ]; then
  say ""; say "Global git hooks"
  cur="$(git config --global core.hooksPath || true)"
  if [ -n "$cur" ] && [ "$cur" != "$AOS/git-hooks" ]; then skip "core.hooksPath already set to $cur, left alone"
  else run git config --global core.hooksPath "$AOS/git-hooks"; ok "core.hooksPath = ~/.agent-os/git-hooks (undo: git config --global --unset core.hooksPath)"; fi
fi

if [ "$LAUNCHD" = 1 ]; then
  say ""; say "Background services (launchd)"
  if [ "$(uname)" != Darwin ]; then skip "not macOS; see docs/INSTALL.md for cron equivalents"
  else
    LA="$HOME/Library/LaunchAgents"; run mkdir -p "$LA"
    for p in "$REPO"/templates/launchd/*.plist; do
      n="$(basename "$p")"
      if [ -e "$LA/$n" ]; then skip "$n exists"; continue; fi
      run cp "$p" "$LA/$n"; run launchctl load -w "$LA/$n"; ok "$n loaded"
    done
  fi
fi

say ""
case ":$PATH:" in *":$BIN:"*) ;; *) say "Add ~/bin to your PATH:  echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc";; esac
say "Done. Try:  agent-system   ·   agent-cap recommend \"fix a flaky login test\"   ·   agent-doc-sync"
