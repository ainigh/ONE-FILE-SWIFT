# CountdownOverlay

Menubar app: click the timer icon → every connected screen is covered by a
dark overlay with a 5-second countdown in the center. Esc, Cmd-W, Cmd-Q and
clicks are swallowed while it runs; it dismisses itself at 0.

## Build & run (no Xcode project needed)

```sh
swiftc -O -o CountdownOverlay main.swift -framework Cocoa
./CountdownOverlay
```

Requires Xcode command line tools (`xcode-select --install`), macOS 11+.

## Use

- **Left-click** the menubar icon → start countdown.
- **Right-click** → menu with Start / Quit (Quit is disabled during a countdown).
- The length defaults to 5 seconds. Override it per launch with an argument
  or an environment variable (argument wins; values outside 1–3600 fall back
  to the default). `-h` / `--help` prints usage.

  ```sh
  ./CountdownOverlay -duration 10
  COUNTDOWN_SECONDS=10 ./CountdownOverlay
  ```

## Robustness notes

- The count is derived from a deadline, not a once-per-second tick, so it
  never drifts and resolves correctly if the Mac sleeps mid-countdown.
- All key events to the process are swallowed by a local event monitor, and
  the app re-activates itself if it loses focus, so Cmd-Q / Esc can't slip
  through via another window.
- Overlays are rebuilt (coalesced, after a short delay) when displays are
  added, removed or resized, and placed in global coordinates so secondary
  displays are covered correctly.
- The cursor is hidden and the menubar icon dims while the countdown runs.
- The digits scale with the smallest screen dimension.
- Focus returns to the app that was frontmost before the countdown started.

## Optional: wrap it as a .app

```sh
mkdir -p CountdownOverlay.app/Contents/MacOS
cp CountdownOverlay CountdownOverlay.app/Contents/MacOS/
cat > CountdownOverlay.app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CountdownOverlay</string>
  <key>CFBundleIdentifier</key><string>com.example.countdownoverlay</string>
  <key>CFBundleName</key><string>CountdownOverlay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
open CountdownOverlay.app
```

## What can't be blocked

Cmd-Option-Esc (Force Quit), Mission Control gestures and the power button are
reserved by macOS. For a 5-second overlay that's acceptable; the app simply
makes casual dismissal (Esc, click, Cmd-Q) impossible.
