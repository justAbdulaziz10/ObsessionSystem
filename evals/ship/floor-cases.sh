#!/bin/zsh
# agent-ship floor guard fixtures. Sourced by regression.sh (needs $T, $S, ok, mk, g, c from it).
# One throwaway repo per case: a base commit, then the change under test as the last commit.
fr(){ F=$T/fl/$1; rm -rf $F; mkdir -p $F; git init -q -b main $F }
w(){ mkdir -p "$(dirname "$F/$1")"; printf '%s\n' "${@:2}" > "$F/$1" }
cm(){ git -C $F add -A; git -C $F commit -qm "$1" }
fj(){ $S floor $F --committed --json 2>/dev/null }
rules(){ fj | jq -r '[.findings[]|select(.ack==null)|.rule]|unique|join(",")' }
nrule(){ fj | jq "[.findings[]|select(.rule==\"$1\")]|length" }
fx(){ $S floor $F --committed >/dev/null 2>&1; echo $? }

# --- each rule category is flagged ---
fr f1; w lib/a.dart 'void main() {' '  print(1);' '}'; cm base
w lib/a.dart 'void main() {' '  // ignore: avoid_print' '  print(1);' '}'; cm change
ok F1-dart-suppression '[[ $(rules) == suppression && $(fj | jq -r ".findings[0]|\"\(.file):\(.line)\"") == lib/a.dart:2 && $(fx) == 1 ]]'

fr f2; w test/a_test.dart "  test('a', () { expect(1, 1); });"; cm base
w test/a_test.dart "  test('a', () { expect(1, 1); }, skip: true);"; cm change
ok F2-dart-skip-test '[[ $(rules) == skip-test ]]'

fr f3; w src/a.ts 'export const x = 1;'; w src/a.test.ts "it('x', () => { expect(1).toBe(1) })"; cm base
w src/a.ts '// @ts-ignore' 'export const x: number = "s";'; w src/a.test.ts "it.only('x', () => { expect(1).toBe(1) })"; cm change
ok F3-ts-suppression-and-focus '[[ $(rules) == focus-test,suppression ]]'

fr f4; w Tests/AppTests/AppTests.swift 'func testA() throws {' '  XCTAssertTrue(true)' '}'; w Sources/App/A.swift 'let a = 1'; cm base
w Tests/AppTests/AppTests.swift 'func testA() throws {' '  try XCTSkipIf(true)' '  XCTAssertTrue(true)' '}'
w Sources/App/A.swift '// swiftlint:disable force_cast' 'let a = 1' 'func f() -> Int { fatalError("not implemented") }'
w Sources/App/V.swift 'required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }'; cm change
ok F4-swift-skip-suppression-stub '[[ $(rules) == skip-test,stub,suppression && $(nrule stub) == 1 ]]'

fr f5; w src/app.py 'x = foo()'; w tests/test_a.py 'def test_a():' '    assert 1'; cm base
w src/app.py 'x = foo()  # type: ignore'; w tests/test_a.py '@pytest.mark.skip(reason="later")' 'def test_a():' '    assert 1'
w src/svc.py 'def charge(amount):' '    raise NotImplementedError'
w src/base.py 'class Store(ABC):' '    @abstractmethod' '    def get(self):' '        raise NotImplementedError'; cm change
ok F5-python-suppression-skip-stub '[[ $(rules) == skip-test,stub,suppression && $(nrule stub) == 1 ]]'

fr f6; w .github/workflows/ci.yml 'on: push' 'jobs:' '  t:' '    runs-on: ubuntu-latest' '    steps:' '      - run: flutter analyze' '      - run: flutter test'; cm base
w .github/workflows/ci.yml 'on: push' 'jobs:' '  t:' '    runs-on: ubuntu-latest' '    steps:' '      # - run: flutter analyze' '      - run: flutter test' '        continue-on-error: true'; cm change
ok F6-workflow-commented-and-continue-on-error '[[ $(rules) == ci-weakened && $(nrule ci-weakened) == 2 ]]'

fr f7; w lib/foo.dart 'int foo() => 1;'; w test/foo_test.dart "test('f', () { expect(foo(), 1); });" "test('g', () { expect(foo(), 1); });"
w lib/bar.dart 'int bar() => 1;'; w test/bar_test.dart "test('b', () { expect(bar(), 1); });"; cm base
git -C $F rm -q test/foo_test.dart; git -C $F rm -q lib/bar.dart test/bar_test.dart; git -C $F commit -qm "drop tests"
ok F7-test-deleted-but-not-with-its-source '[[ $(rules) == test-deleted && $(fj | jq -r "[.findings[].file]|join(\",\")") == test/foo_test.dart ]]'

