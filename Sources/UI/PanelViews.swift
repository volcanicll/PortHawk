import SwiftUI

/// Panel root: a paper ledger. Header -> tabs/search -> rows -> footer; the
/// detail page slides in from the right and covers the list.
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
                // The frame renderer drives detailProgress to slide the page in;
                // live use leaves it at 1.
                DetailView()
                    .background(Paper.bg)
                    .offset(x: (1 - state.detailProgress) * 400)
                    .opacity(state.detailProgress)
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

// MARK: - Header

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
                .font(Paper.serif(19, .bold))
                .foregroundStyle(Paper.ink)
            // Printer's mark: a vermilion dot beside the title.
            Rectangle()
                .fill(Paper.vermilion.opacity(0.85))
                .frame(width: 5, height: 5)
            Text("Port Ledger")
                .font(Paper.serif(11))
                .foregroundStyle(Paper.inkSoft)
            Spacer()
            if let updated = state.lastUpdated {
                Text("updated " + Self.timeFormatter.string(from: updated))
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
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Tabs + search

private struct ToolbarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                tab(for: mode)
            }
            Spacer()
            searchField
            onlyExposedChip
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// "Exposed only" quick filter: which ports the LAN can reach.
    private var onlyExposedChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { state.onlyExposed.toggle() }
        } label: {
            Text("LAN only")
                .font(Paper.body(11, state.onlyExposed ? .medium : .regular))
                .foregroundStyle(state.onlyExposed ? Paper.ochre : Paper.inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    state.onlyExposed ? Paper.ochre.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(state.onlyExposed ? Paper.ochre.opacity(0.5) : Paper.hairline, lineWidth: 1)
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show only ports reachable from the LAN")
    }

    private func tab(for mode: ViewMode) -> some View {
        let selected = state.viewMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { state.viewMode = mode }
        } label: {
            VStack(spacing: 3) {
                Text(mode.rawValue)
                    .font(Paper.body(12, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Paper.ink : Paper.inkSoft)
                Rectangle()
                    .fill(selected ? Paper.blue : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(Paper.body(10))
                .foregroundStyle(Paper.inkSoft)
            // Offscreen rendering cannot draw an editable TextField, so stand in
            // with matching static text.
            if state.isPreviewRender {
                Text("port / process")
                    .font(Paper.body(12))
                    .foregroundStyle(Paper.inkSoft)
                    .frame(width: 96, alignment: .leading)
            } else {
                TextField("port / process", text: $state.query)
                    .font(Paper.body(12))
                    .textFieldStyle(.plain)
                    .frame(width: 96)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Paper.bg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Paper.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Ledger body

private struct LedgerListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // ImageRenderer cannot lay out a ScrollView's content, so offscreen
        // renders use a plain clipped stack instead and the rows show up.
        if state.flatList {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        // LazyVStack, not VStack: a ledger can hold hundreds of listeners, and a
        // plain VStack builds every row — each with its own onHover, contextMenu
        // and action menu — up front, which is what dropped frames while scrolling.
        // Lazy rows are created only as they scroll into view.
        //
        // The whole-list `.animation(...)` this used to carry is gone too: it
        // animated every row on every 3-second poll, so a scroll was fighting a
        // list-wide transition on top of the rows being rebuilt.
        LazyVStack(spacing: 0, pinnedViews: []) {
            if state.groups.isEmpty {
                emptyState(allEmpty: state.entries.isEmpty && state.favorites.isEmpty)
            } else {
                ForEach(state.groups, id: \.name) { group in
                    GroupSection(name: group.name, entries: group.entries)
                }
            }
        }
    }

    private func emptyState(allEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            SealMark(character: allEmpty ? "0" : "?", color: Paper.inkSoft)
            Text(allEmpty ? "Nothing is listening right now" : "No matching entries")
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

    private var isCollapsed: Bool { state.collapsedGroups.contains(name) }

    var body: some View {
        groupHeader
        if !isCollapsed {
            ForEach(entries) { entry in
                LedgerRow(entry: entry)
            }
        }
    }

    /// Group band: leading chevron collapses the group, favorites get a star;
    /// count on the right. The whole band is clickable.
    private var groupHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { state.toggleGroup(name) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(Paper.body(9, .semibold))
                    .foregroundStyle(Paper.inkSoft)
                    .frame(width: 11)
                if name == AlertRules.favoritesGroupName {
                    Image(systemName: "star.fill")
                        .font(Paper.body(10))
                        .foregroundStyle(Paper.ochre)
                }
                Text(name)
                    .font(Paper.serif(13, .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text("\(entries.count)")
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(Paper.body(9, .semibold))
                    .foregroundStyle(Paper.inkSoft.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Paper.bgDeep)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") group \(name)")
    }
}

// MARK: - Ledger row

private struct LedgerRow: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry
    @State private var hovered = false

    private var isKilling: Bool { state.killingIds.contains(entry.id) }
    private var isNew: Bool { state.newIds.contains(entry.id) }
    private var isAlerted: Bool { state.alertPorts.contains(entry.port) }
    private var isPlaceholder: Bool { entry.pid == 0 }
    private var isPendingKill: Bool { state.pendingKillId == entry.id }
    /// Hover can be forced from state so the frame renderer can show the
    /// revealed row actions.
    private var isHovered: Bool { hovered || state.forcedHoverId == entry.id }
    /// Per-row entrance progress; 1 when no animation is in progress.
    private var appear: Double { state.rowAppearProgress?[entry.id] ?? 1 }

    var body: some View {
        HStack(spacing: 8) {
            // Left margin column: monospaced port number, like a page number.
            Text(String(entry.port))
                .font(Paper.mono(16, .semibold))
                .monospacedDigit()
                .foregroundStyle(isKilling ? Paper.inkSoft : Paper.ink)
                .frame(width: 52, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let brand = entry.brand {
                        // Brand ink dot: a bead of colored ink on the paper.
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
                        Text("[\(project)]")
                            .font(Paper.body(12))
                            .foregroundStyle(Paper.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if isAlerted {
                        SealMark(character: "taken", color: Paper.vermilion)
                    } else if isNew {
                        SealMark(character: "new", color: Paper.blue)
                    }
                }
                Text(entry.subtitleText)
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.pid > 0 { scopeBadge }
            starButton
            if entry.pid > 0 {
                rowActions
            } else {
                Color.clear.frame(width: 88)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovered && entry.pid > 0 ? Paper.bgDeep : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if entry.pid > 0 { state.openDetail(entry) }
        }
        .overlay(alignment: .leading) { strikeLine }
        .help(entry.helpText)
        .opacity((isPlaceholder ? 0.55 : (isKilling ? 0.55 : 1)) * appear)
        // Entrance animation: rows fade up as they arrive. `appear` is 1 unless
        // the frame renderer is driving a transition.
        .offset(y: (1 - appear) * 6)
        .contextMenu {
            if entry.pid > 0 {
                actionMenuItems
            } else {
                Button("Copy port \(entry.port)") {
                    _ = state.copyToPasteboard(String(entry.port))
                }
                Button("Remove from favorites") {
                    state.toggleFavorite(port: entry.port)
                }
            }
        }    }

    /// The row menu and the inline "..." menu share one set of actions.
    @ViewBuilder
    private var actionMenuItems: some View {
        Button("Open in browser") {
            if let url = state.openInBrowser(entry) {
                state.flash("Opened \(url.absoluteString)")
            }
        }
        Divider()
        Button("Copy port \(entry.port)") {
            if state.copyToPasteboard(String(entry.port)) {
                state.flash("Copied port \(entry.port)")
            }
        }
        Button("Copy PID \(entry.pid)") {
            if state.copyToPasteboard(String(entry.pid)) {
                state.flash("Copied PID \(entry.pid)")
            }
        }
        Divider()
        Button("End \"\(entry.processName)\"") {
            state.requestKill(entry)
        }
        Button("Force end (SIGKILL)", role: .destructive) {
            state.requestKill(entry, force: true)
        }
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
        .accessibilityLabel("Favorite port \(entry.port)")
    }

    /// Trailing action area: a quiet ">" hint normally; on hover it becomes
    /// "End" (two-step) plus the "..." menu.
    @ViewBuilder
    private var rowActions: some View {
        ZStack {
            if isHovered || isKilling || isPendingKill {
                HStack(spacing: 6) {
                    killButton
                    Menu {
                        actionMenuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(Paper.body(12, .semibold))
                            .foregroundStyle(Paper.inkSoft)
                            .frame(width: 24, height: 22)
                            .background(Paper.bgDeep, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More actions")
                }
                .transition(.opacity)
            } else {
                Image(systemName: "chevron.right")
                    .font(Paper.body(10, .semibold))
                    .foregroundStyle(Paper.inkSoft.opacity(0.55))
                    .transition(.opacity)
            }
        }
        .frame(width: 88, alignment: .trailing)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: state.pendingKillId)
    }

    /// End button: the first click turns it into a solid "Confirm"; a second
    /// click within 2.5 s sends the signal.
    @ViewBuilder
    private var killButton: some View {
        ZStack {
            if isPendingKill {
                Button {
                    state.confirmPendingKill()
                } label: {
                    Text(state.pendingKillForce ? "Force?" : "Confirm?")
                        .font(Paper.body(10, .semibold))
                        .foregroundStyle(Paper.bg)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Paper.vermilion, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Button {
                    state.requestKill(entry)
                } label: {
                    Text(isKilling ? "ending" : "end")
                        .font(Paper.body(11, .medium))
                        .foregroundStyle(Paper.vermilion)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("End process \(entry.processName)")
            }
        }
        .frame(width: 52, alignment: .trailing)
    }

    /// Vermilion strike-through: a line drawn across the row while ending.
    /// The renderer can drive `strikeProgress` to animate the stroke left to
    /// right; live use leaves it at 1.
    @ViewBuilder
    private var strikeLine: some View {
        if isKilling {
            GeometryReader { geo in
                Rectangle()
                    .fill(Paper.vermilion)
                    .frame(width: max(0, (geo.size.width - 32) * state.strikeProgress), height: 1.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.leading, 16)
            .transition(.opacity)
        }
    }
}

// MARK: - Settings

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
                .accessibilityLabel("Back to the ledger")
                Text("Settings")
                    .font(Paper.serif(15, .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text("v" + version)
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Hairline()

            // ImageRenderer cannot lay out a ScrollView, so offscreen renders
            // flatten the settings body too.
            if state.flatList {
                settingsBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    settingsBody
                }
            }
        }
    }

    @ViewBuilder
    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Refresh") {
                HStack(spacing: 8) {
                    ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { interval in
                        intervalChip(interval)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Hairline()
            section("Menu bar") {
                toggleRow(
                    "Show port count",
                    subtitle: "Total listening ports next to the book icon",
                    isOn: Binding(get: { state.showMenuBarCount }, set: { state.showMenuBarCount = $0 })
                )
                toggleRow(
                    "Launch at login",
                    subtitle: "Stay in the menu bar after a restart",
                    isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
                )
            }
            Hairline()
            section("Data") {
                Text("/usr/sbin/lsof · TCP listeners only · polling every \(Int(state.refreshInterval)) s")
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Paper.serif(12, .bold))
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
            Text("\(Int(interval))s")
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
            PaperToggle(isOn: isOn)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Detail page

private struct DetailView: View {
    @EnvironmentObject var state: AppState
    @State private var armedKill = false
    @State private var armedForce = false
    /// In-place copy feedback ("pid" / "port"): the detail page covers the
    /// panel footer, so the flash would be invisible — the feedback has to be
    /// drawn on the button itself.
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
        let detail = state.detailOverride ?? PortScanner.detail(for: entry.pid)
        let brand = DevBrand.match(processName: entry.processName)
        let subtitle = (brand.map { "\($0.label) · " } ?? "") + (entry.project ?? "system process")
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
                .accessibilityLabel("Back to the ledger")
                Text("Process detail")
                    .font(Paper.serif(15, .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text("port " + String(entry.port))
                    .font(Paper.mono(11))
                    .foregroundStyle(Paper.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Hairline()
            // ImageRenderer cannot lay out a ScrollView, so offscreen renders
            // use a plain clipped stack.
            if state.flatList {
                detailBody(entry, detail: detail, brand: brand, subtitle: subtitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    detailBody(entry, detail: detail, brand: brand, subtitle: subtitle)
                }
            }

            Hairline()
            HStack(spacing: 7) {
                actionButton(
                    armedKill ? "Confirm?" : "End",
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
                    armedForce ? "Confirm?" : "Force end",
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
                quietButton("Open") {
                    if let url = state.openInBrowser(entry) {
                        state.flash("Opened \(url.absoluteString)")
                    }
                }
                quietButton(
                    copiedField == "pid" ? (copyFailed ? "✗ failed" : "✓ copied") : "Copy PID",
                    confirmed: copiedField == "pid", failed: copiedField == "pid" && copyFailed
                ) {
                    copyField("pid", String(entry.pid))
                }
                quietButton(
                    copiedField == "port" ? (copyFailed ? "✗ failed" : "✓ copied") : "Copy port",
                    confirmed: copiedField == "port", failed: copiedField == "port" && copyFailed
                ) {
                    copyField("port", String(entry.port))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// The scrolling body of the detail page, split out so offscreen renders can
    /// flatten it (ImageRenderer cannot lay out a ScrollView).
    @ViewBuilder
    private func detailBody(_ entry: PortEntry, detail: PortScanner.ProcessDetail, brand: DevBrand.Brand?, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(brand?.color ?? Paper.inkSoft.opacity(0.5))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(Paper.ink.opacity(0.18), lineWidth: 0.5))
                    .help(brand?.label ?? "Unknown app")
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
            section("Process") {
                kv("PID", String(entry.pid))
                kv("Parent", detail.parentPID.map(String.init) ?? "—")
                kv("User", detail.userName ?? "—")
                kv("Threads", detail.threadCount.map(String.init) ?? "—")
                kv("Memory", detail.residentBytes.map(Self.formatBytes) ?? "—")
                kv("CPU time", detail.cpuSeconds.map(Self.formatSeconds) ?? "—")
                kv("CPU now", state.detailCPU.map { String(format: "%.1f%%", $0) } ?? "sampling")
                kv("Executable", detail.executablePath ?? "—", wraps: true)
            }
            Hairline()
            section("Project") {
                kv("Directory", entry.projectPath ?? "system process, no project directory", wraps: true)
            }
            Hairline()
            section("Command") {
                let line = detail.commandLine?.joined(separator: " ") ?? "—"
                Text(line)
                    .font(Paper.body(12))
                    .foregroundStyle(Paper.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Paper.serif(12, .bold))
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
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Paper.body(12))
                .monospacedDigit()
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

    /// Neutral action (copy): faded ink with a ruled border, so it does not
    /// borrow vermilion's destructive meaning.
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
        case ..<60: return String(format: "%.1f s", seconds)
        case ..<3600:
            let m = Int(seconds) / 60, s = Int(seconds) % 60
            return "\(m) m \(String(format: "%02d", s)) s"
        default:
            let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
            return "\(h) h \(String(format: "%02d", m)) m"
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            if let notice = state.notice {
                // The notice takes the main slot so "not permitted + copy
                // command" fits on one line.
                Text(notice)
                    .font(Paper.body(10, .medium))
                    .foregroundStyle(Paper.vermilion)
                    .lineLimit(1)
                if let command = state.deniedKillCommand {
                    Button {
                        if state.copyToPasteboard(command) {
                            state.flash("Copied — run it in Terminal")
                        }
                    } label: {
                        Text("Copy sudo command")
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
                Text("\(state.entries.count) ports · \(state.projectCount) projects")
                    .font(Paper.mono(10))
                    .foregroundStyle(Paper.inkSoft)
                if state.scanFailed {
                    Text("scan failed · keeping last snapshot")
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
            .accessibilityLabel(state.paused ? "Resume refreshing" : "Pause refreshing")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(Paper.body(11))
                    .foregroundStyle(Paper.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit PortHawk")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Paper.bgDeep.opacity(0.6))
    }
}
