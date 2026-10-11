import SwiftUI
import AppKit

// 入口分发：--cli 调试数据层，--render-preview 导出面板截图，--preview 开浮动预览窗，
// 无参数时作为菜单栏应用常驻。

let arguments = CommandLine.arguments

if arguments.contains("--cli") {
    CLI.run()
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
            print("icon rendered → \(arguments[idx + 1])")
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

// MARK: - 菜单栏应用

/// 菜单栏标签自绘成一张 template NSImage。
/// MenuBarExtra 对复合视图标签（HStack/overlay）的渲染不可靠——数字和圆点都会丢，
/// 单张位图是唯一稳定的画法；isTemplate 保证跟随系统浅色/深色菜单栏。
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
            // 告警圆点画进位图：菜单栏里 overlay 是渲染不出来的
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
        image.accessibilityDescription = "PortHawk，当前 \(count) 个监听端口"
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

// MARK: - CLI（数据层自检 / 远程调试用）

enum CLI {
    static func run() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--kill-port"), idx + 1 < args.count,
           let port = Int(args[idx + 1]) {
            killPort(port)
        }
        guard let entries = PortScanner.scan() else {
            print("lsof 扫描失败")
            exit(1)
        }
        printTable(entries.sorted { $0.port < $1.port })
        exit(0)
    }

    private static func killPort(_ port: Int) {
        guard let all = PortScanner.scan() else {
            print("lsof 扫描失败")
            return
        }
        let targets = all.filter { $0.port == port }
        guard !targets.isEmpty else {
            print("端口 \(port) 当前没有监听进程")
            return
        }
        for entry in targets {
            print("TERM  → pid=\(entry.pid) \(entry.processName)")
            _ = PortScanner.kill(pid: entry.pid, force: false)
        }
        Thread.sleep(forTimeInterval: 1.6)
        for entry in targets where PortScanner.isAlive(entry.pid) {
            print("KILL  → pid=\(entry.pid)（TERM 未退出）")
            _ = PortScanner.kill(pid: entry.pid, force: true)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    private static func printTable(_ entries: [PortEntry]) {
        print("PORT   SCOPE PID     PROCESS                 PROJECT")
        for e in entries {
            let port = pad(String(e.port), 7)
            let scope = pad(e.scopeText + (e.scopeText == "对外" ? " " : "  "), 6)
            let pid = pad(String(e.pid), 8)
            print("\(port)\(scope)\(pid)\(pad(e.processName, 24))\(e.project ?? "-")")
        }
        let projects = Set(entries.compactMap(\.project))
        print("\n共 \(entries.count) 个监听端口 · \(projects.count) 个项目")
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        var count = 0
        for ch in s {
            count += ch.unicodeScalars.first.map { $0.properties.isIdeographic || $0.value > 0x2E80 } == true ? 2 : 1
        }
        return s + String(repeating: " ", count: max(0, width - count))
    }
}

// MARK: - 视觉验证：模拟一版「有新占用、有告警、有划账」的账目状态

enum PreviewRenderer {
    /// 填充模拟账目；若真实扫描里有带项目归属的端口，用它顶替 mock 首行并返回其 id
    /// （落地页的明细截图需要真实命令行/内存数据，mock PID 是编不出来的）。
    @discardableResult
    @MainActor
    static func fillMock(_ state: AppState, portMode: Bool = false) -> String? {
        if portMode { state.viewMode = .port }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lab = home + "/workspace/lab/"
        let mock: [PortEntry] = [
            PortEntry(port: 3000, pid: 8123, processName: "node", isLanExposed: true,
                      project: "controlPort", projectPath: lab + "controlPort"),
            PortEntry(port: 5173, pid: 9021, processName: "node", isLanExposed: false,
                      project: "frontend-lab-website", projectPath: lab + "frontend-lab-website"),
            PortEntry(port: 8000, pid: 4555, processName: "python3", isLanExposed: false,
                      project: "ai-notes", projectPath: home + "/workspace/ai-notes"),
            PortEntry(port: 8080, pid: 3344, processName: "java", isLanExposed: true,
                      project: "gateway-service", projectPath: home + "/workspace/work/gateway-service"),
            PortEntry(port: 9229, pid: 8123, processName: "node", isLanExposed: false,
                      project: "controlPort", projectPath: lab + "controlPort"),
            PortEntry(port: 5432, pid: 778, processName: "postgres", isLanExposed: false,
                      project: nil, projectPath: nil),
            PortEntry(port: 6379, pid: 779, processName: "redis-server", isLanExposed: false,
                      project: nil, projectPath: nil),
            PortEntry(port: 49152, pid: 410, processName: "rapportd", isLanExposed: true,
                      project: nil, projectPath: nil),
        ]
        state.entries = mock
        // 4747 未被占用：验证「收藏占位行」
        state.favorites = [3000, 5173, 4747]
        // 9229 停在「确认结束」状态：验证两步按钮
        state.pendingKillId = "9229-8123"
        state.newIds = ["5173-9021", "8000-4555"]
        state.alertPorts = [5173]
        state.killingIds = ["8080-3344"]
        state.lastUpdated = Date()
        // 落地页的明细截图要有真实内容：用真实扫描中带项目归属的端口顶替首行
        var realId: String?
        if let real = PortScanner.scan()?.first(where: { $0.project != nil && $0.pid > 0 }) {
            state.entries[0] = real
            state.entries = state.entries.sorted { $0.port < $1.port }
            realId = real.id
        }
        return realId
    }

    @MainActor
    static func render(to path: String) {
        let state = AppState(preview: true)
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
        print("rendered → \(path)")
    }
}

// MARK: - 浮动预览窗（真实数据、真实交互，供人工检查与截图验证）

enum PreviewWindow {
    @MainActor
    static func run(screenshotAfter path: String? = nil, mock: Bool = false, portMode: Bool = false, openDetail: Bool = false, openSettings: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let state = AppState(
            preview: mock,
            // mock 用独立存储域，避免污染正式的视图模式/收藏偏好
            defaults: mock ? UserDefaults(suiteName: "controlport.verify")! : .standard
        )
        if mock {
            let realId = PreviewRenderer.fillMock(state, portMode: portMode)
            if openDetail {
                // 选中真实条目（fillMock 已用真实端口顶替首行）
                state.selectedId = realId ?? state.entries.first?.id
                state.detailCPU = 12.4
            }
            if openSettings {
                state.viewMode = .project  // 复现用户的场景：按项目视图下进出设置
                state.showSettings = true
                // 模拟「从设置返回」：在截图前先关掉设置页，复现返回后的列表状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                    state.showSettings = false
                }
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 596),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PortHawk · 预览"
        window.contentView = NSHostingView(rootView: PanelView().environmentObject(state))
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        app.activate()

        if let path {
            // 等两轮扫描完成后再截图，然后退出
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if let view = window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                        print("screenshot → \(path)")
                    }
                }
                app.terminate(nil)
            }
        }
        app.run()
    }
}