fr f8; w test/a_test.dart "test('a', () {" '  expect(a, 1);' '  expect(b, 2);' '  expect(c, 3);' '  expect(d, 4);' '  expect(e, 5);' '});'; cm base
w test/a_test.dart "test('a', () {" '  expect(a, 1);' '});'; cm change
ok F8-assertions-stripped '[[ $(rules) == assert-removed ]]'

fr f9; w pyproject.toml '[tool.coverage.report]' 'fail_under = 80'; w jest.config.js 'module.exports = { coverageThreshold: { global: {' '  branches: 80,' '} } };'; cm base
w pyproject.toml '[tool.coverage.report]' 'fail_under = 60'; w jest.config.js 'module.exports = { coverageThreshold: { global: {' '  branches: 70,' '} } };'; cm change
ok F9-coverage-thresholds-lowered '[[ $(rules) == threshold-lowered && $(nrule threshold-lowered) == 2 ]]'

fr f10; w analysis_options.yaml 'linter:' '  rules:' '    - avoid_print' '    - prefer_const_constructors' 'analyzer:' '  errors:' '    dead_code: error'
w .eslintrc.json '{ "rules": {' '  "no-console": "error",' '  "eqeqeq": "error"' '} }'; cm base
w analysis_options.yaml 'linter:' '  rules:' '    - prefer_const_constructors' 'analyzer:' '  errors:' '    dead_code: ignore' '    missing_return: ignore'
w .eslintrc.json '{ "rules": {' '  "no-console": "warn",' '  "eqeqeq": "error"' '} }'; cm change
ok F10-lint-removed-ignored-downgraded '[[ $(rules) == lint-downgraded && $(nrule lint-downgraded) == 4 ]]'

fr f11; w tsconfig.json '{ "compilerOptions": {' '  "strict": true' '} }'; cm base
w tsconfig.json '{ "compilerOptions": {' '  "strict": false,' '  "noImplicitAny": false' '} }'; cm change
ok F11-tsconfig-strict-off '[[ $(rules) == strict-off && $(nrule strict-off) == 2 ]]'

fr f12; w package.json '{ "scripts": {' '  "test": "jest"' '} }'; cm base
w package.json '{ "scripts": {' '  "test": "jest",' '  "ship": "git commit --no-verify -m wip"' '} }'; cm change
ok F12-no-verify-in-scripts '[[ $(rules) == no-verify ]]'

fr f13; w lib/s.dart 'class S {}'; w app/src/main/kotlin/A.kt 'fun a() = 1'; cm base
w lib/s.dart 'class S {' '  int build() {' '    // TODO: implement build' '    throw UnimplementedError();' '  }' '}'; w app/src/main/kotlin/A.kt 'fun a() = 1' 'fun b(): Int = TODO("later")'; cm change
ok F13-dart-kotlin-stubs '[[ $(rules) == stub && $(nrule stub) == 3 ]]'

fr f14; w main.go 'package main'; w src/lib.rs 'pub fn a() {}'; cm base
w main.go 'package main' 'var x = f() //nolint:errcheck'; w src/lib.rs '#[allow(dead_code)]' 'pub fn a() {}'; cm change
ok F14-go-rust-suppressions '[[ $(rules) == suppression && $(nrule suppression) == 2 ]]'

fr f15; w .gitlab-ci.yml 'test:' '  script: npm test'; w analysis_options.yaml 'analyzer:' '  language:' '    strict-casts: true'; cm base
w .gitlab-ci.yml 'test:' '  script: npm test || true' '  allow_failure: true'; w analysis_options.yaml 'analyzer:' '  language:' '    strict-casts: false'; cm change
ok F15-gitlab-swallow-and-dart-strict '[[ $(rules) == ci-weakened,strict-off && $(nrule ci-weakened) == 2 ]]'

