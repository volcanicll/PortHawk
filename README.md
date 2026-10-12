# PortHawk

> A port ledger living in your macOS menu bar: **which app owns which port, which project runs which port** — at a glance.

[![CI](https://github.com/volcanicll/PortHawk/actions/workflows/ci.yml/badge.svg)](https://github.com/volcanicll/PortHawk/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/volcanicll/PortHawk?color=A3321C&label=version)](https://github.com/volcanicll/PortHawk/releases/latest)
[![Site](https://img.shields.io/badge/landing-2D4B6F)](https://volcanicll.github.io/PortHawk/)

**Install**: visit the [landing page](https://volcanicll.github.io/PortHawk/), or run one command to install the latest build:

```bash
curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash
```

![Panel](verify/panel.png)

PortHawk is a native SwiftUI menu bar app (`MenuBarExtra`) — a single ~1 MB binary, no Electron, no runtime dependencies. It keeps a ledger of every TCP listening port on the machine: the port number sits in a left margin column like a page number, with process, project, PID and path on the right. Project ownership is inferred automatically from each process's working directory.

## Features

- **Ledger panel**: every TCP listening port in one ledger, hairline-ruled groups, serif titles, monospaced port numbers.
- **Two views**: "By project" groups ports under their owning project; "By port" lists favorites first, then everything else by port number.
- **Brand ink dots**: ~100 well-known dev-tool processes (node, python, redis-server, Code Helper…) get a brand-colored dot before their name.
- **Detail inspector**: click any row for a full page — complete command line, executable path, working directory, user, parent PID, threads, memory, cumulative and live CPU%; open the port in your browser, copy its PID or port number, or end / force-end (SIGKILL) right there.
- **Open in browser**: the row menu and the detail page hand the listener to your default browser. A wildcard bind (`0.0.0.0` / `*` / `[::]`) opens on `127.0.0.1`, since that always works; a listener bound to one specific interface address opens there instead. Ports 443/8443/9443 open over `https`, everything else over `http`. Favorite placeholder rows have no process, so there is nothing to open.
- **Two-step end**: hover a row for "end"; the first click arms a solid "Confirm", the second one within 2.5 s sends the signal. A row being ended gets struck through with a vermilion line, like ink cancelling a ledger entry.
- **Favorites & placeholders**: star ports you care about; idle favorites show a faint "not in use" placeholder row, so a dead service is obvious at a glance.
- **Occupancy alerts**: when a favorited port gets taken by a new process, the menu bar icon lights a dot and the row gets a vermilion "taken" seal; brand-new ports get a blue "new" seal.
- **Exposed / local badge**: any listener that is not bound to loopback is marked ochre "LAN" — that includes `0.0.0.0` / `*` / `[::]` and addresses bound to a specific interface such as `192.168.1.5`. Loopback-only listeners are gray "local". A "LAN only" chip filters your attack surface in one click.
- **Honest failures**: if lsof fails (including a 3 s timeout), the last snapshot is kept and the footer says so — it never pretends there are no ports.
- **Settings**: refresh interval (1/3/5/10 s), menu bar count toggle, launch at login (SMAppService).

## Screenshots

| Detail inspector | Settings |
| --- | --- |
| ![Detail](verify/detail.png) | ![Settings](verify/settings.png) |

## Build & Run

Requires macOS 13+ and Command Line Tools (full Xcode not needed). Release builds are Apple Silicon (arm64); `install.sh` stops with a clear message on Intel Macs rather than installing a binary that cannot run.

```bash
./build.sh
open build/PortHawk.app
```

`build.sh` pins `-target` to the advertised minimum macOS and fails the build if the resulting binary ends up requiring something newer. Without that pin, `swiftc` inherits the SDK's default deployment target, which tracks the toolchain — a newer CI runner silently raises the floor and the shipped app refuses to launch on the versions the README promises.

## Development & Diagnostics

```bash
# Data-layer self check, diffable against raw lsof output
./build/PortHawk.app/Contents/MacOS/PortHawk --cli

# Assertion suite for the parsing, exposure and alert rules (also run in CI)
./build/PortHawk.app/Contents/MacOS/PortHawk --selftest

# Send a kill signal to a port (verifies the kill flow)
./build/PortHawk.app/Contents/MacOS/PortHawk --cli --kill-port 3000

# Floating preview window (real data, real interaction)
./build/PortHawk.app/Contents/MacOS/PortHawk --preview

# Screenshot verification: real / mocked states / detail / settings / menu bar icon
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot verify/real.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock verify/mock.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock-detail verify/detail.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock-settings verify/settings.png
./build/PortHawk.app/Contents/MacOS/PortHawk --render-icon verify/icon.png 12 --alert

# Storyboard frames for the landing-page animation
./build/PortHawk.app/Contents/MacOS/PortHawk --render-frames /tmp/frames --scale 2
```

Mocked runs read and write a separate `controlport.verify` preferences suite, so screenshots never disturb your real favorites or view mode.

### The landing-page animation

`--render-frames` walks the panel through a scripted sequence of states — rows arriving, a favorite placeholder, the two-step end with its strike-through, an alert, the LAN filter, the detail drill-down, settings — and captures each frame with `ImageRenderer`. The frames are the real SwiftUI views, not mockups.

Alongside the PNGs it writes `manifest.json` recording which frame each scene starts on, so the site can seek the video to the segment matching the caption on screen instead of duplicating the timings by hand. Re-render and re-encode after UI changes:

```bash
./build/PortHawk.app/Contents/MacOS/PortHawk --render-frames /tmp/frames --scale 2
ffmpeg -y -framerate 24 -i /tmp/frames/%05d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 24 -preset slow \
  -g 12 -keyint_min 12 -sc_threshold 0 -movflags +faststart -an \
  site/assets/panel.mp4
cp /tmp/frames/00240.png site/assets/panel-poster.png
cp /tmp/frames/manifest.json site/assets/manifest.json
```

A few notes on why the encode looks the way it does: `-g 12` keeps keyframes dense so chapter seeking stays responsive (about 40 ms), `-crf 24` holds the whole 14 s clip near 1.4 MB, and `+faststart` moves the index to the front so playback can begin before the file finishes downloading. The `manifest.json` copy is what keeps the site's scene timings in step with the video.

The landing page loops: the overview plays the whole clip on repeat as an attract mode, and each feature scene replays its own segment with a short hold on the final frame, so the animation keeps demonstrating for as long as the scene is on screen. Switching scenes cancels the pending repeat, and the install scene leaves the video paused. Dwell times per scene live in `DWELL_MS` in `site/app.js`.

`ImageRenderer` cannot lay out a `ScrollView`'s content, which is why `AppState.flatList` exists: offscreen renders flatten the list, the detail page and the settings page into plain clipped stacks. It is never set in the running app.

### The app icon

`Tools/make-icon.swift` draws the icon and `Resources/AppIcon.icns` is built from its output. The artwork is designed in a 1024×1024 space and then scaled onto the body of Apple's macOS icon grid — an 824×824 rounded square centred in the 1024 canvas, leaving 100px of transparent margin on every side. Drawing edge to edge instead makes the icon read as oversized next to every other app in the Dock, which is exactly what the grid exists to prevent.

The generator measures its own output and exits non-zero if the body coverage drifts more than 1.5% from 80.5%, so a future tweak cannot silently reintroduce an oversized icon:

```bash
swift Tools/make-icon.swift /tmp/icon
# icon body covers 80.5% of the canvas (Apple grid expects ~80.5%)
```


## Release Flow (GitHub Actions)

- **`ci.yml`**: builds `./build.sh` on a clean macOS runner whenever `Sources/`, `Resources/` or `build.sh` change, or on PRs. It also runs `--selftest` and asserts that the binary's deployment target matches the advertised `LSMinimumSystemVersion`.
- **`release.yml`**: triggered by pushing a `v*` tag — injects the version from the tag into Info.plist → builds → runs the same self-test and deployment-target gates → produces DMG + zip → creates a GitHub Release with the artifacts.
- **`site-deploy.yml`**: deploys the landing page to GitHub Pages when `site/` changes. The page reads the latest version from the Releases API at runtime (falling back to `releases.atom`), so **shipping a new app version never requires redeploying the site**.

Everyday release: `git tag v0.x.0 && git push origin v0.x.0`.

## Data Sources & Limits

- Port list: `lsof -iTCP -sTCP:LISTEN -n -P -l +c0`, deduplicated by `(port, pid)` — IPv4/IPv6 dual-stack listeners count once. When one process listens on both a loopback and a wildcard address for the same port, the entry keeps the wider exposure rather than whichever row lsof printed first.
- Project inference: `proc_pidinfo(PROC_PIDVNODEPATHINFO)` reads each process's working directory; system paths (`/System`, `/usr`, `/private/var`, `/tmp`…) and the home directory itself are not treated as projects.
- Only **your own** processes are fully visible: other users' processes expose no cwd/executable path (detail fields show `—`), and ending them requires sudo.
- TCP listeners only; UDP and outbound connections are out of the ledger's scope.
- lsof escapes spaces in command names as `\x20` (e.g. `Google\x20Chrome`); PortHawk unescapes them and preserves any backslash sequence it does not recognize.

## Inspiration & Credits

**[Pulse](https://github.com/egoist/pulse)** (Go + WebView menu bar system monitor) — brand ink dots, the detail inspector, force-quit semantics and filter presets came from static analysis of its binary; its full-machine monitoring scope was deliberately left out.

**[PortBar](https://github.com/egoist/portbar)** (Swift menu bar port monitor) — favorite placeholder rows, keeping the last snapshot on scan failure, scan timeout, two-step kill confirmation, copyable sudo command, menu bar count badge, launch at login.

## Layout

```
Sources/
├── main.swift          Entry dispatch (menu bar app / CLI / self-test / screenshot & icon diagnostics)
├── Core/
│   ├── PortScanner.swift   lsof parsing, exposure classification, proc_pidinfo detail data, kill
│   ├── AppState.swift      Polling, snapshot diff, favorite alerts, grouping, detail sampling, pref migration
│   ├── AlertRules.swift    Pure snapshot-diff rules (kept free of UI and I/O for the self-test suite)
│   ├── SelfTest.swift      Assertion suite behind --selftest
│   └── DevBrand.swift      Process brand catalog (~100 dev tools)
└── UI/
    ├── PanelViews.swift    Ledger panel, detail inspector, settings
    └── Theme.swift         Paper visual tokens (paper, ink, blue, vermilion, ochre)
```

Preferences live in UserDefaults (domain `app.porthawk.PortHawk`); upgrading from an older bundle id (`local.controlport.app`, `app.portpeek.PortPeek`) migrates favorites and settings automatically.

## License

[MIT](LICENSE)
