# CountdownOverlay → Machine Prompts Man

This repository started as a one-file menubar countdown overlay (`Sources/CountdownOverlay/main.swift`).
It is now the ground for the app specified in `docs/`: **Machine Prompts Man**, a work clock for
macOS. Read `docs/Machine Prompts Man.md` (the 2.1 handshake addendum) and `docs/index.html` (the
landing page: phases, arithmetic, screens) before implementing any of it. Nothing of that app is
implemented yet; what exists is the plumbing it will need.

## Layout

- `Package.swift`: a Swift package. `CountdownCore` is Foundation-only (tested on Linux);
  `CountdownOverlay` is the macOS app (AppKit, no SwiftUI yet) and depends on FluidAudio.
- `Sources/CountdownOverlay/main.swift`: the app. Config, the overlay windows, the updater, and the
  app delegate (menubar item, countdown, voice and folder wiring). Top-level code at the end.
- `Sources/CountdownOverlay/Voice.swift`, `Neural.swift`: text to speech (Kokoro through
  FluidAudio, the Mac's own voice until Kokoro is downloaded) and speech to text (Parakeet).
  Ported from `ainigh/tool-mac-tool`, which works on the owner's Mac; keep them close to that
  source so fixes can be carried across.
- `Sources/CountdownOverlay/Permissions.swift`: the user-chosen output folder (bookmark) and
  writing dated files into it.
- `Sources/CountdownCore/Speech.swift`: spoken-text cleaning and sentence splitting, the phrase
  cutter for microphone audio, voice choice. Tests in `Tests/CountdownCoreTests`.
- `scripts/make-app.sh`, `Makefile`, `install.sh`, `.github/workflows/build.yml`: build, bundle,
  sign, release and install. The in-app updater (in `main.swift`) follows the branch it was built
  from and uses the same script to build on the Mac when GitHub hasn't.

## Conventions

- macOS 14 or newer, Swift 6 toolchain to build (FluidAudio needs it); the package itself is
  tools-version 5.9 so the language mode stays Swift 5.
- Everything a contributor runs locally: `swift test` (core), `make app` (the bundle).
- Permissions macOS asks for are exercised deliberately: each countdown says the time and saves it
  to the chosen folder (Files and Folders), and the menu's Listen uses the microphone. Keep
  `PromptSafety` in mind: the overlay windows float above everything, so lower them while macOS
  may be asking.
- No Swift toolchain exists in the cloud session; CI on the macOS runner is the compile check.