# --- acknowledged, moved, generated and tightened changes pass ---
fr n1; w lib/a.dart 'void main() {' '  print(1);' '}'; cm base
w lib/a.dart 'void main() {' '  // ignore: avoid_print' '  print(1);' '}'; git -C $F add -A
git -C $F commit -qm "cli output" -m "Floor-Guard-Ack: suppression print is the CLI's output channel"
ok N1-ack-trailer-passes '[[ $(fx) == 0 && $(fj | jq -r ".findings[0].ack") == *"output channel"* ]]'
git -C $F commit -q --amend -m "cli output" -m "Floor-Guard-Ack: suppression ok"
ok N2-ack-without-reason-blocks '[[ $(fx) == 1 && $(fj | jq ".bad_acks|length") == 1 ]]'
git -C $F commit -q --amend -m "cli output" -m "Floor-Guard-Ack: suppression@test/* print is the CLI output channel"
ok N3-ack-glob-must-cover-file '[[ $(fx) == 1 ]]'
git -C $F commit -q --amend -m "cli output" -m "Floor-Guard-Ack: suppresion print is the CLI output channel"
ok N3-ack-unknown-rule-blocks '[[ $(fx) == 1 ]]'

fr n4; w test/a_test.dart "test('a', () {" '  expect(a, 1);' '  expect(b, 2);' '  expect(c, 3);' '  expect(d, 4);' '});'
w lib/old.dart '// ignore_for_file: avoid_print' 'void f() { print(1); }' 'void g() {}' 'void h() {}'; cm base
git -C $F mv test/a_test.dart test/renamed_test.dart; git -C $F mv lib/old.dart lib/new.dart; git -C $F commit -qm rename
ok N4-rename-not-flagged '[[ $(fx) == 0 && $(fj | jq ".findings|length") == 0 ]]'

fr n5; w lib/a.dart 'void a() {}' 'void f() {' '  // ignore: avoid_print' '  print(1);' '}' 'void z() {}'; cm base
w lib/a.dart 'void a() {}' 'void z() {}'; w lib/b.dart 'import "x.dart";' 'void f() {' '  // ignore: avoid_print' '  print(1);' '}'; cm move
ok N5-moved-code-not-flagged '[[ $(fx) == 0 ]]'

fr n6; w lib/x.dart 'int x = 1;'; cm base
w lib/a.g.dart '// ignore_for_file: type=lint'; w build/gen/x.dart '// ignore: a'; w node_modules/p/index.ts '// @ts-ignore'
w lib/l10n/strings.dart '// GENERATED CODE - DO NOT MODIFY BY HAND' '// ignore_for_file: type=lint'; w README.md 'Never use `git commit --no-verify` or `# noqa`.'; cm gen
ok N6-generated-vendored-docs-ignored '[[ $(fx) == 0 ]]'

fr n7; w pyproject.toml 'fail_under = 60'; w .eslintrc.json '{ "rules": {' '  "no-console": "warn"' '} }'; w tsconfig.json '{ "compilerOptions": {' '  "strict": false' '} }'; cm base
w pyproject.toml 'fail_under = 80'; w .eslintrc.json '{ "rules": {' '  "no-console": "error"' '} }'; w tsconfig.json '{ "compilerOptions": {' '  "strict": true' '} }'; cm tighten
ok N7-tightening-is-silent '[[ $(fx) == 0 ]]'

fr n8; w lib/a.dart '// ignore: avoid_print' 'void f() { print(1); }' 'int x = 1;'; cm base
w lib/a.dart '// ignore: avoid_print' 'void f() { print(1); }' 'int x = 2;'; cm edit
ok N8-existing-suppression-not-relitigated '[[ $(fx) == 0 ]]'

fr n9; w lib/x.dart 'int x = 1;'; cm base
w packages/foo_platform_interface/lib/foo.dart 'abstract class FooPlatform {' '  Future<int> get() {' "    throw UnimplementedError('get() has not been implemented.');" '  }' '}'
w lib/repo.dart 'abstract class Repo {' '  int load() => throw UnimplementedError();' '}'; cm iface
ok N9-abstract-and-platform-interface-stubs-exempt '[[ $(fx) == 0 ]]'

fr n10; w lib/a.dart 'int a = 1;'; cm base
w lib/a.dart '// ignore: unused' 'int a = 1;'
ok N10-worktree-default-sees-uncommitted '[[ $($S floor $F >/dev/null 2>&1; echo $?) == 1 && $(fx) == 0 ]]'
git -C $F checkout -q -- lib/a.dart; w test/new.test.ts "it.only('x', () => {});"
ok N10-worktree-sees-untracked '[[ $($S floor $F --json 2>/dev/null | jq -r "[.findings[].rule]|join(\",\")") == focus-test ]]'
rm -rf $F/test
ok N11-range-option '[[ $($S floor $T/fl/f1 --range HEAD~1..HEAD >/dev/null 2>&1; echo $?) == 1 && $($S floor $T/fl/f1 --range HEAD~1..HEAD~1 >/dev/null 2>&1; echo $?) == 0 ]]'
ok N11-bad-range-exit-2 '[[ $($S floor $T/fl/f1 --range nope..HEAD >/dev/null 2>&1; echo $?) == 2 ]]'

