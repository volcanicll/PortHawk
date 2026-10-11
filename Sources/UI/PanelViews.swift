import SwiftUI

/// 面板根视图：纸面账簿。表头 → 页签/搜索 → 账目行 → 页脚；明细页从右滑入覆盖。
struct PanelView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderView()
                Hairline()
                ToolbarView()
                LedgerListView()
                Hairline()
                FooterView()
            }
            .background(Paper.bg)

            if state.showSettings {
                SettingsView()
                    .background(Paper.bg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if state.selectedEntry != nil {
                DetailView()
                    .background(Paper.bg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 400, height: 596)
        .background(Paper.bg)
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.22), value: state.selectedId)
        .animation(.easeOut(duration: 0.22), value: state.showSettings)
        .onAppear {
            state.start()
            state.markPanelOpened()
        }
    }
}

// MARK: - 表头

private struct HeaderView: View {
    @EnvironmentObject var state: AppState

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("PortHawk")
                .font(Paper.songti(19, .bold))
                .foregroundStyle(Paper.ink)
            // 印刷 marks：书名旁的一粒朱砂
            Rectangle()
                .fill(Paper.vermilion.opacity(0.85))
                .frame(width: 5, height: 5)
            Text("端口簿")
                .font(Paper.songti(11))
                .foregroundStyle(Paper.inkSoft)
            Spacer()
            if let updated = state.lastUpdated {
                Text("更新于 " + Self.timeFormatter.string(from: updated))
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
            }
            Button {
                state.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(Paper.body(12))
                    .foregroundStyle(Paper.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 页签 + 搜索

private struct ToolbarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                tab(for: mode)
            }
            onlyExposedChip
            Spacer()
            searchField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 「仅对外」快捷筛选：检查有哪些端口暴露给局域网
    private var onlyExposedChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { state.onlyExposed.toggle() }
        } label: {
            Text("仅对外")
                .font(Paper.body(11, state.onlyExposed ? .medium : .regular))
                .foregroundStyle(state.onlyExposed ? Paper.ochre : Paper.inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    state.onlyExposed ? Paper.ochre.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(state.onlyExposed ? Paper.ochre.opacity(0.5) : Paper.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("只显示对外监听的端口")
    }

    private func tab(for mode: ViewMode) -> some View {
        let selected = state.viewMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { state.viewMode = mode }
        } label: {
            VStack(spacing: 3) {
                Text(mode.rawValue)
                    .font(Paper.body(13, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Paper.ink : Paper.inkSoft)
                Rectangle()
                    .fill(selected ? Paper.blue : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(Paper.body(10))
                .foregroundStyle(Paper.inkSoft)
            // 离屏渲染无法渲染可编辑 TextField，用同版式的静态文本代替
            if state.isPreviewRender {
                Text("端口 / 进程 / 项目")
                    .font(Paper.body(12))
                    .foregroundStyle(Paper.inkSoft)
                    .frame(width: 118, alignment: .leading)
            } else {
                TextField("端口 / 进程 / 项目", text: $state.query)
                    .font(Paper.body(12))
                    .textFieldStyle(.plain)
                    .frame(width: 118)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Paper.bgDeep, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 账目主体

private struct LedgerListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            // 账目行最多几十条，VStack 足够，也保证离屏渲染可用
            VStack(spacing: 0) {
                if state.groups.isEmpty {
                    emptyState(allEmpty: state.entries.isEmpty && state.favorites.isEmpty)
                } else {
                    ForEach(state.groups, id: \.name) { group in
                        GroupSection(name: group.name, entries: group.entries)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: state.entries)
    }

    private func emptyState(allEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            SealMark(character: allEmpty ? "空" : "无", color: Paper.inkSoft)
                .frame(width: 22, height: 22)
                .font(Paper.songti(13, .bold))
            Text(allEmpty ? "当前没有任何端口监听" : "没有匹配的记录")
                .font(Paper.body(12))
                .foregroundStyle(Paper.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct GroupSection: View {
    @EnvironmentObject var state: AppState
    let name: String
    let entries: [PortEntry]

    private var isSystemGroup: Bool { name == AppState.systemGroupName }

    var body: some View {
        if isSystemGroup && !state.systemGroupExpanded {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { state.systemGroupExpanded = true }
            } label: {
                groupHeader(trailing: "\(entries.count) 个 · 点开")
            }
            .buttonStyle(.plain)
        } else {
            groupHeader(trailing: "\(entries.count) 个")
            ForEach(entries) { entry in
                LedgerRow(entry: entry)
            }
            if isSystemGroup && state.systemGroupExpanded {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { state.systemGroupExpanded = false }
                } label: {
                    HStack {
                        Spacer()
                        Text("收起系统端口")
                            .font(Paper.body(11))
                            .foregroundStyle(Paper.inkSoft)
                            .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 16)
                    .background(Paper.bgDeep.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupHeader(trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                if isSystemGroup {
                    Image(systemName: state.systemGroupExpanded ? "chevron.down" : "chevron.right")
                        .font(Paper.body(9, .semibold))
                        .foregroundStyle(Paper.inkSoft)
                }
                Text(name)
                    .font(Paper.songti(13, .bold))
                    .foregroundStyle(Paper.ink)
            }
            Spacer()
            Text(trailing)
                .font(Paper.mono(10))
                .foregroundStyle(Paper.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Paper.bgDeep)
    }
}

// MARK: - 单行账目

private struct LedgerRow: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry
    @State private var hovered = false

    private var isKilling: Bool { state.killingIds.contains(entry.id) }
    private var isNew: Bool { state.newIds.contains(entry.id) }
    private var isAlerted: Bool { state.alertPorts.contains(entry.port) }
    private var isPlaceholder: Bool { entry.pid == 0 }
    private var isPendingKill: Bool { state.pendingKillId == entry.id }

    var body: some View {
        HStack(spacing: 10) {
            // 左侧页码列：等宽大号端口号
            Text(String(entry.port))
                .font(Paper.mono(16, .semibold))
                .monospacedDigit()
                .foregroundStyle(isKilling ? Paper.inkSoft : Paper.ink)
                .frame(width: 56, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let brand = DevBrand.match(processName: entry.processName) {
                        // 品牌墨点：借 Pulse 的 dev-tool 品牌识别，落在纸上是一粒彩墨
                        Circle()
                            .fill(brand.color)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Paper.ink.opacity(0.18), lineWidth: 0.5))
                            .help(brand.label)
                    }
                    Text(entry.processName)
                        .font(Paper.body(13, .medium))
                        .foregroundStyle(Paper.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let project = entry.project {
                        Text("「\(project)」")
                            .font(Paper.body(12))
                            .foregroundStyle(Paper.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if isAlerted {
                        SealMark(character: "占", color: Paper.vermilion)
                    } else if isNew {
                        SealMark(character: "新", color: Paper.blue)
                    }
                }
                Text(subtitle)
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.pid > 0 { scopeBadge }
            starButton
            if entry.pid > 0 {
                killButton
            } else {
                Color.clear.frame(width: 58)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hovered && entry.pid > 0 ? Paper.bgDeep : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if entry.pid > 0 { state.openDetail(entry) }
        }
        .overlay(alignment: .leading) { strikeLine }
        .help(helpText)
        .opacity(isPlaceholder ? 0.55 : (isKilling ? 0.55 : 1))
        .contextMenu {
            Button("复制端口号 \(entry.port)") {
                if state.copyToPasteboard(String(entry.port)) {
                    state.flash("已复制端口 \(entry.port)")
                }
            }
            if entry.pid > 0 {
                Button("复制 PID \(entry.pid)") {
                    if state.copyToPasteboard(String(entry.pid)) {
                        state.flash("已复制 PID \(entry.pid)")
                    }
                }
                Divider()
                Button("结束「\(entry.processName)」") {
                    state.requestKill(entry)
                }
                Button("强制结束（SIGKILL）", role: .destructive) {
                    state.requestKill(entry, force: true)
                }
            } else {
                Button("取消收藏") {
                    state.toggleFavorite(port: entry.port)
                }
            }
        }
    }

    /// 第二行：PID + 项目所在上级目录（确定性排版，不依赖动态截断），完整路径见悬停提示
    private var subtitle: String {
        guard entry.pid > 0 else { return "收藏的端口 · 当前空闲" }
        var parts = ["PID \(entry.pid)"]
        if let path = entry.projectPath {
            let components = path.split(separator: "/").map(String.init)
            if components.count >= 2 {
                parts.append("…/\(components[components.count - 2])")
            }
        } else {
            parts.append("系统进程")
        }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        guard entry.pid > 0 else { return "收藏的端口，当前没有进程占用" }
        var parts = ["\(entry.processName) (PID \(entry.pid))"]
        if let path = entry.projectPath { parts.append(path) }
        parts.append(entry.scopeText == "对外" ? "监听所有网卡，局域网可达" : "仅监听本机回环")
        return parts.joined(separator: "\n")
    }

    private var scopeBadge: some View {
        Text(entry.scopeText)
            .font(Paper.body(10, .medium))
            .foregroundStyle(entry.isLanExposed ? Paper.ochre : Paper.inkSoft)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                (entry.isLanExposed ? Paper.ochre : Paper.inkSoft).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 3)
            )
    }

    private var starButton: some View {
        Button {
            state.toggleFavorite(port: entry.port)
        } label: {
            Image(systemName: state.favorites.contains(entry.port) ? "star.fill" : "star")
                .font(Paper.body(12))
                .foregroundStyle(state.favorites.contains(entry.port) ? Paper.ochre : Paper.inkSoft.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收藏端口 \(entry.port)")
    }

    /// 结束按钮：悬停浮现；第一步变实心「确认结束」，2.5 秒内再点才真发信号。
    @ViewBuilder
    private var killButton: some View {
        ZStack {
            if isPendingKill {
                Button {
                    state.confirmPendingKill()
                } label: {
                    Text(state.pendingKillForce ? "确认强杀" : "确认结束")
                        .font(Paper.body(10, .semibold))
                        .foregroundStyle(Paper.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Paper.vermilion, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else if hovered || isKilling {
                Button {
                    state.requestKill(entry)
                } label: {
                    Text(isKilling ? "结束中" : "结束")
                        .font(Paper.body(11, .medium))
                        .foregroundStyle(Paper.vermilion)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("结束进程 \(entry.processName)")
            }
        }
        .frame(width: 58, alignment: .trailing)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: state.pendingKillId)
    }

    /// 红笔划账：结束进程时一道朱砂线从左划到右。
    @ViewBuilder
    private var strikeLine: some View {
        if isKilling {
            GeometryReader { geo in
                Rectangle()
                    .fill(Paper.vermilion)
                    .frame(width: geo.size.width - 32, height: 1.4)
                    .frame(maxHeight: .infinity)
            }
            .padding(.leading, 16)
            .transition(.opacity)
        }
    }
}

// MARK: - 设置页

private struct SettingsView: View {
    @EnvironmentObject var state: AppState

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    state.showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Paper.body(12, .semibold))
                        .foregroundStyle(Paper.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回账簿")
                Text("设置")
                    .font(Paper.songti(15, .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text("v" + version)
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("刷新") {
                        HStack(spacing: 8) {
                            ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { interval in
                                intervalChip(interval)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Hairline()
                    section("菜单栏") {
                        toggleRow(
                            "显示端口数",
                            subtitle: "书本图标旁显示当前端口总数",
                            isOn: Binding(get: { state.showMenuBarCount }, set: { state.showMenuBarCount = $0 })
                        )
                        toggleRow(
                            "登录时启动",
                            subtitle: "开机后自动常驻菜单栏",
                            isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
                        )
                    }
                    Hairline()
                    section("数据") {
                        Text("/usr/sbin/lsof · 仅监控 TCP 监听端口 · \(Int(state.refreshInterval)) 秒轮询")
                            .font(Paper.mono(10))
                            .foregroundStyle(Paper.inkSoft)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Paper.songti(12, .bold))
                .foregroundStyle(Paper.inkSoft)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intervalChip(_ interval: Double) -> some View {
        let selected = state.refreshInterval == interval
        return Button {
            state.refreshInterval = interval
        } label: {
            Text("\(Int(interval)) 秒")
                .font(Paper.body(12, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Paper.bg : Paper.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Paper.blue : Paper.bgDeep, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Paper.body(13))
                    .foregroundStyle(Paper.ink)
                Text(subtitle)
                    .font(Paper.body(10))
                    .foregroundStyle(Paper.inkSoft)
            }
            Spacer()
            // SwitchToggleStyle(tint:) 是 macOS 上给开关轨道着色的可靠 API，.tint 不生效
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Paper.blue))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - 明细页（借鉴 Pulse 的 inspector 钻取：整页从右滑入）

private struct DetailView: View {
    @EnvironmentObject var state: AppState
    @State private var armedKill = false
    @State private var armedForce = false
    /// 就地复制反馈："pid" / "port"；明细页盖住了主面板页脚，flash 看不见，反馈必须画在按钮上
    @State private var copiedField: String?
    @State private var copyFailed = false

    var body: some View {
        Group {
            if let entry = state.selectedEntry {
                content(entry)
                    .task(id: entry.id) {
                        armedKill = false
                        armedForce = false
                        copiedField = nil
                        copyFailed = false
                    }
                    .task(id: copiedField) {
                        guard copiedField != nil else { return }
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copiedField = nil
                        copyFailed = false
                    }
                    .task(id: armedKill) {
                        guard armedKill else { return }
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        armedKill = false
                    }
                    .task(id: armedForce) {
                        guard armedForce else { return }
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        armedForce = false
                    }
            } else {
                Color.clear
            }
        }
        .frame(width: 400, height: 596)
    }

    private func content(_ entry: PortEntry) -> some View {
        let detail = PortScanner.detail(for: entry.pid)
        let brand = DevBrand.match(processName: entry.processName)
        let subtitle = (brand.map { "\($0.label) · " } ?? "") + (entry.project ?? "系统进程")
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    state.closeDetail()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Paper.body(12, .semibold))
                        .foregroundStyle(Paper.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回账簿")
                Text("明细")
                    .font(Paper.songti(15, .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text("端口 " + String(entry.port))
                    .font(Paper.mono(11))
                    .foregroundStyle(Paper.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(brand?.color ?? Paper.inkSoft.opacity(0.5))
                            .frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(Paper.ink.opacity(0.18), lineWidth: 0.5))
                            .help(brand?.label ?? "未知应用")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.processName)
                                .font(Paper.body(15, .semibold))
                                .foregroundStyle(Paper.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(subtitle)
                                .font(Paper.body(11))
                                .foregroundStyle(Paper.blue)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(entry.scopeText)
                            .font(Paper.body(10, .medium))
                            .foregroundStyle(entry.isLanExposed ? Paper.ochre : Paper.inkSoft)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                (entry.isLanExposed ? Paper.ochre : Paper.inkSoft).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 3)
                            )
                    }
                    .padding(16)

                    Hairline()
                    section("进程") {
                        kv("PID", String(entry.pid))
                        kv("父进程", detail.parentPID.map(String.init) ?? "—")
                        kv("用户", detail.userName ?? "—")
                        kv("线程", detail.threadCount.map(String.init) ?? "—")
                        kv("内存", detail.residentBytes.map(Self.formatBytes) ?? "—")
                        kv("CPU 时间", detail.cpuSeconds.map(Self.formatSeconds) ?? "—")
                        kv("实时 CPU", state.detailCPU.map { String(format: "%.1f%%", $0) } ?? "采样中")
                        kv("可执行", detail.executablePath ?? "—", wraps: true)
                    }
                    Hairline()
                    section("项目") {
                        kv("所在目录", entry.projectPath ?? "系统进程，无项目目录", wraps: true)
                    }
                    Hairline()
                    section("命令") {
                        let line = detail.commandLine?.joined(separator: " ") ?? "—"
                        Text(line)
                            .font(Paper.mono(11))
                            .foregroundStyle(Paper.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }

            Hairline()
            HStack(spacing: 8) {
                actionButton(
                    armedKill ? "确认结束？" : "结束进程",
                    filled: true, armed: armedKill
                ) {
                    if armedKill {
                        state.kill(entry, force: false)
                        armedKill = false
                    } else {
                        armedKill = true
                        armedForce = false
                    }
                }
                actionButton(
                    armedForce ? "确认强杀？" : "强制结束",
                    filled: false, armed: armedForce
                ) {
                    if armedForce {
                        state.kill(entry, force: true)
                        armedForce = false
                    } else {
                        armedForce = true
                        armedKill = false
                    }
                }
                Spacer()
                quietButton(
                    copiedField == "pid" ? (copyFailed ? "✗ 失败" : "✓ 已复制") : "复制 PID",
                    confirmed: copiedField == "pid", failed: copiedField == "pid" && copyFailed
                ) {
                    copyField("pid", String(entry.pid))
                }
                quietButton(
                    copiedField == "port" ? (copyFailed ? "✗ 失败" : "✓ 已复制") : "复制端口",
                    confirmed: copiedField == "port", failed: copiedField == "port" && copyFailed
                ) {
                    copyField("port", String(entry.port))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Paper.songti(12, .bold))
                .foregroundStyle(Paper.inkSoft)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kv(_ label: String, _ value: String, wraps: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Paper.body(11))
                .foregroundStyle(Paper.inkSoft)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(Paper.mono(11))
                .foregroundStyle(Paper.ink)
                .textSelection(.enabled)
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func actionButton(_ title: String, filled: Bool, armed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Paper.body(11, .medium))
                .foregroundStyle(armed || filled ? Paper.bg : Paper.vermilion)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    armed || filled ? Paper.vermilion : Paper.vermilion.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Paper.vermilion.opacity(armed || filled ? 0 : 0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func copyField(_ key: String, _ text: String) {
        if state.copyToPasteboard(text) {
            copiedField = key
            copyFailed = false
        } else {
            copiedField = key
            copyFailed = true
        }
    }

    /// 中性操作（复制类）：淡墨字 + 横格线框，不占用朱砂的破坏性语义
    private func quietButton(_ title: String, confirmed: Bool = false, failed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Paper.body(11, .medium))
                .foregroundStyle(failed ? Paper.vermilion : (confirmed ? Paper.blue : Paper.inkSoft))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(failed ? Paper.vermilion.opacity(0.5) : (confirmed ? Paper.blue.opacity(0.5) : Paper.hairline), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        switch seconds {
        case ..<60: return String(format: "%.1f 秒", seconds)
        case ..<3600:
            let m = Int(seconds) / 60, s = Int(seconds) % 60
            return "\(m) 分 \(String(format: "%02d", s)) 秒"
        default:
            let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
            return "\(h) 小时 \(String(format: "%02d", m)) 分"
        }
    }
}

// MARK: - 页脚

private struct FooterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            if let notice = state.notice {
                // 通知占主槽位，保证「权限不足 + 复制命令」一行放得下
                Text(notice)
                    .font(Paper.body(10, .medium))
                    .foregroundStyle(Paper.vermilion)
                    .lineLimit(1)
                if let command = state.deniedKillCommand {
                    Button {
                        if state.copyToPasteboard(command) {
                            state.flash("已复制，去终端执行")
                        }
                    } label: {
                        Text("复制 sudo 命令")
                            .font(Paper.body(10, .medium))
                            .foregroundStyle(Paper.inkSoft)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Paper.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("共 \(state.entries.count) 端口 · \(state.projectCount) 项目")
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                if state.scanFailed {
                    Text("扫描失败 · 保留上一轮")
                        .font(Paper.body(10, .medium))
                        .foregroundStyle(Paper.vermilion)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(Int(state.refreshInterval))s")
                .font(Paper.mono(10))
                .foregroundStyle(Paper.inkSoft.opacity(0.8))
            Button {
                state.setPaused(!state.paused)
            } label: {
                Image(systemName: state.paused ? "arrow.clockwise" : "pause")
                    .font(Paper.body(11))
                    .foregroundStyle(state.paused ? Paper.vermilion : Paper.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.paused ? "恢复刷新" : "暂停刷新")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(Paper.body(11))
                    .foregroundStyle(Paper.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出端口簿")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Paper.bgDeep.opacity(0.6))
    }
}
