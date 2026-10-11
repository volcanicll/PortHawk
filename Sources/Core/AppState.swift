import SwiftUI
import Combine
import ServiceManagement

enum ViewMode: String, CaseIterable {
    case project = "按项目"
    case port = "按端口"

    var persistedKey: String { "controlport.viewmode" }
}

/// 面板的数据中枢：3 秒轮询 lsof，对新旧快照做 diff，
/// 驱动「新占用」印章、收藏端口告警与菜单栏红点。
@MainActor
final class AppState: ObservableObject {
    @Published var entries: [PortEntry] = []
    @Published var viewMode: ViewMode {
        didSet { defaults.set(viewMode.rawValue, forKey: "controlport.viewmode") }
    }
    @Published var query = ""
    @Published var favorites: Set<Int> {
        didSet { defaults.set(Array(favorites), forKey: "controlport.favorites") }
    }
    @Published var systemGroupExpanded = false
    @Published var paused = false
    @Published var lastUpdated: Date?
    /// 结束信号已发出、等待进程退出的行，行上画红笔划线
    @Published var killingIds: Set<String> = []
    /// 本轮扫描新出现的记录，短暂显示「新」印章
    @Published var newIds: Set<String> = []
    /// 收藏端口从空闲变为被占的告警集合，驱动菜单栏圆点
    @Published var alertPorts: Set<Int> = []
    /// 页脚提示（如权限不足），几秒后自动消失
    @Published var notice: String?
    /// 明细页选中的账目行（借鉴 Pulse 的 inspector 钻取）
    @Published var selectedId: String?
    /// 明细页的实时 CPU%（两次轮询采样的差值）
    @Published var detailCPU: Double?
    /// 工具栏「仅对外」快捷筛选（借鉴 Pulse 的过滤预设）
    @Published var onlyExposed = false
    /// 最近一轮扫描失败（lsof 启动失败/超时）。此时保留旧数据，页脚提示。
    @Published var scanFailed = false
    /// 待二次确认的结束请求：行上先亮「确认结束」，再点一次才动手
    @Published var pendingKillId: String?
    @Published var pendingKillForce = false
    /// 权限不足时的可复制命令（借鉴 PortBar：给命令而不是只给提示）
    @Published var deniedKillCommand: String?
    /// 设置页可见性（齿轮入口，与明细页互斥）
    @Published var showSettings = false
    /// 刷新间隔（秒），设置页可调
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "controlport.interval")
            if !paused { restartTimer() }
        }
    }
    /// 菜单栏是否显示端口数
    @Published var showMenuBarCount: Bool {
        didSet { defaults.set(showMenuBarCount, forKey: "controlport.menu.count") }
    }
    /// 登录自启（SMAppService），通过 setLaunchAtLogin 变更
    @Published private(set) var launchAtLogin: Bool

    static let systemGroupName = "系统与其他"
    /// 供离屏渲染识别：渲染态不显示可编辑控件、不跑定时器
    let isPreviewRender: Bool
    private let defaults: UserDefaults
    private var previousIds: Set<String> = []
    private var favoriteBusy: [Int: Bool] = [:]
    private var timer: Timer?
    private var noticeTask: Task<Void, Never>?
    private var lastCPUSample: (seconds: Double, at: Date)?
    private var pendingKillResetTask: Task<Void, Never>?

    init(preview: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPreviewRender = preview
        if defaults === UserDefaults.standard {
            Self.migrateLegacyPreferences(into: defaults)
        }
        self.viewMode = ViewMode(rawValue: defaults.string(forKey: "controlport.viewmode") ?? "") ?? .project
        self.refreshInterval = defaults.object(forKey: "controlport.interval") as? Double ?? 3
        self.showMenuBarCount = defaults.object(forKey: "controlport.menu.count") as? Bool ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let saved = defaults.array(forKey: "controlport.favorites") as? [Int] {
            self.favorites = Set(saved)
        } else {
            self.favorites = []
        }
        // 启动即扫描并常驻定时器：菜单栏徽标要在用户第一次点开面板之前就有数字
        if !preview {
            refreshOnce()
            restartTimer()
        }
    }

    /// 项目历经 controlPort → PortPeek → PortHawk 改名，bundle id 随之变更；
    /// 首次以新身份启动时按顺序找旧域的偏好搬过来，只补缺失键，幂等。
    private static func migrateLegacyPreferences(into defaults: UserDefaults) {
        let legacyDomains = ["local.controlport.app", "app.portpeek.PortPeek"]
        let keys = ["controlport.viewmode", "controlport.favorites", "controlport.interval", "controlport.menu.count"]
        for domain in legacyDomains {
            guard let legacy = UserDefaults(suiteName: domain) else { continue }
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
    }

    func start() {
        guard !isPreviewRender else { return }
        restartTimer()
        refreshOnce()
    }

    func setPaused(_ value: Bool) {
        paused = value
        if paused {
            timer?.invalidate()
            timer = nil
        } else {
            refreshOnce()
            restartTimer()
        }
    }

    func refreshOnce() {
        guard !isPreviewRender else { return }
        Task.detached(priority: .userInitiated) {
            let fresh = PortScanner.scan()
            await self.apply(fresh)
        }
    }

    /// 面板打开时调用：清掉红点，立刻刷一轮。
    func markPanelOpened() {
        guard !isPreviewRender else { return }
        alertPorts = []
        refreshOnce()
    }

    func toggleFavorite(port: Int) {
        if favorites.contains(port) {
            favorites.remove(port)
            alertPorts.remove(port)
        } else {
            favorites.insert(port)
        }
    }

    func kill(_ entry: PortEntry) {
        kill(entry, force: false)
    }

    /// 第一步：在行上亮起「确认结束」，2.5 秒内不确认就自动收回。
    func requestKill(_ entry: PortEntry, force: Bool = false) {
        guard !killingIds.contains(entry.id) else { return }
        pendingKillResetTask?.cancel()
        pendingKillId = entry.id
        pendingKillForce = force
        pendingKillResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingKillId = nil
            self?.pendingKillForce = false
        }
    }

    /// 第二步：真发送信号。
    func confirmPendingKill() {
        guard let id = pendingKillId,
              let entry = entries.first(where: { $0.id == id }) else {
            pendingKillId = nil
            return
        }
        pendingKillResetTask?.cancel()
        pendingKillId = nil
        kill(entry, force: pendingKillForce)
        pendingKillForce = false
    }

    func kill(_ entry: PortEntry, force: Bool) {
        guard !killingIds.contains(entry.id) else { return }
        killingIds.insert(entry.id)
        if selectedId == entry.id { closeDetail() }
        let pid = entry.pid
        let command = force ? "sudo kill -9 \(pid)" : "sudo kill \(pid)"
        Task.detached(priority: .userInitiated) {
            let sent = PortScanner.kill(pid: pid, force: force)
            if !sent {
                await MainActor.run {
                    self.showNotice("权限不足，无法结束 PID \(pid)")
                    self.deniedKillCommand = command
                }
            }
            if !force {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                // TERM 没退掉就补 KILL
                if sent, PortScanner.isAlive(pid) {
                    _ = PortScanner.kill(pid: pid, force: true)
                }
            }
            await MainActor.run {
                self.killingIds.remove(entry.id)
                self.refreshOnce()
            }
        }
    }

    // MARK: - 明细钻取

    var selectedEntry: PortEntry? {
        selectedId.flatMap { id in entries.first { $0.id == id } }
    }

    func openDetail(_ entry: PortEntry) {
        selectedId = entry.id
        detailCPU = nil
        lastCPUSample = nil
        sampleDetailCPU()
    }

    func closeDetail() {
        selectedId = nil
        detailCPU = nil
        lastCPUSample = nil
    }

    /// 累计 CPU 时间的两次采样差 → CPU%。第一次采样只记录基准。
    private func sampleDetailCPU() {
        guard let selected = selectedEntry,
              let now = PortScanner.cpuSecondsSnapshot(for: selected.pid) else {
            detailCPU = nil
            return
        }
        if let last = lastCPUSample {
            let wall = Date().timeIntervalSince(last.at)
            if wall > 0.3 {
                detailCPU = max(0, (now - last.seconds) / wall * 100)
            }
        }
        lastCPUSample = (now, Date())
    }

    func flash(_ text: String) {
        showNotice(text)
    }

    // MARK: - 快照 diff 与派生数据

    /// 快照落账。fresh 为 nil 表示扫描失败：保留上一轮数据，只翻失败旗标。
    private func apply(_ fresh: [PortEntry]?) {
        guard let fresh else {
            scanFailed = true
            return
        }
        scanFailed = false
        let ids = Set(fresh.map(\.id))
        if !previousIds.isEmpty {
            let added = ids.subtracting(previousIds)
            newIds.formUnion(added)
            if !added.isEmpty {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self?.newIds.subtract(added)
                }
            }
        }

        var busyNow: [Int: Bool] = [:]
        for entry in fresh where favorites.contains(entry.port) {
            busyNow[entry.port] = true
        }
        for (port, wasBusy) in favoriteBusy where favorites.contains(port) {
            if busyNow[port] == true, !wasBusy {
                alertPorts.insert(port)
            }
        }
        favoriteBusy = busyNow

        previousIds = ids
        killingIds = killingIds.intersection(ids)
        entries = fresh.sorted {
            $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid
        }
        lastUpdated = Date()
        if selectedId != nil { sampleDetailCPU() }
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
            self?.deniedKillCommand = nil
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshOnce() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 打开设置页（与明细页互斥）
    func openSettings() {
        selectedId = nil
        showSettings = true
    }

    /// 登录自启开关。SMAppService 注册失败时回读真实状态，不让开关说谎。
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showNotice("开机自启设置失败：\(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var projectCount: Int {
        Set(entries.compactMap(\.project)).count
    }

    var filtered: [PortEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { !onlyExposed || $0.isLanExposed }
            .filter {
                q.isEmpty
                    || String($0.port).contains(q)
                    || String($0.pid).contains(q)
                    || $0.processName.localizedCaseInsensitiveContains(q)
                    || ($0.project?.localizedCaseInsensitiveContains(q) ?? false)
            }
    }

    /// 账簿的分组行。收藏组永远置顶：占用的真实行 + 未占用端口的淡墨占位行；
    /// 项目视图其后按项目分组（收藏的端口不再重复出现），「系统与其他」垫底；
    /// 端口视图其后是「全部端口」。
    var groups: [(name: String, entries: [PortEntry])] {
        let visible = filtered
        let q = query.trimmingCharacters(in: .whitespaces)

        // 占位行只看「端口是否真的被占」和「是否匹配搜索」，不受 仅对外 影响
        let occupiedPorts = Set(entries.map(\.port))
        let placeholders: [PortEntry] = favorites
            .filter { !occupiedPorts.contains($0) }
            .filter { q.isEmpty || String($0).contains(q) }
            .sorted()
            .map {
                PortEntry(port: $0, pid: 0, processName: "未占用",
                          isLanExposed: false, project: nil, projectPath: nil)
            }
        let favoriteGroup = (visible.filter { favorites.contains($0.port) } + placeholders)
            .sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }

        var result: [(String, [PortEntry])] = []
        if !favoriteGroup.isEmpty {
            result.append(("收藏", favoriteGroup))
        }

        let unmarked = visible.filter { !favorites.contains($0.port) }
        if viewMode == .port {
            result.append(("全部端口", unmarked))
            return result
        }
        let byProject = Dictionary(grouping: unmarked) {
            $0.project ?? AppState.systemGroupName
        }
        result += byProject
            .map { (name: $0.key, entries: $0.value) }
            .sorted { a, b in
                if a.name == AppState.systemGroupName { return false }
                if b.name == AppState.systemGroupName { return true }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        return result
    }
}
