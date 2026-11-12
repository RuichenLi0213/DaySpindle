import SwiftUI

/// The window: the selected workspace (sidebar, toolbar, tabs, chart and details pane),
/// or a welcome screen when no workspace is open.
struct RootView: View {
    @ObservedObject var workspaces: Workspaces

    var body: some View {
        Group {
            if let store = workspaces.active {
                WorkspaceView(store: store, workspaces: workspaces)
                    .id(ObjectIdentifier(store))
            } else {
                NoWorkspaceView(workspaces: workspaces)
            }
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(Theme.canvas)
        .ignoresSafeArea()
    }
}

struct WorkspaceView: View {
    @ObservedObject var store: Store
    @ObservedObject var workspaces: Workspaces

    // Sidebar width (user-adjustable by dragging the divider; double-click resets).
    static let defaultSidebarWidth: CGFloat = 232
    static let minSidebarWidth: CGFloat = 180
    static let maxSidebarWidth: CGFloat = 420
    /// The toolbar's narrowest layout needs about this much room to the right of the sidebar.
    static let minContentWidth: CGFloat = 640
    static let sidebarWidthKey = "SidebarWidth"

    // Details pane width.
    static let defaultInspectorWidth: CGFloat = 340
    static let minInspectorWidth: CGFloat = 280
    static let maxInspectorWidth: CGFloat = 560
    static let inspectorWidthKey = "InspectorWidth"

    @AppStorage(WorkspaceView.sidebarWidthKey) private var storedSidebarWidth: Double = Double(WorkspaceView.defaultSidebarWidth)
    @AppStorage(WorkspaceView.inspectorWidthKey) private var storedInspectorWidth: Double = Double(WorkspaceView.defaultInspectorWidth)
    @ViewState private var resizeStartWidth: CGFloat = 0
    @ViewState private var inspectorResizeStart: CGFloat = 0

    private func sidebarWidth(total: CGFloat) -> CGFloat {
        let upper = max(Self.minSidebarWidth, min(Self.maxSidebarWidth, total - 1 - Self.minContentWidth))
        return min(max(CGFloat(storedSidebarWidth), Self.minSidebarWidth), upper)
    }

    private func inspectorWidth(total: CGFloat, sidebar: CGFloat) -> CGFloat {
        // The chart keeps at least 440 pt (task list and some timeline).
        let upper = max(240, min(Self.maxInspectorWidth, total - sidebar - 2 - 440))
        return min(max(CGFloat(storedInspectorWidth), min(Self.minInspectorWidth, upper)), upper)
    }

    var body: some View {
        GeometryReader { geo in
            let sw = sidebarWidth(total: geo.size.width)
            let iw = inspectorWidth(total: geo.size.width, sidebar: sw)
            HStack(spacing: 0) {
                SidebarView(store: store)
                    .frame(width: sw)
                Rectangle().fill(Theme.divider).frame(width: 1)
                VStack(spacing: 0) {
                    // Workspace tabs on top, then the toolbar (dates, time scale, appearance).
                    WorkspaceTabBar(workspaces: workspaces)
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    ToolbarView(store: store)
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    if store.filtersActive {
                        FilterBar(store: store)
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                    if let error = store.saveError {
                        Text(error)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.errorFill)
                    }
                    if let notice = store.notice {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.accent)
                            Text(notice).font(Theme.font(12)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Dismiss") { store.notice = nil }.buttonStyle(PillButtonStyle(height: 22))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Theme.filterBar)
                        .controlMarker("Notice")
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                    GanttChartRepresentable(store: store)
                }
                .background(Theme.canvas)
                if store.inspectorVisible {
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    InspectorView(store: store)
                        .frame(width: iw)
                }
            }
            // The drag strips sit above everything, centered on the 1 pt divider lines.
            .overlay(alignment: .topLeading) {
                ResizeHandle(
                    onBegin: { resizeStartWidth = sw },
                    onDrag: { dx in
                        let w = min(max(resizeStartWidth + dx, Self.minSidebarWidth), Self.maxSidebarWidth)
                        storedSidebarWidth = Double(w.rounded())
                    },
                    onReset: { storedSidebarWidth = Double(Self.defaultSidebarWidth) })
                    .frame(width: 9)
                    .frame(maxHeight: .infinity)
                    .help("Drag to resize the sidebar. Double-click to reset.")
                    .padding(.leading, sw + 0.5 - 4.5)
            }
            .overlay(alignment: .topTrailing) {
                if store.inspectorVisible {
                    ResizeHandle(
                        onBegin: { inspectorResizeStart = iw },
                        onDrag: { dx in
                            let w = min(max(inspectorResizeStart - dx, Self.minInspectorWidth), Self.maxInspectorWidth)
                            storedInspectorWidth = Double(w.rounded())
                        },
                        onReset: { storedInspectorWidth = Double(Self.defaultInspectorWidth) })
                        .frame(width: 9)
                        .frame(maxHeight: .infinity)
                        .help("Drag to resize the details. Double-click to reset.")
                        .padding(.trailing, iw + 0.5 - 4.5)
                }
            }
        }
        .background(Theme.canvas)
        .font(Theme.font(13))
        .foregroundStyle(Theme.text)
        .sheet(item: $store.activeSheet) { sheet in
            SheetHost(store: store, sheet: sheet)
                .font(Theme.font(13))
                .foregroundStyle(Theme.text)
                .background(Theme.canvas)
        }
    }
}

/// SwiftUI wrapper for the shared resize strip.
struct ResizeHandle: NSViewRepresentable {
    var onBegin: () -> Void
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void = {}
    var onReset: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let v = ResizeHandleView()
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: ResizeHandleView, context: Context) {
        v.onBegin = onBegin
        v.onDrag = onDrag
        v.onEnd = onEnd
        v.onReset = onReset
    }
}

private struct SheetHost: View {
    @ObservedObject var store: Store
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .category(_, let draft): CategoryEditorSheet(store: store, draft: draft)
        case .tag(_, let draft): TagEditorSheet(store: store, draft: draft)
        case .confirm(_, let c): ConfirmSheet(store: store, confirmation: c)
        case .todayColor(_, let hex): TodayColorSheet(store: store, hex: hex)
        case .categoryNote(_, let id, let text): CategoryNoteSheet(store: store, categoryID: id, text: text)
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @ObservedObject var store: Store

