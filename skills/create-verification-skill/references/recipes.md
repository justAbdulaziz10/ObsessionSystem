# Harness recipes by surface

Use the repo's own harness when it has one. Otherwise start from the matching recipe, replace every example with this repo's real values, and prove it once. Install missing tools project-locally, or ask before a global install.

## Web app (browser)

- Launch the dev server on a free port (`PORT=0` or pick one and check it), wait for HTTP 200 on a health route.
- Drive with Playwright (`npx playwright` in a JS project, `python -m playwright` otherwise). Locate by role and accessible name (`getByRole('button', { name: 'Save' })`), then test IDs.
- Evidence: `page.screenshot`, `page.accessibility.snapshot()` or `ariaSnapshot()`, console messages, failed network requests, the API response behind the action, a video for flows (`recordVideo`).
- Isolation: a fresh browser context and storage state per run; a disposable database or schema.

## Desktop: Electron, Tauri, web views

- Launch with `--remote-debugging-port=<free port>` and drive through Chrome DevTools Protocol (Playwright `connectOverCDP`).
- Native macOS apps: XCUITest, or `osascript` with Accessibility for simple flows; `screencapture -l <windowid>` for evidence.

## iOS, iPadOS, macOS (Swift/SwiftUI)

- Use a dedicated simulator per run: `xcrun simctl create verify-<app>-<run> <device type> <runtime>` and boot it. Never touch a simulator you did not create.
- Build and install: `xcodebuild -scheme <S> -destination 'id=<UDID>' -derivedDataPath build/verify build`, then `xcrun simctl install <UDID> <.app>` and `xcrun simctl launch --console-pty <UDID> <bundle id>`.
- Drive: XCUITest targets for real interaction, `xcrun simctl openurl` for deep links, `xcrun simctl push` for notifications, `xcrun simctl privacy` for permissions. Give views `accessibilityIdentifier`s.
- Evidence: `xcrun simctl io <UDID> screenshot <png>`, `xcrun simctl io <UDID> recordVideo <mov>`, `log stream --predicate 'subsystem == "<bundle id>"'`, the xcresult bundle.
- Cleanup: `xcrun simctl shutdown <UDID>` and `xcrun simctl delete <UDID>` for simulators this run created only.
- Xcode MCP tools (BuildProject, RunSomeTests, RenderPreview) help when Xcode has the workspace open.

## Flutter

- Pick the device explicitly (`flutter devices`); create a simulator or emulator per run as above or below.
- Drive with `integration_test` and `flutter test integration_test/<x>_test.dart -d <device>`; find widgets by `Key('...')` or semantics labels. For flows outside the app (permissions, notifications) combine with simctl or adb.
- Evidence: `IntegrationTestWidgetsFlutterBinding.takeScreenshot`, or the platform screenshot commands; `flutter logs -d <device>`.
- Dart MCP tools can run tests, analyze, and inspect the widget tree of a running app.

## Android (Kotlin/Compose)

- Create a dedicated AVD or use an emulator serial this run started: `emulator -avd <name> -no-window -no-snapshot-save -port <even port>`; wait for `adb -s emulator-<port> wait-for-device` and `getprop sys.boot_completed` = 1.
- Install and launch: `./gradlew installDebug`, `adb -s <serial> shell am start -n <pkg>/<activity>`, deep links with `am start -a android.intent.action.VIEW -d <uri>`.
- Drive: Compose UI tests / Espresso for real flows; `adb shell uiautomator dump` plus `adb shell input tap|text|keyevent` for quick drives (find bounds from the dump, not guessed coordinates). Set `testTag`s.
- Evidence: `adb exec-out screencap -p > shot.png`, `adb shell screenrecord`, `adb logcat -d --pid=$(adb shell pidof <pkg>)`.
- Cleanup: `adb -s <serial> emu kill` for emulators this run started.

## CLI and TUI

- Build once. Drive each case in a fresh PTY: `expect` scripts or Python `pexpect`; `tmux` with `send-keys` and `capture-pane -p` for full-screen TUIs.
- Evidence: the command, stdin, stdout, stderr, exit code, and any files written (diff the working dir before/after).
- Isolation: a temp HOME/config dir per run (`HOME=$(mktemp -d)`), so the user's config is never touched.

## HTTP, gRPC, WebSocket services and APIs

- Launch the service (or `docker compose up -d` with a project name per run: `-p verify-<run>`); wait on the health endpoint.
- Drive with `curl -sS -w '%{http_code}'`, `grpcurl`, `websocat`, or the repo's client SDK. Use seeded test users and tokens from a test config, never production secrets.
- Evidence: request, response status, headers, body, and a read-back of the stored state (a GET after a POST, or a DB query).
- Load or latency claims: `hey`/`k6` with a fixed workload, before and after, several runs, report median and range.

## Networks and distributed systems

- Build the topology in containers: one compose project per run with its own network; add fault injection with `tc netem` inside a Linux container or Toxiproxy.
- Drive: send real traffic between nodes (`curl`, `nc`, `iperf3`, the protocol's client).
- Evidence: `tcpdump -i <iface> -w capture.pcap` inside the container (host capture needs sudo; ask first), then `tshark`/Wireshark to read it; per-node logs with timestamps; convergence state queried from each node.
- Cleanup: `docker compose -p verify-<run> down -v`.

## Embedded, firmware, hardware

- Prefer simulation first: QEMU or Renode for MCUs, Wokwi for Arduino/ESP32, the vendor's simulator, or host-built unit tests of the logic (PlatformIO `pio test -e native`, install).
- Real device: identify it by serial number, not port order (`ls /dev/cu.*`, `system_profiler SPUSBDataType`). Doctor checks the board ID and firmware version before any action.
- Flashing changes a physical device: the skill must require the user's approval for the first flash on a board and record the previous firmware so it can be restored.
- Drive: serial commands with `pyserial` or `screen`/`expect` on the tty; GPIO/relay rigs or a test fixture for hardware-in-the-loop; `sigrok-cli` for logic-analyzer captures.
- Evidence: the serial transcript with timestamps, logic captures, sensor readings, photos/video when only a human-visible effect exists (say so).

## Games and graphics

- Launch in windowed or headless mode with a fixed seed and fixed timestep. Drive with scripted input (an input-replay file, an automation hook in a debug build, or CDP for web games).
- Evidence: screenshots at named frames, frame-time stats, a replay file that reproduces the run.

## Data pipelines, ML, and batch jobs

- Run against a small frozen fixture dataset with a fixed seed. Compare outputs with a golden file or invariants (row counts, schema, metric thresholds).
- Evidence: the input fixture hash, output sample, metrics, and runtime. Before trusting a metric, explain the number: what limits it, repeat runs, same environment, and whether the work ran inside the measured region.

## Libraries and SDKs

- Drive through the public API exactly as a consumer would: a tiny example project or doc snippet that imports the built package, not the source tree.
- Evidence: the example's output and exit code, and type-check of the example against the published types.
