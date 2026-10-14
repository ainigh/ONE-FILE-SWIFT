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
- Change `duration` in `AppDelegate` to adjust the length.

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
