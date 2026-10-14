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
- **Right-click** → menu with Start / Quit (both disabled during a countdown).
- `./CountdownOverlay -duration 10` → 10-second countdown (1…3600; anything
  else falls back to 5). With the .app wrapper below you can persist it with
  `defaults write com.example.countdownoverlay duration -int 10`.
- `./CountdownOverlay --help` → usage.

## Robustness notes

- The count is derived from a wall-clock deadline, not from timer ticks, so it
  stays accurate under load and finishes correctly after system sleep.
- Keys are swallowed by an app-wide local event monitor (no accessibility
  permission needed), not just by whichever overlay happens to be key. If
  another app steals focus (Cmd-Tab), the overlay re-activates itself.
- Overlays are positioned in global screen coordinates, so secondary displays
  are covered correctly; display plug/unplug events are coalesced and rebuilt.
- The cursor is hidden while the overlay is up and always restored, including
  on quit.

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
