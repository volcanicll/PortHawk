import SwiftUI
import AppKit

// Entry dispatch: --cli for the data layer, --selftest for the assertion suite,
// --render-preview to export a panel image, --preview for a floating window,
// and the menu bar app when launched with no arguments.

let arguments = CommandLine.arguments

if arguments.contains("--cli") {
    CLI.run()
} else if arguments.contains("--selftest") {
    SelfTest.run()
} else if let idx = arguments.firstIndex(of: "--render-frames"), idx + 1 < arguments.count {
    let dir = arguments[idx + 1]
    let scale = arguments.firstIndex(of: "--scale").flatMap { i in
        i + 1 < arguments.count ? Double(arguments[i + 1]) : nil
    } ?? 2
    MainActor.assumeIsolated {
        FrameRenderer.render(to: dir, scale: CGFloat(scale))
    }
    exit(0)
} else if let idx = arguments.firstIndex(of: "--render-preview"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewRenderer.render(to: arguments[idx + 1])
    }
    exit(0)
} else if let idx = arguments.firstIndex(of: "--screenshot"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewWindow.run(screenshotAfter: arguments[idx + 1])
    }
} else if let idx = arguments.firstIndex(of: "--screenshot-mock"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewWindow.run(screenshotAfter: arguments[idx + 1], mock: true)
    }
} else if let idx = arguments.firstIndex(of: "--screenshot-mock-port"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewWindow.run(screenshotAfter: arguments[idx + 1], mock: true, portMode: true)
    }
} else if let idx = arguments.firstIndex(of: "--screenshot-mock-detail"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewWindow.run(screenshotAfter: arguments[idx + 1], mock: true, openDetail: true)
    }
} else if let idx = arguments.firstIndex(of: "--screenshot-mock-settings"), idx + 1 < arguments.count {
    MainActor.assumeIsolated {
        PreviewWindow.run(screenshotAfter: arguments[idx + 1], mock: true, openSettings: true)
    }
} else if let idx = arguments.firstIndex(of: "--render-icon"), idx + 1 < arguments.count {
    let count = idx + 2 < arguments.count ? (Int(arguments[idx + 2]) ?? 0) : 0
    let alert = arguments.contains("--alert")
    MainActor.assumeIsolated {
        let icon = MenuBarIconRenderer.image(count: count, alert: alert, showCount: true)
        let scale: CGFloat = 4
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(icon.size.width * scale), pixelsHigh: Int(icon.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        ctx?.cgContext.setFillColor(NSColor.white.cgColor)
        ctx?.cgContext.fill(NSRect(origin: .zero, size: rep.size))
        ctx?.cgContext.scaleBy(x: scale, y: scale)
        icon.draw(in: NSRect(origin: .zero, size: icon.size))
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: arguments[idx + 1]))
            print("icon rendered -> \(arguments[idx + 1])")
        }
    }
    exit(0)
} else if arguments.contains("--preview") {
    MainActor.assumeIsolated {
        PreviewWindow.run()
    }
} else {
    ControlPortApp.main()
}

// MARK: - Menu bar app

/// The menu bar label is drawn into a single template NSImage.
/// MenuBarExtra renders composite labels (HStack/overlay) unreliably — the count
/// and the dot both get dropped — so a bitmap is the only stable approach;
/// isTemplate keeps it in step with the light/dark menu bar.
enum MenuBarIconRenderer {
    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]

    static func image(count: Int, alert: Bool, showCount: Bool) -> NSImage {
        let key = "\(count)|\(alert)|\(showCount)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let image = draw(count: count, alert: alert, showCount: showCount)
        cache[key] = image
        return image
    }

    private static func draw(count: Int, alert: Bool, showCount: Bool) -> NSImage {
        let symbolName = alert ? "book.closed.fill" : "book.closed"
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))!
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let text = String(count) as NSString
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = text.size(withAttributes: textAttributes)
        let symbolSize = symbol.size

        let height: CGFloat = 18
        let width = ceil(symbolSize.width + (showCount ? textSize.width + 3 : 0))
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let symbolY = (height - symbolSize.height) / 2
            symbol.draw(in: NSRect(x: 0, y: symbolY, width: symbolSize.width, height: symbolSize.height))
            // The alert dot goes into the bitmap: overlays do not render in the
            // menu bar.
            if alert {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: symbolSize.width - 3, y: height - 5.5, width: 4, height: 4)).fill()
            }
            if showCount {
                text.draw(
                    at: NSPoint(x: symbolSize.width + 3, y: (height - textSize.height) / 2),
                    withAttributes: textAttributes
                )
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PortHawk, \(count) listening ports"
        return image
    }
}

