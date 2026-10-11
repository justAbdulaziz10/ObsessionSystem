#!/bin/zsh
[ -n "${ZSH_VERSION-}" ] || exec zsh "$0" "$@"  # zsh script: re-exec when started via bash/sh
# agent-ship regression: fake github (canonical) + gitlab (mirror) bare remotes in a temp dir.
set -u
T=$(mktemp -d /tmp/shipeval.XXXX); export AGENT_SHIP_DIR=$T/state AGENT_SHIP_PROFILES=$T/profiles.json AGENT_SHIP_LEARNED=$T/learned
export AGENT_SHIP_NO_STATUS=1  # never let tests reach the real GitHub API; ST* cases use a stub gh
S=${AGENT_SHIP:-$HOME/bin/agent-ship}; pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass+1)); echo "pass $1"; else fail=$((fail+1)); echo "FAIL $1"; fi }
g(){ git -C "$@" }
echo '{"profiles":[{"name":"t","match":["*app*"],"ci":["test ! -f broken"],"rules":["r1"]}]}' > $T/profiles.json
mk(){ # $1 name -> repo with origin=github, gitlab=gitlab, main pushed to both
  mkdir -p $T/$1/github.com/org $T/$1/gitlab.com/org
  git init -q --bare -b main $T/$1/github.com/org/app.git; git init -q --bare -b main $T/$1/gitlab.com/org/app.git
  git init -q -b main $T/$1/app; g $T/$1/app commit -q --allow-empty -m init
  g $T/$1/app remote add origin $T/$1/github.com/org/app.git; g $T/$1/app remote add gitlab $T/$1/gitlab.com/org/app.git
  g $T/$1/app push -q origin main; g $T/$1/app push -q gitlab main; g $T/$1/app fetch -q --all
}
c(){ g $1 commit -q --allow-empty -m "$2" }

# S1 canonical = the remote that is ahead (fetched); stale mirror reported
mk s1; c $T/s1/app a; g $T/s1/app push -q origin main; g $T/s1/app fetch -q --all
J=$($S topology $T/s1/app --fetch --json)
ok S1-canonical '[[ $(echo $J | jq -r .canonical) == origin ]]'
ok S1-stale '[[ $(echo $J | jq -r ".mirrors[0].state") == stale && $(echo $J | jq ".mirrors[0].drift.main.behind") == 1 ]]'

# S2 equal heads, non-origin names: mirror-job evidence picks the source
mk s2; g $T/s2/app remote rename origin gh; g $T/s2/app remote rename gitlab gl
mkdir -p $T/s2/app/.github/workflows; printf 'on: push\njobs:\n s:\n  steps:\n   - run: git push --force gitlab HEAD\n' > $T/s2/app/.github/workflows/m.yml
ok S2-evidence '[[ $($S topology $T/s2/app --json | jq -r .canonical) == gh ]]'

# S3 base push: blocked without local CI; after CI passes, canonical updated and mirror fast-forwarded to the same SHA
mk s3; c $T/s3/app a; g $T/s3/app push -q origin main; g $T/s3/app fetch -q --all; c $T/s3/app work
$S push $T/s3/app >/dev/null 2>&1; ok S3-ci-gate '[[ $? == 4 ]]'
touch $T/s3/app/broken; g $T/s3/app add broken; g $T/s3/app commit -qm broken; $S ci $T/s3/app >/dev/null 2>&1; ok S3-ci-fails '[[ $? == 1 ]]'
g $T/s3/app rm -q broken; g $T/s3/app commit -qm fixed; $S ci $T/s3/app >/dev/null 2>&1; ok S3-ci-passes '[[ $? == 0 ]]'
$S push $T/s3/app >/dev/null 2>&1; rc=$?
H=$(g $T/s3/app rev-parse main)
ok S3-push '[[ $rc == 0 && $(g $T/s3/github.com/org/app.git rev-parse main) == $H && $(g $T/s3/gitlab.com/org/app.git rev-parse main) == $H ]]'

# S4 behind canonical: refuse
mk s4; git clone -q $T/s4/github.com/org/app.git $T/s4/other; c $T/s4/other theirs; g $T/s4/other push -q origin main
c $T/s4/app mine; $S push $T/s4/app --no-ci test >/dev/null 2>&1; ok S4-behind-stops '[[ $? == 3 ]]'

# S5 mirror has commits canonical lacks AND canonical ahead: diverged -> plan stops
mk s5; git clone -q $T/s5/gitlab.com/org/app.git $T/s5/gl; c $T/s5/gl direct; g $T/s5/gl push -q origin main
c $T/s5/app a; g $T/s5/app push -q origin main; g $T/s5/app fetch -q --all
$S plan $T/s5/app >/dev/null 2>&1; ok S5-diverged-stops '[[ $? == 3 ]]'
$S push $T/s5/app --no-ci t >/dev/null 2>&1; ok S5-push-refused '[[ $? == 3 && $(g $T/s5/gitlab.com/org/app.git log -1 --format=%s main) == direct ]]'

