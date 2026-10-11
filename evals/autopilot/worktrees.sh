#!/bin/zsh
[ -n "${ZSH_VERSION-}" ] || exec zsh "$0" "$@"  # zsh script: re-exec when started via bash/sh
# agent-autopilot worktree retirement: only clean, idle, merged-or-stale worktrees are proposed; --apply re-checks.
set -u
T=$(mktemp -d /tmp/wteval.XXXX); export AGENT_AUTOPILOT_DIR=$T/ap AGENT_AUTOPILOT_CONFIG=$T/ap.json; mkdir -p $T/ap
g(){ git -C "$@" }; pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass+1)); echo "pass $1"; else fail=$((fail+1)); echo "FAIL $1"; fi }
git init -q --bare -b main $T/origin.git; R=$T/repo; git init -q -b main $R; g $R commit -q --allow-empty -m init
g $R remote add origin $T/origin.git; g $R push -q origin main
old(){ gd=$(g $1 rev-parse --absolute-git-dir); sed -E -i '' 's/> [0-9]+ ([+-][0-9]{4})	/> 1767225600 \1	/' $gd/logs/HEAD; touch $gd/index }  # old reflog, freshly rewritten index
wt(){ g $R worktree add -q -b $1 $T/wt/$1 main 2>/dev/null; g $T/wt/$1 commit -q --allow-empty -m $1 }
wt merged; g $R merge -q --no-ff -m m merged; g $R push -q origin main; mkdir -p $T/wt/merged/build; echo x > $T/wt/merged/build/out
mkdir -p $R/.git/info; echo 'build/' >> $R/.git/info/exclude   # ignored build output: the only thing removal loses
wt stale; wt fresh; wt dirty; echo change > $T/wt/dirty/f; wt untracked_new; wt busy; wt detached
g $T/wt/detached checkout -q --detach; g $T/wt/detached commit -q --allow-empty -m orphan-commit
for w in merged stale dirty busy detached; do old $T/wt/$w; done
gd=$(g $T/wt/fresh rev-parse --absolute-git-dir); T3=$(( $(date +%s) - 3*86400 )); sed -E -i '' "s/> [0-9]+ ([+-][0-9]{4})	/> $T3 \1	/" $gd/logs/HEAD
# merged and idle, but removal would lose something: an ignored .env, a hidden untracked file, a release archive
for w in envw untr rel; do g $R worktree add -q -b $w $T/wt/$w main 2>/dev/null; old $T/wt/$w; done
echo 'SECRET=1' > $T/wt/envw/.env; echo '.env' >> $R/.git/info/exclude
g $T/wt/untr config extensions.worktreeConfig true; g $T/wt/untr config --worktree status.showUntrackedFiles no; echo n > $T/wt/untr/notes.txt
mkdir -p $T/wt/rel/build/ios/ipa; echo i > $T/wt/rel/build/ios/ipa/Runner.ipa
(cd $T/wt/busy && sleep 60) & BP=$!
P="import importlib.machinery as m,importlib.util as u,os,sys,json
l=m.SourceFileLoader('a',os.path.expanduser('~/bin/agent-autopilot'));s=u.spec_from_loader('a',l);a=u.module_from_spec(s);l.exec_module(a)"
C=$(python3 -c "$P
print(' '.join(sorted(os.path.basename(w['path'])+':'+('M' if w['merged'] else 'S') for w in a.worktree_candidates('$R',14,a.busy_dirs()))))")
echo "candidates: $C"
ok W1-merged-proposed '[[ $C == *merged:M* ]]'
ok W2-stale-proposed '[[ $C == *stale:S* ]]'
ok W3-fresh-not-proposed '[[ $C != *fresh* ]]'
ok W4-dirty-not-proposed '[[ $C != *dirty* ]]'
ok W5-busy-not-proposed '[[ $C != *busy* ]]'
ok W6-detached-unique-commit-not-proposed '[[ $C != *detached* ]]'
ok W10-ignored-env-not-proposed '[[ $C != *envw* ]]'
ok W11-hidden-untracked-not-proposed '[[ $C != *untr* ]]'
ok W12-release-archive-not-proposed '[[ $C != *rel:* ]]'
python3 -c "$P
d={'checked':'L1','candidates':[dict(w,gb=0) for w in a.worktree_candidates('$R',14,a.busy_dirs())]}
(a.ROOT/'worktrees.json').write_text(json.dumps(d))"
python3 -c "$P
class A: apply='L0'
a.cmd_worktrees(A())" > $T/apply0.out 2>&1
ok W13-apply-refuses-a-list-the-user-did-not-see '[[ -d $T/wt/merged ]] && grep -q "list changed" $T/apply0.out'
echo late > $T/wt/stale/newfile   # the user starts work in it after the list was shown
python3 -c "$P
class A: apply='L1'
a.cmd_worktrees(A())" > $T/apply.out 2>&1; cat $T/apply.out
ok W7-apply-removes-merged-and-its-branch '[[ ! -d $T/wt/merged && -z $(g $R branch --list merged) ]]'
ok W8-apply-rechecks-and-keeps-changed '[[ -d $T/wt/stale && -f $T/wt/stale/newfile ]]'
ok W9-others-untouched '[[ -d $T/wt/fresh && -d $T/wt/dirty && -d $T/wt/busy && -d $T/wt/detached ]]'
# Disk-pressure build sweep: ignored build output in idle worktrees goes; everything else stays.
mk(){ mkdir -p $T/wt/$1/build/sub; echo o > $T/wt/$1/build/sub/o; [[ $2 == old ]] && touch -t 202601010000 $T/wt/$1/build/sub/o $T/wt/$1/build/sub $T/wt/$1/build }
mk dirty old; mk busy old; mk fresh new; mkdir -p $T/wt/rel/build/sub; touch -t 202601010000 $T/wt/rel/build/ios/ipa/Runner.ipa $T/wt/rel/build/ios/ipa $T/wt/rel/build/ios $T/wt/rel/build/sub $T/wt/rel/build
mkdir -p $T/wt/detached/build; echo t > $T/wt/detached/build/t; g $T/wt/detached add -f build/t; g $T/wt/detached commit -q -m tracked-build
old $T/wt/detached; touch -t 202601010000 $T/wt/detached/build/t $T/wt/detached/build
python3 -c "$P
print('freed', a.build_sweep([('$R',0,'main')], a.busy_dirs()))"
ok B1-idle-ignored-build-removed-source-kept '[[ ! -d $T/wt/dirty/build && -f $T/wt/dirty/f ]]'
ok B2-busy-worktree-build-kept '[[ -f $T/wt/busy/build/sub/o ]]'
ok B3-recent-build-kept '[[ -f $T/wt/fresh/build/sub/o ]]'
ok B4-tracked-build-kept '[[ -f $T/wt/detached/build/t ]]'
ok B5-release-archive-build-kept '[[ -f $T/wt/rel/build/ios/ipa/Runner.ipa ]]'
kill $BP 2>/dev/null; rm -rf $T; echo "worktree regression: $pass passed, $fail failed"; [[ $fail == 0 ]]