struct ControlPortApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(state)
        } label: {
            Image(nsImage: MenuBarIconRenderer.image(
                count: state.entries.count,
                alert: !state.alertPorts.isEmpty,
                showCount: state.showMenuBarCount
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - CLI (data-layer self check / remote debugging)

enum CLI {
    static func run() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--kill-port"), idx + 1 < args.count,
           let port = Int(args[idx + 1]) {
            killPort(port)
        }
        guard let entries = PortScanner.scan() else {
            print("lsof scan failed")
            exit(1)
        }
        printTable(entries.sorted { $0.port < $1.port })
        exit(0)
    }

    private static func killPort(_ port: Int) {
        guard let all = PortScanner.scan() else {
            print("lsof scan failed")
            return
        }
        let targets = all.filter { $0.port == port }
        guard !targets.isEmpty else {
            print("nothing is listening on port \(port)")
            return
        }
        for entry in targets {
            print("TERM  -> pid=\(entry.pid) \(entry.processName)")
            _ = PortScanner.kill(pid: entry.pid, force: false)
        }
        Thread.sleep(forTimeInterval: 1.6)
        for entry in targets where PortScanner.isAlive(entry.pid) {
            print("KILL  -> pid=\(entry.pid) (TERM did not take)")
            _ = PortScanner.kill(pid: entry.pid, force: true)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    private static func printTable(_ entries: [PortEntry]) {
        print("PORT   SCOPE PID     PROCESS                 PROJECT")
        for e in entries {
            let port = pad(String(e.port), 7)
            let scope = pad(e.scopeText, 6)
            let pid = pad(String(e.pid), 8)
            print("\(port)\(scope)\(pid)\(pad(e.processName, 24))\(e.project ?? "-")")
        }
        let projects = Set(entries.compactMap(\.project))
        print("\n\(entries.count) listening ports · \(projects.count) projects")
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - s.count))
    }
}

// MARK: - Visual verification fixtures

enum PreviewRenderer {
    /// Fill the panel with a mock ledger: new ports, an alert, a struck-through
    /// row, a favorite placeholder and an armed kill button.
    ///
    /// The mock PIDs do not exist, so `PortScanner.detail` returns nil for every
    /// field and the detail page would render as a column of dashes. When the
    /// real scan finds a listening process that belongs to a project, it is
    /// swapped in so the detail screenshot shows genuine command-line, memory
    /// and thread data; any mock entry sharing that port is dropped first so the
    /// ledger never shows the same port twice.
    @discardableResult
    @MainActor
    static func fillMock(_ state: AppState, portMode: Bool = false) -> String? {
        if portMode { state.viewMode = .port }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lab = home + "/workspace/"
        var mock: [PortEntry] = [
            PortEntry(port: 3000, pid: 8123, processName: "node", host: "0.0.0.0",
                      project: "PortHawk", projectPath: lab + "PortHawk"),
            PortEntry(port: 5173, pid: 9021, processName: "node", host: "127.0.0.1",
                      project: "frontend-lab-website", projectPath: lab + "frontend-lab-website"),
            PortEntry(port: 8000, pid: 4555, processName: "python3", host: "127.0.0.1",
                      project: "ai-notes", projectPath: home + "/workspace/ai-notes"),
            PortEntry(port: 8080, pid: 3344, processName: "java", host: "0.0.0.0",
                      project: "gateway-service", projectPath: home + "/workspace/work/gateway-service"),
            PortEntry(port: 9229, pid: 8123, processName: "node", host: "127.0.0.1",
                      project: "PortHawk", projectPath: lab + "PortHawk"),
            PortEntry(port: 5432, pid: 778, processName: "postgres", host: "127.0.0.1",
                      project: nil, projectPath: nil),
            PortEntry(port: 6379, pid: 779, processName: "redis-server", host: "127.0.0.1",
                      project: nil, projectPath: nil),
            PortEntry(port: 49152, pid: 410, processName: "rapportd", host: "0.0.0.0",
                      project: nil, projectPath: nil),
        ]
        var realId: String?
        if let real = PortScanner.scan()?.first(where: { $0.project != nil && $0.pid > 0 }) {
            mock.removeAll { $0.port == real.port }
            mock.append(real)
            realId = real.id
        }
        state.entries = mock.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
        // 4747 is free: demonstrates the favorite placeholder row.
        state.favorites = [3000, 5173, 4747]
        // 9229 is armed: demonstrates the two-step button.
        state.pendingKillId = "9229-8123"
        state.newIds = ["5173-9021", "8000-4555"]
        state.alertPorts = [5173]
        state.killingIds = ["8080-3344"]
        state.lastUpdated = Date()
        return realId
    }

    /// Entries used by the landing-page animation, ordered the way they should
    /// arrive on screen.
    @MainActor
    static func animationEntries() -> [PortEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lab = home + "/workspace/"
        return [
            PortEntry(port: 3000, pid: 8123, processName: "node", host: "0.0.0.0",
                      project: "PortHawk", projectPath: lab + "PortHawk"),
            PortEntry(port: 5173, pid: 9021, processName: "node", host: "127.0.0.1",
                      project: "frontend-lab-website", projectPath: lab + "frontend-lab-website"),
            PortEntry(port: 8000, pid: 4555, processName: "python3", host: "127.0.0.1",
                      project: "ai-notes", projectPath: home + "/workspace/ai-notes"),
            PortEntry(port: 8080, pid: 3344, processName: "java", host: "0.0.0.0",
                      project: "gateway-service", projectPath: home + "/workspace/work/gateway-service"),
            PortEntry(port: 9229, pid: 8123, processName: "node", host: "127.0.0.1",
                      project: "PortHawk", projectPath: lab + "PortHawk"),
            PortEntry(port: 5432, pid: 778, processName: "postgres", host: "127.0.0.1",
                      project: nil, projectPath: nil),
            PortEntry(port: 6379, pid: 779, processName: "redis-server", host: "127.0.0.1",
                      project: nil, projectPath: nil),
        ]
    }

    /// Plausible detail-page values for the animation: the mock PIDs are not
    /// real processes, so the fields are supplied instead of introspected.
    static func animationDetail() -> PortScanner.ProcessDetail {
        PortScanner.ProcessDetail(
            commandLine: ["/usr/local/bin/node", "--enable-source-maps", "server.js"],
            userName: NSUserName(),
            parentPID: 1,
            residentBytes: 118 * 1_048_576,
            threadCount: 11,
            cpuSeconds: 42.6,
            executablePath: "/usr/local/bin/node"
        )
    }

    @MainActor
    static func render(to path: String) {
        let state = AppState(preview: true, flatList: true)
        fillMock(state)
        let renderer = ImageRenderer(content: PanelView().environmentObject(state))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered -> \(path)")
    }
}

// MARK: - Frame renderer: storyboard frames for the landing-page animation

/// Renders the panel through a scripted sequence of states so the landing page
/// can play the real UI as video. Each frame mutates `AppState` and is captured
/// with ImageRenderer, which draws the actual SwiftUI views — no mockups, no
/// hand-drawn assets. Frames are written as PNGs and encoded outside the app.
enum FrameRenderer {
    /// 24 fps; scene lengths below are expressed in seconds.
    static let fps = 24

    @MainActor
    static func render(to directory: String, scale: CGFloat = 2) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // ImageRenderer draws synchronously, which a frame-by-frame storyboard
        // needs; it cannot lay out a ScrollView, so the list is flattened via
        // flatList.
        let state = AppState(preview: true, flatList: true)
        let view = PanelView().environmentObject(state)

        var frameIndex = 0
        /// Scene start frames, keyed by a stable name. Written alongside the
        /// frames so the landing page can seek the video to the segment that
        /// matches the text it is showing, without hard-coding timings.
        var scenes: [(name: String, startFrame: Int)] = []

        func markScene(_ name: String) {
            scenes.append((name, frameIndex))
        }

        func capture() {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let name = String(format: "%05d.png", frameIndex)
            try? png.write(to: URL(fileURLWithPath: directory + "/" + name))
            frameIndex += 1
        }

        /// Render `count` frames, interpolating 0...1 and handing each step to
        /// `apply`.
        func animate(seconds: Double, apply: (Double) -> Void) {
            let count = max(1, Int((seconds * Double(fps)).rounded()))
            for i in 0..<count {
                let t = count == 1 ? 1 : Double(i) / Double(count - 1)
                apply(t)
                capture()
            }
        }

        func hold(seconds: Double) {
            let count = max(1, Int((seconds * Double(fps)).rounded()))
            for _ in 0..<count { capture() }
        }

        // --- Scene 1: empty ledger, rows arrive one by one -------------------
        state.viewMode = .project
        state.entries = []
        state.favorites = []
        state.collapsedGroups = []
        state.lastUpdated = Date()
        markScene("empty")
        hold(seconds: 0.6)

        let story: [PortEntry] = PreviewRenderer.animationEntries()
        markScene("arrive")
        state.rowAppearProgress = [:]
        for (i, entry) in story.enumerated() {
            let id = entry.id
            // Add the row first, then fade it in from slightly below. Adding it
            // afterwards would leave nothing on screen to animate.
            state.entries = Array(story.prefix(i + 1))
            state.rowAppearProgress?[id] = 0
            animate(seconds: 0.22) { t in
                state.rowAppearProgress?[id] = t
            }
            // Pause a beat so the arrival is readable.
            hold(seconds: 0.1)
        }
        state.rowAppearProgress = nil
        hold(seconds: 0.7)

        // --- Scene 2: favorite an idle port -> placeholder row ----------------
        markScene("favorite")
        // 4747 is deliberately not listening, so favoriting it demonstrates the
        // faint "not in use" placeholder and sets up the alert in scene 4.
        let favoritePort = 4747
        let favoriteRow = PortEntry(port: favoritePort, pid: 0, processName: "not in use",
                                    host: "127.0.0.1", project: nil, projectPath: nil)
        if let first = story.first {
            state.forcedHoverId = first.id
            hold(seconds: 0.3)
            state.forcedHoverId = nil
        }
        state.favorites = [favoritePort]
        state.rowAppearProgress = [favoriteRow.id: 0]
        animate(seconds: 0.25) { t in state.rowAppearProgress?[favoriteRow.id] = t }
        state.rowAppearProgress = nil
        hold(seconds: 0.6)

        // --- Scene 3: hover reveals the row actions, then two-step confirm ----
        markScene("end")
        let killTarget = story.first { $0.port == 8080 } ?? story[story.count / 2]
        state.forcedHoverId = killTarget.id
        hold(seconds: 0.7)
        state.pendingKillId = killTarget.id
        hold(seconds: 0.5)
        // Confirmed: the row is struck through left to right.
        state.pendingKillId = nil
        state.killingIds = [killTarget.id]
        state.strikeProgress = 0
        animate(seconds: 0.35) { t in state.strikeProgress = t }
        hold(seconds: 0.35)
        // The process is gone; the row disappears.
        state.killingIds = []
        state.entries = state.entries.filter { $0.id != killTarget.id }
        state.strikeProgress = 1
        state.forcedHoverId = nil
        hold(seconds: 0.5)

        // --- Scene 4: the favorited port gets taken over -> seal + menu dot ---
        markScene("alert")
        let taker = PortEntry(port: favoritePort, pid: 6612, processName: "node",
                              host: "0.0.0.0", project: "frontend-lab-website",
                              projectPath: FileManager.default.homeDirectoryForCurrentUser.path + "/workspace/frontend-lab-website")
        state.entries.append(taker)
        state.newIds = [taker.id]
        state.alertPorts = [favoritePort]
        hold(seconds: 1.3)

        // --- Scene 5: the LAN-only filter ------------------------------------
        markScene("filter")
        state.newIds = []
        state.onlyExposed = true
        hold(seconds: 1.0)
        state.onlyExposed = false
        state.alertPorts = []
        hold(seconds: 0.4)

        // --- Scene 6: drill into the detail page -----------------------------
        markScene("detail")
        let detailTarget = story.first { $0.port == 3000 } ?? story[0]
        state.detailOverride = PreviewRenderer.animationDetail()
        state.selectedId = detailTarget.id
        state.detailProgress = 0
        animate(seconds: 0.5) { t in state.detailProgress = t }
        hold(seconds: 1.5)
        state.detailProgress = 1

        // --- Scene 7: back to the ledger, then the settings page -------------
        markScene("settings")
        state.selectedId = nil
        state.detailOverride = nil
        hold(seconds: 0.5)
        state.showSettings = true
        hold(seconds: 1.4)
        state.showSettings = false
        hold(seconds: 0.6)

        // Emit the scene map so the landing page can drive its own scroll
        // position from real timings instead of duplicating them by hand.
        let manifest: [String: Any] = [
            "fps": fps,
            "frameCount": frameIndex,
            "duration": Double(frameIndex) / Double(fps),
            "width": Int(400 * scale),
            "height": Int(596 * scale),
            "scenes": scenes.map { ["name": $0.name, "frame": $0.startFrame] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: directory + "/manifest.json"))
        }

        print("rendered \(frameIndex) frames -> \(directory) @ \(fps)fps")
        print("scenes: " + scenes.map { "\($0.name)@\($0.startFrame)" }.joined(separator: " "))
    }
}

// MARK: - Floating preview window (real data, real interaction)

enum PreviewWindow {
    @MainActor
    static func run(screenshotAfter path: String? = nil, mock: Bool = false, portMode: Bool = false, openDetail: Bool = false, openSettings: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // Mocked runs use the scratch suite so they never pollute real prefs.
        let state = AppState(preview: mock)
        if mock {
            let realId = PreviewRenderer.fillMock(state, portMode: portMode)
            if openDetail {
                state.selectedId = realId ?? state.entries.first?.id
                state.detailCPU = 12.4
            }
            if openSettings {
                state.viewMode = .project
                state.showSettings = true
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 596),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PortHawk · Preview"
        window.contentView = NSHostingView(rootView: PanelView().environmentObject(state))
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        // NSApplication.activate() is macOS 14+; fall back on macOS 13.
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }

        if let path {
            // Wait for two scan rounds before capturing, then quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if let view = window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                        print("screenshot -> \(path)")
                    }
                }
                app.terminate(nil)
            }
        }
        app.run()
    }
}
