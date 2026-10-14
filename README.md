# Machine Prompts Man

A work clock for macOS. Pick two. Work ten. Step away.

You choose what you are doing and what comes next. The ring counts down a ten-minute round. When
it ends you leave the desk for a while, plan the next round, and start again. Every phase change
is a handshake: you ask, A says yes or not yet, and you press Go. Only two things ever change a
clock: the clock running out, and your Go.

The spec and a browser version live in [`docs/`](docs/): open `docs/app.html` to try a round.
The Mac app is the same rules, the same screens, plus a voice, the menubar, and covers over every
display when time is up.

## Install

Paste this in Terminal (macOS 14 or newer):

```sh
curl -fsSL https://raw.githubusercontent.com/ainigh/ONE-FILE-SWIFT/main/install.sh | bash
```

It downloads the latest release into `~/Applications/MachinePromptsMan.app` and opens it. If
there's no release yet, it builds from the source instead, which needs Apple's command line tools
with Swift 6 (`xcode-select --install`). If the new copy quits as soon as it opens, the installer
puts the one you had back. Running the line again is always safe.

To install a branch that isn't merged yet, and follow that branch for updates:

```sh
curl -fsSL "https://raw.githubusercontent.com/ainigh/ONE-FILE-SWIFT/BRANCH/install.sh" | BRANCH=BRANCH bash
```

## Your first ten minutes

The app lives in your menu bar. Click the clock for the window; right-click it for the menu.

1. **Say what you're doing.** The first screen asks one thing: what would you like to do now?
   Type a line and press Return (or dictate it with the microphone button).
2. **Say what's next.** The same question again. Your second line becomes Next.
3. **Ready? OK.** Add more steps if you like, then OK. That asks to open the session and start
   round one.
4. **Go.** "Ready when you are." Press Go and the ring starts. Nothing else ever starts a round.
5. **Next phase.** Done early? Press Next phase to ask to move on, then Go. Not done? When time is
   up, every screen is covered and the clock waits for you, however long you are away.

Space does the one thing each screen asks for.

## The three roles

One window, three tabs. **B** works: the intake, the ring, the Strategy board, the request
screen. **A** answers requests: on autopilot the policy table answers at once; switch *Who
answers* to You and every request waits for you, with the policy's default beside it. A request
that waits for you also shows as a small card at the top right of the screen, over nothing.
**Admin** watches: the Monitor (every part of the app and every hand-off, live), the event log,
A's feed, and the switch for spoken confirmations.

## The voice

Every confirmation for B is spoken out loud: the engine's announcements (round start, the
reminders, time's up, the check-up, the plan, the break) and the request screen's lines ("Ready
when you are. Round 2: …"). It is on by default; Admin and Settings › General turn it off. The
voice is Kokoro, an open-source model that runs on this Mac through
[FluidAudio](https://github.com/FluidInference/FluidAudio); until it is downloaded (once, into
`~/.cache/fluidaudio`) the Mac's own best voice reads instead. Pick the voice under Settings ›
General. The announcements' wording follows the voice style at the foot of B's screen: Rich,
Varied or Fixed (the spec's wording, word for word).

## The arithmetic

Round length R (10 min), reminders r (3), sitting limit Ls (45 min), movement break Lb (3 min).
The base unit q = R ÷ 2^r = 1:15 is the snooze and the plan. Reminders come at 5:00, 2:30 and 1:15
left; the first two fade, the last covers the screen. The check-up after a round is
q · 2^(snoozes+1) ÷ (steps cleared + 1): each snooze doubles it, each step cleared divides it. A
check-up of 3 min or more resets the sitting clock. Settings › Session shows the whole table.

## Build it yourself

Needs Apple's command line tools with Swift 6 or newer (or Xcode 16+), macOS 14+.

```sh
make app      # builds build/MachinePromptsMan.app (and the .zip)
make install  # copies it into ~/Applications and opens it
make run      # builds and opens it from build/
make test     # the engine's tests (also run on Linux)
```

`MachinePromptsMan -speed 60` runs the clocks sixty times faster, for trying it out; so does Test
Mode in the menubar menu.

## Updates

The app follows `main` (or the branch it was installed from). It checks at launch, every 6 hours,
and from Settings › General. When the branch has a commit this copy wasn't built from, it offers
**Update to v1.0.N** (GitHub already built it) or **Update (build here)** (it builds the commit on
this Mac). Updating restarts the app, so it is offered between sessions only. Build output goes to
`~/Library/Logs/MachinePromptsMan/update.log`.

GitHub Actions tests the engine on Linux, tests and builds the app on macOS for every push, and
publishes a release (`v1.0.<run number>`, with `MachinePromptsMan.zip`) for every push to `main`.
The app is ad-hoc signed with a requirement of just its bundle identifier, so macOS keeps its
permissions across updates.

## What can't be blocked

Cmd-Option-Esc (Force Quit), Mission Control gestures and the power button are reserved by macOS.
The covers make casual dismissal impossible; nothing more.
