# Machine Prompts Man

A work clock for macOS: timed rounds of focused work where every phase change is a handshake.
The spec is `docs/`: `docs/app.html` with `docs/js/*.js` is the reference implementation (it runs
in a browser), `docs/Machine Prompts Man.md` the 2.1 handshake addendum, `docs/index.html` the
landing page. When the Mac app and the page disagree, the page is right unless the addendum says
otherwise. Read the JS file for the part you touch before changing its Swift counterpart.

## Layout

- `Package.swift`: a Swift package. `MPMCore` is Foundation-only and tested on Linux;
  `MachinePromptsMan` is the macOS app (SwiftUI in AppKit windows) and depends on FluidAudio.
- `Sources/MPMCore/`: the engine, ported file for file from `docs/js`:
  `Session.swift` (state.js, engine.js, voice.js: the clocks, phases, Go, the sit check, the
  clock loop), `Plan.swift` (store.js), `Requests.swift` (requests.js, pairs.js),
  `Announce.swift` (announce.js: every variant and tail), `Model.swift` (model.js),
  `Screens.swift` (the request screen and B's views as data, from screen-b.js), `Events.swift`
  (the parts and the event log, from monitor.js), `Feed.swift` (feed.js), `Config.swift`,
  `Format.swift`, `Speech.swift` (text to speak, from tool-mac-tool).
- `Sources/MachinePromptsMan/`: `main.swift` (the app delegate, the menubar ring and menu, the
  entry point), `AppModel.swift` (view state, settings on this Mac, the clock loop, the hooks:
  voice, sounds, feed, saving), `Windows.swift` (the main window, the covers on every screen,
  A's floating notice, the break band, the keyboard), `MainView.swift`, `BViews.swift`,
  `BoardView.swift`, `MapView.swift` (the mind map both maps use), `AViews.swift`,
  `AdminViews.swift`, `SettingsView.swift`, `CoverView.swift`, `Theme.swift` (the tokens of
  base.css), `Sound.swift` (the four tones), `Voice.swift` and `Neural.swift` (Kokoro and
  Parakeet through FluidAudio, from `ainigh/tool-mac-tool`), `Permissions.swift` (the output
  folder for transcripts), `Updater.swift`.
- `Tests/MPMCoreTests/`: the walkthrough of the addendum on the engine, and the speech logic.
- `scripts/make-app.sh`, `Makefile`, `install.sh`, `.github/workflows/build.yml`: build, bundle,
  sign, release and install. The in-app updater follows the branch it was built from.

## What the Mac adds to the page

- The voice: every confirmation for B is spoken (the engine's announcements and the request
  screen's lines), through Kokoro or the Mac's voice until Kokoro is downloaded. On by default;
  Admin and Settings › General turn it off.
- B's notifications (the last reminder, time's up, the check-up, every freeze, a request that is
  not a strip) cover every screen. A's notification (a request waiting for a person) is a
  floating card at the top right that covers nothing.
- The menubar item shows the ring and the time left; the window can be closed and the round goes
  on. Right-click the item for End Session, Session Transcript, System Monitor, Test Mode (60×),
  Mute Sounds, Spoken Confirmations, Open at Login, Schedule, Settings.

## Conventions

- macOS 14 or newer, Swift 6 toolchain to build (FluidAudio needs it); the package is
  tools-version 5.9 so the language mode stays Swift 5.
- `swift test` runs the core on any machine; `make app` builds the bundle on a Mac.
- No Swift toolchain exists in the cloud session; CI on the macOS runner is the compile check.
- Keep the core free of AppKit, and keep its functions named after the JS they port.