    var body: some View {
        // Uses the roomiest layout that fits the current width.
        ViewThatFits(in: .horizontal) {
            bar(newTaskLabel: true, dateIcons: true)
            bar(newTaskLabel: true, dateIcons: false)
            bar(newTaskLabel: false, dateIcons: false)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(WindowDragArea())
        .background(Theme.canvas)
    }

    private func bar(newTaskLabel: Bool, dateIcons: Bool) -> some View {
        HStack(spacing: 6) {
            NewItemButton(store: store, label: newTaskLabel)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Text("FROM").font(Theme.font(12)).foregroundStyle(Theme.secondaryText).controlMarker("From")
                DayPickerButton(day: store.window.start, today: store.today, firstWeekday: store.firstWeekday,
                                compact: true, showIcon: dateIcons, accessibilityName: "First visible day") {
                    store.setWindowStart($0)
                }
                Text("TO").font(Theme.font(12)).foregroundStyle(Theme.secondaryText).controlMarker("TO")
                DayPickerButton(day: store.window.end, minDay: store.window.start, today: store.today,
                                firstWeekday: store.firstWeekday, compact: true,
                                showIcon: dateIcons, accessibilityName: "Last visible day") { store.setWindowEnd($0) }
            }

            TimeScaleMenuButton(store: store)

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                segment(symbol: "chevron.left", help: "Previous period") { store.shiftWindow(by: -1) }
                Rectangle().fill(Theme.controlBorder).frame(width: 0.5, height: 16)
                Button("Today") { store.goToToday() }
                    .buttonStyle(PillButtonStyle(kind: .plain))
                    .help("Bring today into view (⌘T)")
                    .controlMarker("Today")
                Rectangle().fill(Theme.controlBorder).frame(width: 0.5, height: 16)
                segment(symbol: "chevron.right", help: "Next period") { store.shiftWindow(by: 1) }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 0.5))

            AppearanceButton()

            Button {
                store.inspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right").font(.system(size: 13, weight: .regular)).frame(width: 18, height: 18)
            }
            .buttonStyle(PillButtonStyle(kind: store.inspectorVisible ? .normal : .plain))
            .help(store.inspectorVisible ? "Hide Details (⌥⌘I)" : "Show Details (⌥⌘I)")
            .accessibilityLabel("Details")
            .controlMarker("Details")
        }
    }

    private func segment(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .regular)).frame(width: 18)
        }
        .buttonStyle(PillButtonStyle(kind: .plain))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// "+ New": a task (click), or pick a task, milestone, group or subtask from its menu.