fr n12; w Tests/AppTests/ATests.swift 'final class ATests: XCTestCase {' '}'; w tests/test_a.py 'import os'; cm base
w Tests/AppTests/ATests.swift 'final class ATests: XCTestCase {' '  func testA() throws {' '    guard ProcessInfo.processInfo.environment["DUO"] == "1" else {' '      throw XCTSkip("needs the Duo simulator")' '    }' '  }' '}'
w tests/test_a.py 'import os' 'def test_a():' '    if not os.environ.get("NET"):' '        pytest.skip("needs network")'; cm gated
ok N12-conditional-skips-are-skipif '[[ $(fx) == 0 ]]'
fr n12b; w Tests/AppTests/ATests.swift 'final class ATests: XCTestCase {' '  func testA() throws {' '  }' '}'; cm base
w Tests/AppTests/ATests.swift 'final class ATests: XCTestCase {' '  func testA() throws {' '    throw XCTSkip("broken, later")' '  }' '}'; cm unconditional
ok N12-unconditional-xctskip-flagged '[[ $(rules) == skip-test ]]'

fr n13; w test/a_test.dart "test('a', () {" '  expect(a, 1);' '  expect(b, 2);' '  expect(c, 3);' '  expect(d, 4);' '});'; cm base
w test/a_test.dart "test('a', () {" '  expect(a, 10);' '  expect(b, 20);' '  expect(c, 30);' '  expect(d, 40);' '});'; cm rewrite
ok N13-rewritten-assertions-not-flagged '[[ $(fx) == 0 ]]'

fr n14; w app/x.py 'def f(r):' '    return r.model_validate(p)  # type: ignore[attr-defined]'; cm base
w app/x.py 'def f(r):' '    return r.model_validate(p), mode  # type: ignore[attr-defined]'; cm edit
ok N14-edited-line-keeps-its-existing-suppression '[[ $(fx) == 0 ]]'

# --- inside `ci`, on the push range ---
mk fc; FC=$T/fc/app; g $FC checkout -q -b feat; mkdir -p $FC/test; echo "test.skip('x', () => { expect(1).toBe(1) })" > $FC/test/a.test.ts
g $FC add -A; g $FC commit -qm skip; O=$($S ci $FC 2>&1)
ok FC1-ci-blocks-on-floor '[[ $? == 1 && $O == *"FAIL floor guard"* && $O == *"[skip-test] test/a.test.ts:1"* ]]'
g $FC commit -q --amend -m skip -m "Floor-Guard-Ack: skip-test upstream sandbox is down, re-enable in #42"
$S ci $FC >/dev/null 2>&1; ok FC2-ci-ack-passes '[[ $? == 0 ]]'
mk fp; FP=$T/fp/app; mkdir -p $FP/lib; printf '// ignore: x\nint a = 1;\n' > $FP/lib/a.dart; g $FP add -A; g $FP commit -qm pub; g $FP push -q origin main; g $FP fetch -q --all
g $FP checkout -q -b feat; echo 'int b = 1;' > $FP/lib/b.dart; g $FP add -A; g $FP commit -qm clean
$S ci $FP >/dev/null 2>&1; ok FC3-published-lines-not-rescanned '[[ $? == 0 ]]'
g $FP checkout -q main; printf '// ignore_for_file: y\n' > $FP/lib/c.dart; g $FP add -A; g $FP commit -qm main2; g $FP push -q origin main; g $FP fetch -q --all
g $FP checkout -q feat; g $FP merge -q --no-edit origin/main
$S ci $FP >/dev/null 2>&1; ok FC4-merged-in-main-not-judged '[[ $? == 0 ]]'
cp $T/profiles.json $T/profiles.bak; echo '{"profiles":[{"name":"t","match":["*app*"],"ci":["true"],"floor_guard":false}]}' > $T/profiles.json
g $FC commit -q --amend -m skip; $S ci $FC >/dev/null 2>&1; r1=$?; $S floor $FC >/dev/null 2>&1; r2=$?
ok FC5-profile-opt-out '[[ $r1 == 0 && $r2 == 0 ]]'
echo '{"profiles":[{"name":"t","match":["*app*"],"ci":["true"],"floor_allow":["noqa: TCH00[12]"],"floor_ignore":["legacy/*"]}]}' > $T/profiles.json
mk fa; FA=$T/fa/app; mkdir -p $FA/app $FA/legacy; echo 'from x import Session  # noqa: TCH002' > $FA/app/a.py; echo '// @ts-ignore' > $FA/legacy/b.ts
g $FA add -A; g $FA commit -qm idiom; $S ci $FA >/dev/null 2>&1; r1=$?
echo 'import y  # noqa: E501' > $FA/app/c.py; g $FA add -A; g $FA commit -qm other; $S ci $FA >/dev/null 2>&1
ok FC6-profile-allow-and-ignore '[[ $r1 == 0 && $? == 1 ]]'
mv $T/profiles.bak $T/profiles.json

