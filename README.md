# CountdownOverlay

Menubar app: click the timer icon → every connected screen is covered by a
dark overlay with a 5-second countdown in the center. Esc, Cmd-W, Cmd-Q and
clicks are swallowed while it runs; it dismisses itself at 0.

It is also the ground for the app described in [`docs/`](docs/): **Machine Prompts Man**, a work
clock for macOS. The app in `docs/` is not implemented yet. What is here is the plumbing it needs:
a Swift package with a menubar app, text to speech and speech to text that run on the Mac, a
user-chosen folder to write to, GitHub builds and releases, an installer and an in-app updater.
See `CLAUDE.md` for the layout.

## Install

Paste this in Terminal (macOS 14 or newer):

```sh
curl -fsSL https://raw.githubusercontent.com/ainigh/ONE-FILE-SWIFT/main/install.sh | bash
```

It downloads the latest release into `~/Applications/CountdownOverlay.app` and opens it. If
there's no release yet (GitHub Actions hasn't built one), it builds from the source instead,
which needs Apple's command line tools with Swift 6 (`xcode-select --install`). If the new copy
quits as soon as it opens, the installer puts the one you had back. Running the line again is
always safe.

To install a branch that isn't merged yet, and follow that branch for updates:

```sh
curl -fsSL "https://raw.githubusercontent.com/ainigh/ONE-FILE-SWIFT/BRANCH/install.sh" | BRANCH=BRANCH bash
```

## Use

- **Left-click** the menubar icon → start countdown. It says the current time and saves it to a
  new file (`countdown-<date>T<time>.txt`) in the folder you chose; the first countdown asks for
  the folder before the overlay comes up.
- **Right-click** → menu:
  - **Start Countdown**
  - **Choose Output Folder…** (shows the current one), **Say and Save the Time**, **Listen for
    5 Seconds** (the microphone; it says back what it heard and saves it as `heard-….txt`)
  - the version, **Check for Updates…** and, when there is one, the update
  - **Quit** (disabled during a countdown, like everything that would restart the app)
- The length defaults to 5 seconds. Override it per launch with an argument
  or an environment variable (argument wins; values outside 1–3600 fall back
  to the default). `-h` / `--help` prints usage, `--version` the version and commit.

  ```sh
  ./CountdownOverlay -duration 10
  COUNTDOWN_SECONDS=10 ./CountdownOverlay
  ```

## Voices and listening

The app speaks with **Kokoro** and listens with **Parakeet**, open-source models that run on this
Mac through [FluidAudio](https://github.com/FluidInference/FluidAudio) (Core ML, on the Neural
Engine). Each is downloaded once, the first time it's needed, into `~/.cache/fluidaudio`; after
that everything works offline. Until Kokoro is downloaded, the Mac's own best voice reads instead,
so nothing waits. The menu shows the download while it runs. This is the same voice code as
`ainigh/tool-mac-tool`.

## Permissions

macOS asks for two things, each the first time it's needed, and the app is built so the question
is never hidden under the overlay:

- **Files and Folders**: the folder you chose, if it's under Desktop, Documents or Downloads.
  Asked when the first file is written.
- **Microphone**: when you choose Listen.

The app is ad-hoc signed with a requirement of just its bundle identifier
(`com.ainigh.CountdownOverlay`), so macOS keeps those grants across updates. To sign with your
own certificate instead, run
`defaults write com.ainigh.CountdownOverlay signIdentity "THE CERTIFICATE NAME"` once; updates
built on your Mac are then signed with it.

## Updates

The app follows `main` (or the branch it was installed from). It checks at launch, every 6
hours, and when you choose **Check for Updates…** in the right-click menu, which always shows the
version and commit you're on. When the branch has a commit this copy wasn't built from, the menu
offers:

- **Update to v1.0.N**: GitHub already built that commit. The app downloads it, swaps itself and
  reopens.
- **Update (build here)**: GitHub hasn't built it yet. The app downloads that commit's source,
  builds it on this Mac, swaps itself and reopens. Build output goes to
  `~/Library/Logs/CountdownOverlay/update.log`.

Updating is offered only between countdowns, since it restarts the app. If an update fails,
**Copy Update Details** copies the error and the end of the log.

GitHub Actions (`.github/workflows/build.yml`) tests the core on Linux, tests and builds the app
on macOS for every push, and publishes a release (`v1.0.<run number>`, with
`CountdownOverlay.zip`) for every push to `main`.

## Build it yourself

Needs Apple's command line tools with Swift 6 or newer (or Xcode 16+), macOS 14+.

```sh
make app      # builds build/CountdownOverlay.app (and build/CountdownOverlay.zip)
make install  # copies it into ~/Applications and opens it
make run      # builds and opens it from build/
make test     # the CountdownCore tests (also run on Linux)
```

A copy you build yourself still checks for updates and follows `main`.

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

## What can't be blocked

Cmd-Option-Esc (Force Quit), Mission Control gestures and the power button are
reserved by macOS. For a 5-second overlay that's acceptable; the app simply
makes casual dismissal (Esc, click, Cmd-Q) impossible.