# S6 guard
gd(){ printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2" | $S guard 2>/dev/null; echo $? }
mk s6; c $T/s6/app a; g $T/s6/app push -q origin main; g $T/s6/app fetch -q --all; g $T/s6/app checkout -q -b feat
ok S6-mirror-feature-blocked '[[ $(gd "git push gitlab feat" $T/s6/app) == 2 ]]'
ok S6-force-base-blocked '[[ $(gd "git push -f origin main" $T/s6/app) == 2 ]]'
ok S6-plus-refspec-blocked '[[ $(gd "git push origin +main" $T/s6/app) == 2 ]]'
ok S6-cd-chain-blocked '[[ $(gd "cd $T/s6/app && git push gitlab feat" /tmp) == 2 ]]'
ok S6-canonical-allowed '[[ $(gd "git push -u origin feat" $T/s6/app) == 0 ]]'
ok S6-mirror-ff-allowed '[[ $(gd "git push gitlab main" $T/s6/app) == 0 ]]'
ok S6-force-lease-feature-allowed '[[ $(gd "git push --force-with-lease origin feat" $T/s6/app) == 0 ]]'
ok S6-non-git-allowed '[[ $(gd "echo git push" $T/s6/app) == 0 && $(gd "ls" /tmp) == 0 ]]'

# S7 sync fast-forwards a clean checked-out base and leaves dirty trees alone
mk s7; git clone -q $T/s7/github.com/org/app.git $T/s7/other; c $T/s7/other up; g $T/s7/other push -q origin main
$S sync $T/s7/app >/dev/null; ok S7-ff '[[ $(g $T/s7/app rev-parse main) == $(g $T/s7/github.com/org/app.git rev-parse main) ]]'
c $T/s7/other up2; g $T/s7/other push -q origin main; echo x > $T/s7/app/f; g $T/s7/app add f
$S sync $T/s7/app >/dev/null; ok S7-dirty-untouched '[[ $(g $T/s7/app rev-parse main) != $(g $T/s7/github.com/org/app.git rev-parse main) ]]'

# S8 feature branch goes to canonical only
mk s8; c $T/s8/app a; g $T/s8/app push -q origin main; g $T/s8/app fetch -q --all; g $T/s8/app checkout -q -b feat; c $T/s8/app f; $S ci $T/s8/app >/dev/null; $S push $T/s8/app >/dev/null 2>&1
ok S8-feature-canonical-only '[[ -n $(g $T/s8/github.com/org/app.git rev-parse -q --verify feat) && -z $(g $T/s8/gitlab.com/org/app.git rev-parse -q --verify feat) ]]'

# S9 healthy mirror job: base push goes to canonical only
mk s9; mkdir -p $T/s9/app/.github/workflows; printf 'run: git push --force gitlab\n' > $T/s9/app/.github/workflows/m.yml
g $T/s9/app add -A; g $T/s9/app commit -q -m wf; g $T/s9/app push -q origin main; g $T/s9/app push -q gitlab main; g $T/s9/app fetch -q --all
c $T/s9/app b; $S ci $T/s9/app >/dev/null; $S push $T/s9/app >/dev/null 2>&1
ok S9-healthy-mirror-left-alone '[[ $(g $T/s9/gitlab.com/org/app.git log -1 --format=%s main) == wf && $(g $T/s9/github.com/org/app.git log -1 --format=%s main) == b ]]'

# S10 CI record is bound to the commit: a new commit needs CI again
c $T/s9/app c2; $S push $T/s9/app >/dev/null 2>&1; ok S10-new-commit-needs-ci '[[ $? == 4 ]]'

# R-B1 deploy remote and fork upstream are never pushed or treated as mirrors
mk b1; mkdir -p $T/b1/git.heroku.com; git init -q --bare -b main $T/b1/git.heroku.com/app.git; g $T/b1/app remote add heroku $T/b1/git.heroku.com/app.git
g $T/b1/app push -q heroku main; c $T/b1/app a; g $T/b1/app push -q origin main; g $T/b1/app fetch -q --all; c $T/b1/app b; $S ci $T/b1/app >/dev/null
O=$($S push $T/b1/app --dry-run 2>&1); ok B1-heroku-not-pushed '[[ $O != *heroku* && $O == *"push origin"* ]]'
mkdir -p $T/fk/github.com/me $T/fk/github.com/org; git init -q --bare -b main $T/fk/github.com/me/app.git; git init -q --bare -b main $T/fk/github.com/org/app.git
git init -q -b main $T/fk/app; c $T/fk/app i; g $T/fk/app remote add origin $T/fk/github.com/me/app.git; g $T/fk/app remote add upstream $T/fk/github.com/org/app.git
g $T/fk/app push -q origin main; c $T/fk/app up; g $T/fk/app push -q upstream main; g $T/fk/app fetch -q --all; g $T/fk/app checkout -q -b feat
ok B1-fork-canonical-origin '[[ $($S topology $T/fk/app --json | jq -r .canonical) == origin ]]'
ok B1-fork-guard-allows-origin '[[ $(gd "git push -u origin feat" $T/fk/app) == 0 ]]'
ok B1-fork-plan-no-upstream '[[ $($S plan $T/fk/app 2>&1) != *"push: upstream"* ]]'
# R-I1 non-push commands and value options
ok I1-stash-push-allowed '[[ $(gd "git stash push -m wip" $T/s6/app) == 0 && $(gd "git commit -m push" $T/s6/app) == 0 && $(gd "git log --grep push" $T/s6/app) == 0 ]]'
ok I1-push-option-mirror-blocked '[[ $(gd "git push -o ci.skip gitlab feat" $T/s6/app) == 2 ]]'
ok I1-push-option-canonical-allowed '[[ $(gd "git push -o merge_request.create origin feat" $T/s6/app) == 0 ]]'
# R-I2 force/delete variants on a base branch
g $T/s6/app checkout -q main
for v in "git push -fu origin main" "git push -f origin HEAD" "git push origin :main" "git push --force --all gitlab" "git push origin --prune refs/heads/*:refs/heads/*" "GIT_TRACE=0 git push -f origin main" "echo hi | git push -f origin main" "git -c x.y=z push --force origin main"; do
  ok "I2-blocked: $v" '[[ $(gd "$v" $T/s6/app) == 2 ]]'
done
# R-I3 in sync after evidence: keep the remembered canonical
g $T/s1/app push -q gitlab main; g $T/s1/app fetch -q --all
ok I3-remembered '[[ $($S topology $T/s1/app --json | jq -r "[.canonical, .ambiguous] | @tsv") == "origin	false" ]]'
# R-I4 CI refuses a dirty tree
touch $T/s9/app/untracked; $S ci $T/s9/app >/dev/null 2>&1; ok I4-dirty-ci-refused '[[ $? == 5 ]]'

# Round 2 review
gdf(){ python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2" | $S guard 2>/dev/null; echo $? }
NL=$'\n'
ok R1-heredoc-commit-then-force-blocked '[[ $(gdf "git commit -m \"\$(cat <<'"'"'EOF'"'"'${NL}msg body${NL}EOF${NL})\" && git push -f origin main" $T/s6/app) == 2 ]]'
ok R1-multiline-msg-then-force-blocked '[[ $(gdf "git commit -m \"line1${NL}line2\" && git push -f origin main" $T/s6/app) == 2 ]]'
ok R1-heredoc-body-is-data '[[ $(gdf "cat > notes.txt <<EOF${NL}git push -f origin main${NL}EOF" $T/s6/app) == 0 ]]'
ok R1-redirect-fd-allowed '[[ $(gdf "git push gitlab main 2>&1" $T/s6/app) == 0 && $(gdf "git push origin feat > /tmp/log 2>&1" $T/s6/app) == 0 ]]'
ok R3-fork-upstream-force-blocked '[[ $(gd "git push -f upstream main" $T/fk/app) == 2 ]]'
# R2 ambiguous: stop every branch
mk am; g $T/am/app checkout -q -b feat; c $T/am/app f
$S push $T/am/app --no-ci t --dry-run >/dev/null 2>&1; ok R2-ambiguous-feature-stops '[[ $? == 3 ]]'

# User rule (defaults): GitHub first, mirror every pushed branch to GitLab when a GitLab remote exists
echo '{"defaults":{"canonical_host":"github","mirror_all_branches":true},"profiles":[{"name":"t","match":["*app*"],"ci":["true"]}]}' > $T/profiles.json
mk g1; ok G1-github-canonical-when-in-sync '[[ $($S topology $T/g1/app --json | jq -r "[.canonical,.ambiguous]|@tsv") == "origin	false" ]]'
g $T/g1/app checkout -q -b feat; c $T/g1/app f; $S ci $T/g1/app >/dev/null; $S push $T/g1/app >/dev/null 2>&1
H=$(g $T/g1/app rev-parse feat)
ok G2-feature-on-both '[[ $(g $T/g1/github.com/org/app.git rev-parse -q --verify feat) == $H && $(g $T/g1/gitlab.com/org/app.git rev-parse -q --verify feat) == $H ]]'
g $T/g1/app checkout -q -b feat2; c $T/g1/app f2
ok G3-guard-mirror-before-github-blocked '[[ $(gd "git push gitlab feat2" $T/g1/app) == 2 ]]'
g $T/g1/app push -q origin feat2
ok G3-guard-mirror-after-github-allowed '[[ $(gd "git push gitlab feat2" $T/g1/app) == 0 ]]'
mk g4; g $T/g4/app remote remove gitlab; c $T/g4/app x; $S ci $T/g4/app >/dev/null; $S push $T/g4/app >/dev/null 2>&1
ok G4-github-only-repo '[[ $? == 0 && $(g $T/g4/github.com/org/app.git log -1 --format=%s main) == x ]]'
mk g5; git clone -q $T/g5/gitlab.com/org/app.git $T/g5/gl; c $T/g5/gl direct; g $T/g5/gl push -q origin main
c $T/g5/app y; $S ci $T/g5/app >/dev/null; $S push $T/g5/app >/dev/null 2>&1
ok G5-gitlab-diverged-stops-no-force '[[ $? == 3 && $(g $T/g5/gitlab.com/org/app.git log -1 --format=%s main) == direct ]]'

# CI learning + ratchet (repo with no remote and no profile match)
lj(){ jq -c "$1" $T/learned/local_lrn-*.json }
L=$T/lrn; git init -q -b main $L; printf 'lint:\n\tfalse\ntest:\n\ttrue\n' > $L/Makefile; g $L add -A; g $L commit -qm init
$S ci $L --learn >/dev/null 2>&1
ok C1-learned '[[ $(lj .commands) == "[\"make lint\",\"make test\"]" && $(lj ".known_failing|keys") == "[\"make lint\"]" ]]'
$S ci $L >/dev/null 2>&1; ok C1-preexisting-failure-not-blocking '[[ $? == 0 ]]'
printf 'lint:\n\tfalse\ntest:\n\tfalse\n' > $L/Makefile; g $L commit -qam "break test"
$S ci $L >/dev/null 2>&1; ok C1-new-failure-blocks '[[ $? == 1 ]]'
$S ci $L --learn >/dev/null 2>&1; ok C7-learn-cannot-baseline-a-regression '[[ $? == 1 && $(lj ".known_failing|keys") == "[\"make lint\"]" ]]'
g $L checkout -q -b feat; printf 'lint:\n\ttrue\ntest:\n\ttrue\n' > $L/Makefile; g $L commit -qam "fix both on feat"
$S ci $L >/dev/null 2>&1; ok C8-feature-pass-does-not-clear-baseline '[[ $? == 0 && $(lj ".known_failing|keys") == "[\"make lint\"]" ]]'
printf 'lint:\n\ttrue\ntest:\n\ttrue\nnew:\n\tfalse\n' > $L/Makefile; g $L commit -qam "new failing target"
printf 'check:\n\tfalse\n' >> $L/Makefile; g $L commit -qam "check target"
$S ci $L --learn >/dev/null 2>&1; ok C9-no-new-baseline-off-base '[[ $? == 1 && $(lj ".known_failing|keys") == "[\"make lint\"]" ]]'
g $L checkout -q main; g $L merge -q --ff-only feat; g $L reset -q --hard HEAD~2
$S ci $L >/dev/null 2>&1; ok C1-ratchet-tightens-on-base '[[ $? == 0 && $(lj ".known_failing") == "{}" ]]'
printf 'lint:\n\ttouch made-by-lint\ntest:\n\ttrue\n' > $L/Makefile; g $L commit -qam "lint writes a file"
$S ci $L >/dev/null 2>&1; ok C10-check-that-modifies-tree-fails '[[ $? == 1 ]]'
rm -f $L/made-by-lint
M=$T/rc; git init -q -b main $M; printf 'exit 0\n' > $M/check.sh; g $M add -A; g $M commit -qm i
$S ci $M --set "sh check.sh" >/dev/null; $S ci $M --learn >/dev/null 2>&1; printf 'exit 7\n' > $M/check.sh; g $M commit -qam seven
$S ci $M --learn >/dev/null 2>&1; r1=$?; $S ci $M --learn --rebaseline "user agreed" >/dev/null 2>&1; r2=$?
$S ci $M >/dev/null 2>&1; r3=$?
printf 'exit 127\n' > $M/check.sh; g $M commit -qam missing
$S ci $M >/dev/null 2>&1; ok C11-rebaseline-explicit-and-rc-must-match '[[ $r1 == 1 && $r2 == 0 && $r3 == 0 && $? == 1 ]]'
N=$T/none; git init -q -b main $N; echo hi > $N/README; g $N add -A; g $N commit -qm i
$S ci $N >/dev/null 2>&1; ok C1-no-checks-fails-closed '[[ $? == 1 ]]'
$S ci $N --set "true" >/dev/null 2>&1; ok C12-trivial-set-refused '[[ $? == 2 ]]'
$S ci $N --set "test -f README" >/dev/null; $S ci $N >/dev/null 2>&1; ok C1-set-checks '[[ $? == 0 ]]'
$S ci $N --set "test -d ." >/dev/null; NK=$($S ci $N --list | jq -c .checks); ok C12-set-merges '[[ $NK == "[\"test -f README\",\"test -d .\"]" ]]'
$S ci $N --set "test -d ." --replace "README check obsolete" >/dev/null; NK=$($S ci $N --list | jq -c "[.checks,(.history|length)]"); ok C12-replace-logged '[[ $NK == "[[\"test -d .\"],1]" ]]'
Z=$T/zsh; git init -q -b main $Z; printf '#!/bin/zsh\nf(){ echo hi }\n' > $Z/z.sh; printf '#!/bin/bash\necho ok\n' > $Z/b.sh; g $Z add -A; g $Z commit -qm i
ZK=$($S ci $Z --list | jq -c .checks); ok SC1-shellcheck-skips-zsh '[[ $ZK != *z.sh* ]] && { ! command -v shellcheck >/dev/null || [[ $ZK == *b.sh* ]] }'
# secret scan
echo 'key = "AKIAABCDEFGHIJKLMNOP"' > $N/conf.py; g $N add -A; g $N commit -qm leak  # agent-ship: allow-secret
$S ci $N >/dev/null 2>&1; ok C2-aws-key-blocks '[[ $? == 1 ]]'
g $N reset -q --hard HEAD~1; echo 'key = "AKIAIOSFODNN7EXAMPLE"' > $N/conf.py; g $N add -A; g $N commit -qm example  # agent-ship: allow-secret
$S ci $N >/dev/null 2>&1; ok C2-example-key-allowed '[[ $? == 0 ]]'
mkdir -p $N/docs; echo 'key = "AKIAQQQQQQQQQQQQQQQQ"' > $N/docs/sample.md; g $N add -A; g $N commit -qm docs  # agent-ship: allow-secret
$S ci $N >/dev/null 2>&1; r1=$?
jq '.secret_allow=["docs/*"]' $T/learned/local_none-*.json > $T/x.json && mv $T/x.json $(echo $T/learned/local_none-*.json)
$S ci $N >/dev/null 2>&1; ok C2-allow-glob '[[ $r1 == 1 && $? == 0 ]]'
echo 'SECRET=1' > $N/.env; g $N add -f .env; g $N commit -qm env
$S ci $N >/dev/null 2>&1; ok C2-dotenv-blocks '[[ $? == 1 ]]'
for i in $(seq 1 60); do c $N "filler $i"; done
$S ci $N >/dev/null 2>&1; ok C2-scan-covers-whole-unpushed-history '[[ $? == 1 ]]'
# C13 a branch cut from develop scans only its own commits, not develop history main lacks
mk c13; g $T/c13/app checkout -q -b develop; echo 'key = "AKIAABCDEFGHIJKLMNOP"' > $T/c13/app/old.py; g $T/c13/app add -A; g $T/c13/app commit -qm published-leak  # agent-ship: allow-secret
g $T/c13/app push -q origin develop; g $T/c13/app fetch -q --all; g $T/c13/app checkout -q -b feature/x; c $T/c13/app clean-work
$S ci $T/c13/app --set "test -d ." >/dev/null; $S ci $T/c13/app >/dev/null 2>&1; ok C13-scan-from-closest-base '[[ $? == 0 ]]'
# C14 a release branch that merges published main with -s ours scans only unpublished commits; a new leak still blocks
mk c14; R=$T/c14/app; g $R checkout -q -b develop; for i in 1 2 3 4 5; do c $R dev$i; done; g $R push -q origin develop; g $R checkout -q main
echo 'key = "AKIAABCDEFGHIJKLMNOP"' > $R/old.py; g $R add -A; g $R commit -qm main-published-leak; g $R push -q origin main  # agent-ship: allow-secret
g $R fetch -q --all; g $R checkout -q -b release/1.0 origin/develop; c $R bump; g $R merge -q -s ours origin/main -m ours
$S ci $R --set "test -d ." >/dev/null; $S ci $R >/dev/null 2>&1; r1=$?
echo 'k2 = "AKIAZZZZZZZZZZZZZZZZ"' > $R/new.py; g $R add -A; g $R commit -qm new-leak; $S ci $R >/dev/null 2>&1  # agent-ship: allow-secret
ok C14-ours-merge-scans-unpublished-only '[[ $r1 == 0 && $? == 1 ]]'
# round-4 cases
U=$T/u8; git init -q -b main $U; printf 'caf\xe9\n' > $U/l1.txt; g $U add -A; g $U commit -qm latin1
$S ci $U --set "printf 'caf\351'; exit 0" >/dev/null; $S ci $U >/dev/null 2>&1; ok R4-non-utf8-does-not-crash '[[ $? == 0 ]]'
P=$T/envp; git init -q -b main $P; echo 'MAILGUN=key-3ax6xnjp29jd6fds4gc373sgvjxteol0' > $P/.env.production; g $P add -f -A; g $P commit -qm e
$S ci $P --set "test -d ." >/dev/null; $S ci $P >/dev/null 2>&1; ok R4-env-production-flagged '[[ $? == 1 ]]'
K=$T/kb; git init -q -b main $K; mkdir -p $K/test; head -c 64 /dev/urandom > $K/test/release.keystore; g $K add -A; g $K commit -qm k
$S ci $K --set "test -d ." >/dev/null; $S ci $K >/dev/null 2>&1; ok R4-binary-key-in-test-dir-flagged '[[ $? == 1 ]]'
Q=$T/pp; git init -q -b main $Q; echo '++ AKIAABCDEFGHIJKLMNOP' > $Q/n.txt; g $Q add -A; g $Q commit -qm p  # agent-ship: allow-secret
$S ci $Q --set "test -d ." >/dev/null; $S ci $Q >/dev/null 2>&1; ok R4-plusplus-line-scanned '[[ $? == 1 ]]'
W=$T/wb; git init -q -b main $W; printf 'test:\n\tsh t.sh\n' > $W/Makefile; echo 'exit 3' > $W/t.sh; g $W add -A; g $W commit -qm i
$S ci $W --learn >/dev/null 2>&1; g $W checkout -q -b fix; echo 'exit 0' > $W/t.sh; g $W commit -qam fix; $S ci $W --learn >/dev/null 2>&1
g $W checkout -q main; g $W checkout -q -b other; c $W o; $S ci $W >/dev/null 2>&1
ok R4-learn-off-base-keeps-baseline '[[ $? == 0 && $(jq ".known_failing|has(\"make test\")" $T/learned/local_wb-*.json) == true ]]'
F=$T/sf; git init -q -b main $F; echo x > $F/a; g $F add -A; g $F commit -qm i
$S ci $F --set "test -f nope" >/dev/null; $S ci $F --learn >/dev/null 2>&1; r1=$?; $S ci $F >/dev/null 2>&1
ok R4-set-check-failing-on-base-can-baseline '[[ $r1 == 0 && $? == 0 ]]'
Z=$T/rb; git init -q -b main $Z; touch $Z/broken; g $Z add -A; g $Z commit -qm i
$S ci $Z --set "test ! -f broken" >/dev/null; $S ci $Z --learn >/dev/null 2>&1
g $Z rm -q broken; g $Z commit -qm fix; $S ci $Z >/dev/null 2>&1
touch $Z/broken; g $Z add -A; g $Z commit -qm rebreak; $S ci $Z --learn >/dev/null 2>&1; r1=$?; $S ci $Z >/dev/null 2>&1
ok R5-fixed-check-cannot-be-silently-rebaselined '[[ $r1 == 1 && $? == 1 ]]'
ok R5-env-vault-not-flagged '[[ $(python3 -c "import re,sys;exec(open(sys.argv[1]).read().split(\"SECRET_FILES = \")[1].split(\"KEY_BLOB\")[0].join([\"S=\",\"\"]));print(bool(S.search(\".env.vault\")),bool(S.search(\".env.prod\")))" $S) == "False True" ]]'
# release paths
mkdir -p $N/ios; touch $N/wrangler.toml
R=$($S release $N); ok C3-release-paths '[[ $(echo $R | jq -c "[.paths[]|[.kind,.only_when_asked]]") == "[[\"ios-test\",false],[\"ios-store\",true],[\"web-preview\",false],[\"web-prod\",true]]" ]]'
# tidy: only branches with merge evidence; never bases/long-lived, fresh, unmerged or fast-forwarded ones
mk td; A=$T/td/app; pb(){ g $A push -q origin $1; g $A push -q gitlab $1 }
g $A checkout -q -b done; c $A d; pb done
g $A checkout -q main; g $A merge -q --no-ff -m "merge done" done; pb main; g $A branch -q -D done
g $A branch fresh main; pb fresh
g $A checkout -q -b wip; c $A w; pb wip; g $A checkout -q main
g $A checkout -q -b staging; c $A s; pb staging; g $A checkout -q main; g $A merge -q --no-ff -m "merge staging" staging; pb main
g $A checkout -q -b ff; c $A f; pb ff; g $A checkout -q main; g $A merge -q --ff-only ff; pb main; g $A branch -q -D ff
g $A checkout -q -b drift; c $A x; pb drift; g $A checkout -q main; g $A merge -q --no-ff -m "merge drift" drift; pb main
g $A checkout -q -b next; c $A n; pb next; g $A checkout -q main; g $A merge -q --no-ff -m "merge next" next; pb main
g $A checkout -q drift; c $A extra; g $A push -q --no-verify gitlab drift; g $A checkout -q main; g $A branch -q -D drift
O=$($S tidy $A 2>&1)
ok C4-tidy-dry-run '[[ $O == *"would delete origin/done"* && $O == *"would delete gitlab/done"* && $O != *"/main"* && $O != *"fresh"* && $O != *"/wip"* && $O != *"/staging"* && $O != *"origin/ff"* && $O != *"/next"* && $O == *"keep  gitlab/drift"* && -n $(g $T/td/github.com/org/app.git rev-parse -q --verify done) ]]'
$S tidy $A --apply >/dev/null 2>&1; ok C4-tidy-apply-needs-pr-check '[[ $? == 1 && -n $(g $T/td/github.com/org/app.git rev-parse -q --verify done) ]]'
$S tidy $A --apply --without-pr-check >/dev/null 2>&1
ok C4-tidy-apply '[[ -z $(g $T/td/github.com/org/app.git rev-parse -q --verify done) && -z $(g $T/td/gitlab.com/org/app.git rev-parse -q --verify done) && -n $(g $T/td/github.com/org/app.git rev-parse -q --verify wip) && -n $(g $T/td/github.com/org/app.git rev-parse -q --verify staging) && -n $(g $T/td/gitlab.com/org/app.git rev-parse -q --verify drift) && -n $(g $T/td/github.com/org/app.git rev-parse -q --verify main) ]]'
# guard tolerates odd hook input
ok G6-guard-non-dict-json '[[ $(echo "[1,2]" | $S guard; echo $?) == 0 && $(echo "{\"tool_input\":\"git push\"}" | $S guard; echo $?) == 0 ]]'
# global git pre-push hook (any tool, any repo)
HP=${AGENT_SHIP_HOOKS:-$HOME/.agent-os/git-hooks}; gp(){ git -c core.hooksPath=$HP -C "$@" }
mk hk; HK=$T/hk/app
c $HK one; gp $HK push -q origin main 2>/dev/null; ok P1-normal-push-allowed '[[ $? == 0 ]]'
g $HK reset -q --hard HEAD~1; c $HK other; gp $HK push -q --force origin main 2>/dev/null; ok P2-force-base-blocked '[[ $? != 0 && $(g $T/hk/github.com/org/app.git log -1 --format=%s main) == one ]]'
g $HK reset -q --hard origin/main; g $HK checkout -q -b feat; c $HK f1
gp $HK push -q gitlab feat 2>/dev/null; ok P3-mirror-before-github-blocked '[[ $? != 0 ]]'
gp $HK push -q origin feat 2>/dev/null && gp $HK push -q gitlab feat 2>/dev/null; ok P4-mirror-after-github-allowed '[[ $? == 0 ]]'
gp $HK push -q origin --delete main 2>/dev/null; ok P5-delete-base-blocked '[[ $? != 0 && -n $(g $T/hk/github.com/org/app.git rev-parse -q --verify main) ]]'
printf '#!/bin/sh\necho ran > "$(git rev-parse --git-common-dir)/repo-hook-ran"\nexit 0\n' > $HK/.git/hooks/pre-commit; chmod +x $HK/.git/hooks/pre-commit
printf '#!/bin/sh\ncat > "$(git rev-parse --git-common-dir)/repo-prepush-stdin"\nexit 0\n' > $HK/.git/hooks/pre-push; chmod +x $HK/.git/hooks/pre-push
gp $HK commit -q --allow-empty -m f2; gp $HK push -q origin feat 2>/dev/null
ok P6-repo-hooks-still-run '[[ -f $HK/.git/repo-hook-ran && $(cat $HK/.git/repo-prepush-stdin) == *refs/heads/feat* ]]'
printf '#!/bin/sh\nexit 1\n' > $HK/.git/hooks/pre-push; c $HK f3; gp $HK push -q origin feat 2>/dev/null; ok P7-repo-hook-can-still-block '[[ $? != 0 ]]'
rm $HK/.git/hooks/pre-push
mkdir -p $T/hk/git.heroku.com; git init -q --bare -b main $T/hk/git.heroku.com/app.git; g $HK remote add heroku $T/hk/git.heroku.com/app.git
g $HK push -q heroku main; g $HK checkout -q --orphan unrelated; c $HK u; gp $HK push -q --force heroku unrelated:main 2>/dev/null; ok P8-deploy-remote-not-judged '[[ $? == 0 ]]'
gp $HK push -q --force origin unrelated:main 2>/dev/null; ok P9-same-force-to-github-blocked '[[ $? != 0 ]]'; g $HK checkout -q feat
mk hu; HU=$T/hu/app; GH=$T/hu/github.com/org/app.git; GL=$T/hu/gitlab.com/org/app.git
c $HU base; gp $HU push -q origin main 2>/dev/null; g $HU reset -q --hard HEAD~1; c $HU rewrite
gp $HU push -q -f $GH/ main 2>/dev/null; ok P10-force-via-url-blocked '[[ $? != 0 && $(g $GH log -1 --format=%s main) == base ]]'
g $HU reset -q --hard origin/main; g $HU checkout -q -b viaurl; c $HU v; gp $HU push -q file://$GL viaurl 2>/dev/null; ok P10-mirror-via-url-blocked '[[ $? != 0 ]]'
mkdir -p $T/hu/github.com/up; git init -q --bare -b main $T/hu/github.com/up/app.git; g $HU remote add upstream $T/hu/github.com/up/app.git
g $HU push -q --no-verify upstream origin/main:refs/heads/main; g $HU checkout -q --orphan o2; c $HU o
gp $HU push -q -f upstream o2:main 2>/dev/null; ok P11-force-fork-upstream-base-blocked '[[ $? != 0 ]]'
g $HU checkout -q viaurl; c $HU v2; HOME=$T/nohome gp $HU push -q origin viaurl 2>/dev/null; ok P12-missing-tool-never-blocks '[[ $? == 0 ]]'
BR=$T/hu/srv.git; git init -q --bare -b main $BR; printf '#!/bin/sh\ncat >/dev/null; echo hit >> "%s/recv"\n' $T > $BR/hooks/post-receive; chmod +x $BR/hooks/post-receive
gp $HU push -q $BR viaurl 2>/dev/null; ok P13-server-hook-in-bare-repo-runs '[[ -f $T/recv ]]'
printf '#!/bin/sh\ncat >/dev/null; echo t >> "%s/rt"\n' $T > $HU/.git/hooks/reference-transaction; chmod +x $HU/.git/hooks/reference-transaction
gp $HU commit -q --allow-empty -m rt; ok P14-reference-transaction-runs '[[ -s $T/rt ]]'; rm $HU/.git/hooks/reference-transaction
printf '#!/bin/sh\ncat > "%s/stdin-copy"\n' $T > $HU/.git/hooks/pre-push; chmod +x $HU/.git/hooks/pre-push
c $HU p15; gp $HU push -q origin viaurl 2>/dev/null; ok P15-repo-hook-gets-exact-stdin '[[ $(wc -l < $T/stdin-copy | tr -d " ") == 1 && $(cut -d" " -f3 $T/stdin-copy) == refs/heads/viaurl ]]'; rm $HU/.git/hooks/pre-push
# local CI result posted to GitHub as a commit status (stub gh records the API call)
mkdir -p $T/bin; printf '#!/bin/sh\necho "$@" >> "%s/gh.log"\n' $T > $T/bin/gh; chmod +x $T/bin/gh
mk st; ST=$T/st/app; c $ST work; $S ci $ST >/dev/null 2>&1; SHA=$(g $ST rev-parse HEAD)
PATH=$T/bin:$PATH AGENT_SHIP_NO_STATUS= $S push $ST >/dev/null 2>&1
ok ST1-push-posts-status '[[ $(cat $T/gh.log) == *"repos/org/app/statuses/$SHA"* && $(cat $T/gh.log) == *"state=success"* && $(cat $T/gh.log) == *"context=agent-ship/local-ci"* ]]'
rm -f $T/gh.log; c $ST more; $S ci $ST >/dev/null 2>&1; SHA2=$(g $ST rev-parse HEAD)
PATH=$T/bin:$PATH AGENT_SHIP_NO_STATUS= gp $ST push -q origin main 2>/dev/null
for i in $(seq 1 20); do [[ -s $T/gh.log ]] && break; sleep 0.5; done
ok ST2-manual-push-posts-in-background '[[ $(cat $T/gh.log 2>/dev/null) == *"statuses/$SHA2"* ]]'
rm -f $T/gh.log; c $ST nostatus; $S ci $ST >/dev/null 2>&1; $S push $ST >/dev/null 2>&1; sleep 1
ok ST3-no-call-when-disabled '[[ ! -s $T/gh.log ]]'
# new project not on GitHub
mk ng; g $T/ng/app remote remove origin
ok C5-not-on-github-warning '[[ $($S topology $T/ng/app --json | jq -r ".warnings|join(\" \")") == *"not on github"* ]]'
ok C6-scorecard '[[ $($S scorecard) == *"CI runs"* ]]'
# floor guard: changes that lower the quality bar (fixtures per rule, acks, renames, ci integration)
source ${0:A:h}/floor-cases.sh

rm -rf $T; echo "agent-ship regression: $pass passed, $fail failed"; [[ $fail == 0 ]]