struct NewItemButton: View {
    @ObservedObject var store: Store
    let label: Bool
    @ViewState private var showing = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                store.newItem(.task)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .regular))
                    if label { Text("New Task") }
                }
            }
            .buttonStyle(PillButtonStyle())
            .help("New Task (⌘N)")
            .accessibilityLabel("New Task")
            .controlMarker("New Task")
            Button {
                showing.toggle()
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .regular)).frame(width: 10)
            }
            .buttonStyle(PillButtonStyle(kind: .plain))
            .help("New group, task or milestone")
            .accessibilityLabel("New menu")
            .controlMarker("New menu")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    item("New Group", .group, "⇧⌘G") { store.newItem(.group) }
                    item("New Task", .task, "⌘N") { store.newItem(.task) }
                    item("New Milestone", .milestone, "⇧⌘M") { store.newItem(.milestone) }
                    if let sel = store.selectedTaskID, store.kind(of: sel) != .milestone {
                        Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 3)
                        item("New Subtask Inside", .task, "⌥⌘N") { store.newItem(.task, parentID: sel) }
                        item(store.kind(of: sel) == .task ? "Milestone for This Task" : "Milestone Inside", .milestone, "") {
                            store.newItem(.milestone, parentID: sel)
                        }
                    }
                }
                .padding(8)
                .frame(width: 240)
                .background(Theme.canvas)
            }
        }
    }

    private func item(_ title: String, _ kind: ItemKind, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button {
            showing = false
            action()
        } label: {
            HStack(spacing: 8) {
                KindIcon(kind: kind, colorHex: Palette.blue, size: 9)
                Text(title)
                Spacer()
                Text(shortcut).font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 26))
        .controlMarker(title)
    }
}

/// Sun / Moon / computer button: switches the appearance (System → Light → Dark).
/// Right-click it to pick one directly.
struct AppearanceButton: View {
    @ObservedObject var settings = AppearanceSettings.shared

    var body: some View {
        Button {
            settings.mode = settings.mode.next
        } label: {
            Image(systemName: settings.mode.symbol)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(PillButtonStyle())
        .help("Appearance: \(settings.mode.title). Click for \(settings.mode.next.title).")
        .accessibilityLabel("Appearance")
        .controlMarker("Appearance")
        .contextMenu {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    settings.mode = mode
                } label: {
                    Label(mode.title, systemImage: settings.mode == mode ? "checkmark" : mode.symbol)
                }
            }
        }
    }
}

/// One segment of a Calendar-style segmented control.
struct SegmentButton: View {
    let title: String
    let accessibility: String
    let help: String
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.segmentSelected : (hovering ? Theme.controlHover : Color.clear))
                    .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1, y: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(accessibility)
        .controlMarker(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The time scale: one menu button showing the current scale ("2 Weeks"), or the
/// day count for a custom range. It lists the eight presets; the current one is checked.
struct TimeScaleMenuButton: View {
    @ObservedObject var store: Store
    @ViewState private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(store.currentPreset?.title ?? DayFormat.dayCount(store.window.dayCount))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(PillButtonStyle())
        .help("Time scale")
        .accessibilityLabel("Time scale")
        .controlMarker("Time scale")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Scale").font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 2)
                ForEach(WindowPreset.allCases) { p in
                    Button {
                        store.applyPreset(p)
                        showing = false
                    } label: {
                        HStack {
                            Text(p.title)
                            Spacer()
                            if store.currentPreset == p {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                    .accessibilityLabel(p.title)
                    .controlMarker(p.title)
                }
                if store.currentPreset == nil {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 3)
                    Text("Custom: \(DayFormat.range(store.window.start, store.window.end, referenceYear: store.today.year))")
                        .font(Theme.font(11)).foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 6)
                }
            }
            .padding(8)
            .frame(width: 190)
            .background(Theme.canvas)
        }
    }
}

// MARK: - Active filter summary

struct FilterBar: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 8) {
            Text("Showing").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
            if !store.hiddenCategoryIDs.isEmpty {
                let shown = store.shownCategories
                if shown.isEmpty {
                    Text("no categories").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                }
                ForEach(shown) { c in
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: c.colorHex)).frame(width: 8, height: 8)
                        Text(c.name).font(Theme.font(12))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Theme.filterChip))
                }
            }
            ForEach(store.tags.filter { store.selectedTagKeys.contains($0.lowercased()) }, id: \.self) { t in
                chip(Text("#\(t)")) { store.selectedTagKeys.remove(t.lowercased()) }
            }
            Spacer()
            Text("\(store.visibleTasks.count) of \(store.tasks.count) items")
                .font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
            Button("Clear Filters") { store.clearFilters() }
                .buttonStyle(PillButtonStyle(height: 24))
                .help("Show all categories and clear the tag filter (⌘K)")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.filterBar)
    }

    private func chip<Label: View>(_ label: Label, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            label.font(Theme.font(12))
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this filter")
        }
        .padding(.leading, 9).padding(.trailing, 5)
        .frame(height: 22)
        .background(Capsule().fill(Theme.filterChip))
    }
}
