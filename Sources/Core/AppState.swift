import SwiftUI
import Combine
import ServiceManagement

enum ViewMode: String, CaseIterable {
    case project = "By project"
    case port = "By port"
}

/// Panel data hub: polls lsof on an interval, diffs consecutive snapshots and
/// drives the "new" seals, favorite-port alerts and the menu bar dot.
@MainActor
final class AppState: ObservableObject {
    @Published var entries: [PortEntry] = [] {
        didSet { invalidateDerived() }
    }
    @Published var viewMode: ViewMode {
        didSet {
            defaults.set(viewMode.rawValue, forKey: "controlport.viewmode")
            invalidateDerived()
        }
    }
    @Published var query = "" {
        didSet { invalidateDerived() }
    }
    @Published var favorites: Set<Int> {
        didSet {
            defaults.set(Array(favorites), forKey: "controlport.favorites")
            invalidateDerived()
        }
    }
    /// Collapsed group names. "System & Other" starts collapsed; favorites and
    /// project groups can be collapsed too.
    @Published var collapsedGroups: Set<String> {
        didSet { defaults.set(Array(collapsedGroups), forKey: "controlport.collapsed") }
    }
    @Published var paused = false
    @Published var lastUpdated: Date?
    /// Rows whose termination signal was sent and that are waiting to exit;
    /// drawn with a strike-through.
    @Published var killingIds: Set<String> = []
    /// Records that appeared in the latest scan; show a "new" seal briefly.
    @Published var newIds: Set<String> = []
    /// Favorited ports that just became occupied; drives the menu bar dot.
    @Published var alertPorts: Set<Int> = []
    /// Footer notice (e.g. insufficient privileges), auto-clears after a few seconds.
    @Published var notice: String?
    /// Row selected for the detail page.
    @Published var selectedId: String?
    /// Live CPU% on the detail page (delta between two polling samples).
    @Published var detailCPU: Double?
    /// Toolbar "exposed only" quick filter.
    @Published var onlyExposed = false {
        didSet { invalidateDerived() }
    }
    /// The latest scan failed (lsof could not spawn or timed out); previous data
    /// is kept and the footer says so.
    @Published var scanFailed = false
    /// Kill request awaiting its second confirmation.
    @Published var pendingKillId: String?
    @Published var pendingKillForce = false
    /// Copyable command shown when a kill is denied for lack of privileges.
    @Published var deniedKillCommand: String?
    /// Settings page visibility (mutually exclusive with the detail page).
    @Published var showSettings = false
    /// Row forced into its hover state, used by the frame renderer: offscreen
    /// rendering cannot synthesise a real pointer, so the hover reveal has to be
    /// driven from state instead.
    @Published var forcedHoverId: String?
    /// Per-row appear progress (0 = not yet shown, 1 = fully in), keyed by entry
    /// id. nil means "no animation, show everything".
    @Published var rowAppearProgress: [String: Double]?
    /// Strike-through progress 0...1 for the row being ended.
    @Published var strikeProgress: Double = 1
    /// Detail page slide-in progress: 0 = offscreen right, 1 = fully covering.
    @Published var detailProgress: Double = 1
    /// Synthetic detail data for mocked renders. Mock PIDs do not exist, so
    /// proc_pidinfo returns nothing and the detail page would render as a column
    /// of dashes. nil in normal use, where the real process is introspected.
    @Published var detailOverride: PortScanner.ProcessDetail?
    /// Refresh interval in seconds, adjustable in settings.
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "controlport.interval")
            if !paused { restartTimer() }
        }
    }
    /// Whether the menu bar shows the port count.
    @Published var showMenuBarCount: Bool {
        didSet { defaults.set(showMenuBarCount, forKey: "controlport.menu.count") }
    }
    /// Launch at login (SMAppService); change through setLaunchAtLogin.
    @Published private(set) var launchAtLogin: Bool

    static var systemGroupName: String { AlertRules.systemGroupName }
    /// Lets offscreen rendering hide editable controls and skip timers.
    let isPreviewRender: Bool
    /// Render the ledger without its ScrollView. ImageRenderer cannot size a
    /// scroll view's content, so the rows come out blank; frame and preview
    /// renders flatten the list instead. Never set in the running app.
    let flatList: Bool
    private let defaults: UserDefaults
    private var previousIds: Set<String> = []
    private var previousOccupied: Set<Int> = []
    /// Snapshot caches behind `filtered`, `groups` and `projectCount`; nil means
    /// "recompute on next read".
    private var cachedGroups: [(name: String, entries: [PortEntry])]?
    private var cachedFiltered: [PortEntry]?
    private var cachedProjectCount: Int?
    /// False until the first successful scan: without a prior snapshot there is
    /// no transition to detect.
    private var hasOccupiedBaseline = false
    private var timer: Timer?
    private var noticeTask: Task<Void, Never>?
    private var lastCPUSample: (seconds: Double, at: Date)?
    private var pendingKillResetTask: Task<Void, Never>?

    /// Suite backing mocked/screenshot runs, so diagnostics never touch the
    /// user's real preferences.
    static let previewDefaultsSuite = "controlport.verify"

    init(preview: Bool = false, defaults: UserDefaults? = nil, flatList: Bool = false) {
        // Preview and screenshot modes always use the scratch suite: the mock
        // fixtures write favorites, and with .standard that leaked into the
        // user's real settings.
        self.defaults = defaults ?? (preview ? UserDefaults(suiteName: Self.previewDefaultsSuite)! : .standard)
        self.isPreviewRender = preview
        self.flatList = flatList
        if self.defaults === UserDefaults.standard {
            Self.migrateLegacyPreferences(into: self.defaults)
        }
        self.viewMode = ViewMode(rawValue: self.defaults.string(forKey: "controlport.viewmode") ?? "") ?? .project
        self.refreshInterval = self.defaults.object(forKey: "controlport.interval") as? Double ?? 3
        self.showMenuBarCount = self.defaults.object(forKey: "controlport.menu.count") as? Bool ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let saved = self.defaults.array(forKey: "controlport.favorites") as? [Int] {
            self.favorites = Set(saved)
        } else {
            self.favorites = []
        }
        if let savedGroups = self.defaults.array(forKey: "controlport.collapsed") as? [String] {
            self.collapsedGroups = Set(savedGroups.map(AlertRules.migrateGroupName))
        } else {
            self.collapsedGroups = [AlertRules.systemGroupName]
        }
        // Scan immediately and keep the timer running: the menu bar badge must
        // show a count before the user ever opens the panel.
        if !preview {
            refreshOnce()
            restartTimer()
        }
    }

    /// The project was renamed controlPort -> PortPeek -> PortHawk, changing the
    /// bundle id each time; on first launch under a new identity, pull settings
    /// from the older domains. Missing keys only, so it is idempotent.
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

    /// Called when the panel opens: clear the dot and refresh immediately.
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

    /// First step: arm the "confirm" state on the row; it reverts after 2.5 s.
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

    /// Second step: actually send the signal.
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
                    self.showNotice("Not permitted to end PID \(pid)")
                    self.deniedKillCommand = command
                }
            }
            if !force {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                // Escalate to KILL when TERM did not take.
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

    // MARK: - Detail drill-down

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

    /// Delta of cumulative CPU time between two samples -> CPU%. The first
    /// sample only establishes a baseline.
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

    /// Canonical pasteboard write: clearContents before setString. Setting the
    /// string alone can hand the pastee stale content from a lingering lazy
    /// data provider — the classic "copied but pasted something old" bug. The
    /// return value lets callers report the real outcome.
    func copyToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Open a listening port in the default browser. Returns the URL it tried,
    /// or nil when the row has nothing to open (a favorite placeholder).
    @discardableResult
    func openInBrowser(_ entry: PortEntry) -> URL? {
        guard let url = entry.browseURL else {
            showNotice("Port \(entry.port) is not being listened on")
            return nil
        }
        NSWorkspace.shared.open(url)
        return url
    }

    // MARK: - Snapshot diff and derived data

    /// Commit a snapshot. A nil `fresh` means the scan failed: keep the previous
    /// data and only raise the failure flag.
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

        let occupiedNow = Set(fresh.map(\.port))
        alertPorts.formUnion(AlertRules.newlyOccupiedFavorites(
            favorites: favorites,
            previousOccupied: previousOccupied,
            currentOccupied: occupiedNow,
            hasBaseline: hasOccupiedBaseline
        ))
        previousOccupied = occupiedNow
        hasOccupiedBaseline = true

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

    func toggleGroup(_ name: String) {
        if collapsedGroups.contains(name) {
            collapsedGroups.remove(name)
        } else {
            collapsedGroups.insert(name)
        }
    }

    /// Open settings (mutually exclusive with the detail page).
    func openSettings() {
        selectedId = nil
        showSettings = true
    }

    /// Launch-at-login toggle. When SMAppService registration fails, re-read the
    /// real status so the switch never lies.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showNotice("Could not change launch at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var projectCount: Int {
        if let cached = cachedProjectCount { return cached }
        let value = Set(entries.compactMap(\.project)).count
        cachedProjectCount = value
        return value
    }

    var filtered: [PortEntry] {
        if let cached = cachedFiltered { return cached }
        let q = query.trimmingCharacters(in: .whitespaces)
        let value = entries
            .filter { !onlyExposed || $0.isLanExposed }
            .filter {
                q.isEmpty
                    || String($0.port).contains(q)
                    || String($0.pid).contains(q)
                    || $0.processName.localizedCaseInsensitiveContains(q)
                    || ($0.project?.localizedCaseInsensitiveContains(q) ?? false)
            }
        cachedFiltered = value
        return value
    }

    /// Ledger groups. Favorites always come first: real rows plus faint
    /// placeholder rows for favorited ports that are idle. In project view the
    /// remaining entries group by project (favorites are not repeated) with
    /// "System & Other" last; in port view everything else lands in "All ports".
    ///
    /// Cached per snapshot: `groups` is read by the body of every group section,
    /// so recomputing it on each of SwiftUI's evaluation passes made a 300-row
    /// ledger rebuild the whole grouping several times per frame.
    var groups: [(name: String, entries: [PortEntry])] {
        if let cached = cachedGroups { return cached }
        let visible = filtered
        let q = query.trimmingCharacters(in: .whitespaces)

        // Placeholders depend only on real occupancy and the search text; the
        // "exposed only" filter deliberately does not apply to them.
        let occupiedPorts = Set(entries.map(\.port))
        let placeholders: [PortEntry] = favorites
            .filter { !occupiedPorts.contains($0) }
            .filter { q.isEmpty || String($0).contains(q) }
            .sorted()
            .map {
                PortEntry(port: $0, pid: 0, processName: "not in use",
                          host: "127.0.0.1", project: nil, projectPath: nil)
            }
        let favoriteGroup = (visible.filter { favorites.contains($0.port) } + placeholders)
            .sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }

        var result: [(String, [PortEntry])] = []
        if !favoriteGroup.isEmpty {
            result.append((AlertRules.favoritesGroupName, favoriteGroup))
        }

        let unmarked = visible.filter { !favorites.contains($0.port) }
        if viewMode == .port {
            result.append(("All ports", unmarked))
            cachedGroups = result
            return result
        }
        let byProject = Dictionary(grouping: unmarked) {
            $0.project ?? AlertRules.systemGroupName
        }
        result += byProject
            .map { (name: $0.key, entries: $0.value) }
            .sorted { a, b in
                if a.name == AlertRules.systemGroupName { return false }
                if b.name == AlertRules.systemGroupName { return true }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        cachedGroups = result
        return result
    }

    /// Drop the cached grouping/filter results. Called whenever an input changes
    /// so the next read recomputes once instead of on every evaluation pass.
    private func invalidateDerived() {
        cachedGroups = nil
        cachedFiltered = nil
        cachedProjectCount = nil
    }
}