# --- measurement: `ci` appends one line per floor evaluation; `floor --stats` summarises (own state dir) ---
FS=$T/fs-state; FL=$FS/floor-log.jsonl; fs(){ AGENT_SHIP_DIR=$FS $S "$@" }
mk fs; FR=$T/fs/app; g $FR checkout -q -b feat; mkdir -p $FR/test; echo "test.skip('x', () => { expect(1).toBe(1) })" > $FR/test/a.test.ts
g $FR add -A; g $FR commit -qm skip; fs ci $FR >/dev/null 2>&1; r1=$?
ok FS1-ci-logs-blocked-evaluation '[[ $r1 == 1 && $(wc -l < $FL) -eq 1 && $(tail -1 $FL | jq -r "[.blocked,.branch,(.rules|join(\",\")),.findings[0].ack,(.range|test(\"HEAD\"))]|map(tostring)|join(\" \")") == "true feat skip-test null true" ]]'
g $FR commit -q --amend -m skip -m "Floor-Guard-Ack: skip-test upstream sandbox is down, re-enable in #42"; fs ci $FR >/dev/null 2>&1; r1=$?
ok FS2-ci-logs-ack-reason '[[ $r1 == 0 && $(tail -1 $FL | jq -r "[.blocked,.findings[0].ack,.acks[0].reason]|map(tostring)|join(\"|\")") == "false|upstream sandbox is down, re-enable in #42|upstream sandbox is down, re-enable in #42" ]]'
O=$(fs floor --stats --json)
ok FS3-stats-per-rule '[[ $(jq -r "[.evaluations,.blocked_evaluations,.rules[\"skip-test\"].findings,.rules[\"skip-test\"].acked,.rules[\"skip-test\"].blocked,.rules[\"skip-test\"].top_ack_reasons[0][0]]|map(tostring)|join(\"|\")" <<< $O) == "2|1|2|1|1|upstream sandbox is down, re-enable in #42" ]]'
fs ci $FR >/dev/null 2>&1
ok FS4-rerun-same-commit-counts-once '[[ $(wc -l < $FL) -eq 3 && $(fs floor --stats --json | jq .evaluations) == 2 ]]'
AGENT_SHIP_FLOOR_LOG_MAX=1 fs ci $FR >/dev/null 2>&1
ok FS5-log-rotates-and-stats-reads-both '[[ -s $FL.1 && $(wc -l < $FL) -eq 1 && $(fs floor --stats --json | jq .evaluations) == 2 ]]'
echo '{"epoch": 1000, "repo": "old", "head": "x", "range": "HEAD", "findings": [{"rule": "suppression", "file": "a.py", "ack": null}], "blocked": true}' >> $FL
O=$(fs floor --stats); O2=$(fs floor --stats --days 100000 --json | jq .evaluations)
ok FS6-stats-window-and-table '[[ $O == *"2 evaluation(s) in 1 repo(s), 1 blocked"* && $O == *"skip-test"*"1x upstream sandbox"* && $O != *suppression* && $O2 == 3 ]]'
n=$(cat $FL $FL.1 | wc -l); fs floor $FR >/dev/null 2>&1; AGENT_SHIP_DIR=$T/fs-empty $S floor --stats > $T/fs-empty.out
ok FS7-standalone-floor-not-logged-and-empty-stats '[[ $(cat $FL $FL.1 | wc -l) -eq $n && $(cat $T/fs-empty.out) == "no floor evaluations recorded"* ]]'
rm -rf $FS; mkdir -p $FL; O=$(fs ci $FR 2>&1)
ok FS8-unwritable-log-keeps-ci-verdict '[[ $? == 0 && $O == *"could not record floor evaluation"* && $O == *"local CI PASSED"* ]]'
