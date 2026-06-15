# Caffeinator

A tiny macOS menu bar app that stops your Mac from going to sleep when you
need it to stay awake — long downloads, video calls, presentations, file
transfers, renders, backups, anything that takes a while.

It's a friendly front end for the built-in macOS command `caffeinate`. You
get a coffee-cup icon in the menu bar instead of a Terminal command. When the
cup is **full**, your Mac stays awake; when it's **empty**, your Mac sleeps
normally.

```
☕  full cup  →  staying awake
☕  empty cup →  sleeping normally
```

---

## For everyday use

Click the cup in the menu bar to open the menu:

| Menu item | What it does |
| --- | --- |
| **Keep my Mac awake** / **Let my Mac sleep** *(⌘T)* | The main switch. Turns staying-awake on or off. |
| **Keep awake** | A heading — not clickable. The four options below it are independent checkboxes; turn on any combination. |
| &nbsp;&nbsp;The screen | Keeps the display on (no screen dimming or sleep). |
| &nbsp;&nbsp;The system, even when idle | Keeps the whole Mac awake even with no activity. |
| &nbsp;&nbsp;Storage (good for backups, downloads) | Keeps disks spun up — useful during backups and downloads. |
| &nbsp;&nbsp;Never sleep while plugged in | Stops the whole Mac from sleeping while on AC power. |
| **Turn off after…** | A submenu: auto-stop after 15 min, 30 min, 1/2/4/8 hours, or run until you turn it off. |
| **Until an app or task finishes…** | Stay awake until a chosen app or task quits — then stop automatically. (While one is already being watched this reads **Wait for a different app or task…**.) |
| **Open when I log in** | Start Caffeinator automatically every time you sign in. |
| **About Caffeinator** | A plain-language description of what the app does. |
| **Quit Caffeinator** *(⌘Q)* | Quit the app (your Mac immediately goes back to sleeping normally). |

The first line of the menu always tells you the current state, for example:
*"Your Mac sleeps normally"*, *"Keeping your Mac awake"*, *"Awake · 1 h 23 min
left"*, *"Awake while Zoom is running"*, or *"Off — saving battery (8% left)"*
when the low-battery guard has stepped in.

### Stay awake until an app or task finishes

Choose **Until an app or task finishes…** to open a searchable list of what's
running. Type in the **Search by name** field — it matches by name, and also by
process ID or path — then pick the app and click **Wait for this**. Caffeinator
keeps your Mac awake until that app quits, then turns itself off. Tick **Show
background tasks too** to include things without a window (for advanced users).

### Battery protection

If you're on battery power and the charge drops to **10 % or below**,
Caffeinator automatically turns itself off and greys out the controls so your
Mac can sleep and save power. Plug in (or charge above 10 %) and it's available
again. This guard never triggers on a Mac without a battery or while plugged in.

---

## Install

### Option A — build it yourself (recommended)

Requires the Xcode command-line tools (Swift 5.9+) on macOS 11 or newer.

```sh
git clone <this-repo>
cd caffeinate
make install      # builds, bundles, and copies Caffeinator.app to /Applications
open /Applications/Caffeinator.app
```

The first time you launch, macOS Gatekeeper may ask you to confirm — open it
once from **Applications** (or right-click → Open) to get past the prompt. The
app is ad-hoc signed, not notarized.

### Option B — just build and run locally

```sh
make run          # builds, bundles to .build/Caffeinator.app, and launches it
```

---

## Building from source

| Command | What it does |
| --- | --- |
| `make` / `make bundle` | Build release binary and assemble `.build/Caffeinator.app`. |
| `make run` | Bundle, then launch the app. |
| `make build` | Compile only (`swift build -c release`), no bundling. |
| `make install` | Bundle and copy to `/Applications`. |
| `make uninstall` | Remove the app, its LaunchAgent, and unload it from `launchd`. |
| `make clean` | Remove all build artifacts. |

The build assembles a real `.app` bundle by hand (binary + `Info.plist`) and
ad-hoc codesigns it (`codesign --force --sign -`) so macOS treats it as a
stable identity for permissions and login items.

The app runs as a menu-bar–only agent (`LSUIElement` / `.accessory`
activation policy) — no Dock icon, no main window.

---

## How it works

