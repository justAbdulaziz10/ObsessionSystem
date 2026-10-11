# Repro, log, and loop commands by stack

Use the repo's own scripts (Makefile, `package.json`, `justfile`, `verify-<app>` skill) when they exist; these are fallbacks. Replace `<id>` with the session's debug tag.

| Stack | Focused repro | Tagged log | Repeat for flakes |
|---|---|---|---|
| Flutter/Dart | `flutter test test/x_test.dart --plain-name "case"`; `dart test test/x_test.dart --plain-name "case"`; device flow: `flutter test integration_test/x_test.dart -d <device>` | `debugPrint('[DEBUG-<id>] $value');` | shell loop below |
| Swift/Xcode | `swift test --filter Suite/testCase`; `xcodebuild test -scheme S -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:Target/Suite/testCase` | `print("[DEBUG-<id>] \(value)")` | `xcodebuild test ... -test-iterations 50 -run-tests-until-failure` |
| TS/web | `npx vitest run path -t "case"`; `npx jest path -t "case"`; `npx playwright test file -g "case"` | `console.log('[DEBUG-<id>]', value);` | `npx playwright test -g "case" --repeat-each 50`; shell loop |
| Python | `python -m pytest path::test_case -x -q`; `python -I repro.py` | `print(f"[DEBUG-<id>] {value!r}", file=sys.stderr)` | shell loop below |
| Android/Kotlin | `./gradlew :app:testDebugUnitTest --tests "pkg.ClassTest.method"`; instrumented: `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=pkg.ClassTest#method` | `Log.d("DEBUG-<id>", "value=$value")` | shell loop below |
| HTTP service | `curl -sS -o /tmp/out.json -w '%{http_code}\n' "$BASE_URL/path"` then assert on status and body | the service's logger, prefixed `[DEBUG-<id>]` | shell loop below |

Use an isolated simulator or emulator. Leave a device another person or agent is using untouched.

## Shell loop for a failure rate

```bash
fails=0; for i in $(seq 50); do <cmd> >/dev/null 2>&1 || fails=$((fails+1)); done; echo "failed $fails/50"
```

## Bisect between two known states

```bash
git bisect start <bad-sha> <good-sha>
git bisect run <cmd>      # <cmd> exits 0 = good, 1-124 = bad, 125 = skip
git bisect reset
```

## Assert an exact symptom

Save as a script so the repro exits non-zero only on the reported symptom. Read the log on every GREEN: a different failure also prints GREEN.

```bash
#!/usr/bin/env bash
# repro.sh: exit 1 only when the reported symptom appears
<cmd> > /tmp/repro.log 2>&1
if grep -q "the exact error text" /tmp/repro.log; then echo RED; exit 1; fi
echo GREEN
```

## Bug only a human can trigger

When a step needs a person (physical device, hardware, third-party login), write a short script that prints each step, waits for Enter, and saves the logs it captures to a file you read afterwards. Run it only in an interactive session; non-interactive runs record a blocker instead.

## Cleanup check

```bash
git grep -n "DEBUG-<id>"   # exit status 1 (no matches) = clean
```