Caffeinator never reimplements sleep prevention itself — it drives the
system's own `/usr/bin/caffeinate` tool and reflects its state in the menu bar.

- **`main.swift`** — bootstraps the `NSApplication` as a background agent.
  Before anything else it checks for an already-running copy with the same
  bundle ID and exits immediately if found, so you can never launch two
  instances (whether via `open`, Finder, or login items).

- **`CaffeinateController.swift`** — owns the child `caffeinate` process.
  It assembles the flags, adds `-t <seconds>` for a timer or `-w <pid>` to
  wait on a process, and launches it. When `caffeinate` exits on its own
  (the timer elapsed or the watched app quit) a termination handler clears
  the state and updates the UI. Turning it off sends `SIGTERM` and waits, so
  no stray sleep assertions are ever left behind.

- **`AppDelegate.swift`** — builds the `NSStatusItem` and menu, persists your
  choices in `UserDefaults`, and ties everything together. The menu is
  refreshed every time it opens so the remaining-time and status lines stay
  current.

- **`PowerMonitor.swift`** — watches power changes through IOKit
  (`IOPSNotificationCreateRunLoopSource`). Each notification produces a
  snapshot of battery presence, on-battery vs. plugged-in state, and charge
  percentage, which drives the low-battery guard.

- **`ProcessPickerWindowController.swift`** — the "wait for an app or task"
  window: a searchable, icon-rich list built from `NSWorkspace`'s running
  applications, plus optional background processes from `ps -axo pid=,comm=`.
  Typing filters the list without auto-selecting, so you can narrow down and
  pick visually.

- **`LaunchAgent.swift`** — writes/removes a user LaunchAgent at
  `~/Library/LaunchAgents/com.caffeinator.menubar.plist` (with `RunAtLoad`)
  and best-effort registers it with `launchd` for the current session.

### What "keep awake" really does

Each menu toggle maps to a `caffeinate` flag. If you turn everything off,
Caffeinator still falls back to keeping the screen awake (`-d`).

| Menu toggle | Flag | What the flag does | Default |
| --- | --- | --- | --- |
| The screen | `-d` | Prevent the display from sleeping | on |
| The system, even when idle | `-i` | Prevent the system from idle-sleeping | off |
| Storage (good for backups, downloads) | `-m` | Prevent the disk from idle-sleeping | off |
| Never sleep while plugged in | `-s` | Prevent system sleep — takes effect only on AC power | off |
| Turn off after… | `-t <seconds>` | Stop automatically after N seconds | — |
| Until an app or task finishes… | `-w <pid>` | Run until the chosen process exits | — |

A timer (`-t`) and a process wait (`-w`) are mutually exclusive — choosing one
clears the other.

---

## Project layout

```
Package.swift                      # SwiftPM manifest (executable target)
Makefile                           # build / bundle / install / uninstall
Resources/Info.plist               # LSUIElement=true, bundle metadata
Sources/Caffeinator/
  main.swift                       # app bootstrap + single-instance guard
  AppDelegate.swift                # status item, menu, state, settings
  CaffeinateController.swift       # caffeinate process lifecycle
  PowerMonitor.swift               # IOKit battery / power monitoring
  ProcessPickerWindowController.swift  # "wait for app/task" picker UI
  LaunchAgent.swift                # login-item plist install/uninstall
```

---

## Notes & troubleshooting

- **Quitting is safe.** Quitting Caffeinator stops the underlying
  `caffeinate` process — your Mac never gets stuck awake.
- **Only one copy runs.** If Caffeinator is already running, launching it again
  does nothing visible — the duplicate detects the first by bundle ID and exits
  silently, leaving the running instance untouched.
- **Login item permissions.** The first time you enable *Open when I log in*,
  macOS may show a prompt. Even if the live `launchctl` registration fails,
  the plist is written and takes effect at your next login.
- **Not notarized.** Caffeinator is ad-hoc signed and not sandboxed, so the
  smoothest path is to build it yourself or approve it once in Gatekeeper.
- **Full uninstall:** `make uninstall` (or delete `Caffeinator.app` and
  `~/Library/LaunchAgents/com.caffeinator.menubar.plist`).

---

## Requirements

- macOS 11 (Big Sur) or newer
- Xcode command-line tools with Swift 5.9+
- The system `caffeinate` tool (ships with macOS at `/usr/bin/caffeinate`)
