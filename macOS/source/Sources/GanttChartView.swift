import AppKit
import SwiftUI

// MARK: - Model handed to the chart

struct GanttRow: Equatable {
    var id: UUID
    var title: String
    var start: Day
    var end: Day
    var colorHex: String
    var tags: [String]
    /// Indentation level: 0 for a top-level task, 1 for a subtask, and so on.
    var depth: Int = 0
    /// Has subtasks shown under it (given the current filters).
    var hasChildren: Bool = false
    /// Its subtasks are hidden.
    var collapsed: Bool = false
    var parentID: UUID? = nil
    /// Times and location, shown after the dates ("09:30–17:00 · Room 204").
    var detail: String = ""
    /// The task's notes (marked with an icon; shown on hover).
    var notes: String? = nil
    /// Group (spans what's inside it), task (a bar) or milestone (a diamond).
    var kind: ItemKind = .task
    /// False for an empty group, which has no dates and no bar.
    var hasDates: Bool = true
    /// A milestone's time of day in minutes (nil = no time: the middle of its day).
    var minute: Int? = nil
    /// Milestones attached to this task, drawn as diamonds on its bar.
    var marks: [GanttMark] = []
    /// Marked as completed: listed after the unfinished items at its level and drawn faded, with a check.
    var completed: Bool = false

    /// Hover text: dates, times, location, milestones and notes.
    func toolTip(today: Day) -> String? {
        guard notes != nil || !detail.isEmpty || !marks.isEmpty || kind != .task else { return nil }
        var lines = [title]
        if hasDates {
            let range = kind == .milestone ? DayFormat.medium(start) : DayFormat.range(start, end, referenceYear: today.year)
            lines.append(range + (detail.isEmpty ? "" : " · " + detail))
        } else {
            lines.append("Empty group")
        }
        for m in marks { lines.append("◆ \(m.title): \(DayFormat.short(m.day))\(m.detail.isEmpty ? "" : " · " + m.detail)") }
        if let notes { lines.append(""); lines.append(notes) }
        return lines.joined(separator: "\n")
    }
}

/// A milestone shown on its task's row.
struct GanttMark: Equatable {
    var id: UUID
    var day: Day
    var minute: Int?
    var title: String
    var colorHex: String
    var detail: String = ""
    var completed: Bool = false

    func toolTip() -> String { "◆ \(title)\(completed ? " (completed)" : "")\n\(DayFormat.medium(day))\(detail.isEmpty ? "" : " · " + detail)" }
}

/// A dependency arrow.
struct GanttLink: Equatable {
    var id: UUID
    var from: UUID
    var to: UUID
    var type: DependencyType
    /// The sides of the two items the arrow leaves from and arrives at.
    var exitSide: LinkSide
    var entrySide: LinkSide
    var colorHex: String?
    var width: CGFloat
}

struct GanttModel: Equatable {
    var rows: [GanttRow]
    var window: DateWindow
    var today: Day
    var selectedID: UUID?
    var emptyMessage: String?
    /// Items matching the filters, including those hidden in collapsed groups.
    var taskCount: Int = 0
    /// First day of the week for the week bar (0 = Sunday).
    var firstWeekday: Int = 0
    /// The Today spindle color.
    var todayHex: String = TodayStyle.defaultHex
    var links: [GanttLink] = []
    /// The row each item is drawn on (its own, its task's for a milestone mark, or a folded group's).
    var anchorRow: [UUID: UUID] = [:]
    var selectedLinkID: UUID? = nil
    /// Minutes since midnight now, for the line in the Today column.
    var nowMinute: Int? = nil
    /// Showing the Archive (completed items).
    var archive: Bool = false

    static let empty = GanttModel(rows: [], window: DateWindow(start: Day(ordinal: 0), end: Day(ordinal: 13)),
                                  today: Day(ordinal: 0), selectedID: nil, emptyMessage: nil)
}

/// Dragging from a bar's connector handle to another item to add an arrow.
struct LinkDraft {
    var fromID: UUID
    var fromSide: LinkSide
    var origin: NSPoint
    var current: NSPoint
    /// The item under the pointer and which side the arrow would arrive at.
    var target: (id: UUID, side: LinkSide, point: NSPoint)?
}

/// The item the pointer is over, whose connector handles are shown.
struct HoverItem: Equatable {
    var row: Int
    var markID: UUID?
    var itemID: UUID
}

/// Reordering a task in the task list: the places it may go (among its siblings only).
struct ReorderSession {
    struct Slot { var y: CGFloat; var beforeID: UUID?; var depth: Int }
    var id: UUID
    var slots: [Slot]
    var current: Int?
}

struct DragSession {
    enum Mode { case move, resizeStart, resizeEnd }
    var id: UUID
    var mode: Mode
    var anchorX: CGFloat
    var originalStart: Day
    var originalEnd: Day
    var start: Day
    var end: Day
    /// Rows and milestone marks that move along (what's inside a group, a task's milestones).
    var shifted: Set<UUID> = []
    var changed: Bool { start != originalStart || end != originalEnd }
    var delta: Int { start - originalStart }
}

// MARK: - SwiftUI bridge

struct GanttChartRepresentable: NSViewRepresentable {
    @ObservedObject var store: Store

    func makeNSView(context: Context) -> GanttChartView {
        let view = GanttChartView(frame: .zero)
        view.onSelect = { [weak store] id in store?.selectedTaskID = id }
        view.onOpen = { [weak store] id in store?.beginEdit(id) }
        view.onDelete = { [weak store] id in store?.requestDelete(id) }
        view.onCommit = { [weak store] id, s, e in store?.updateDates(id, start: s, end: e) }
        view.onReveal = { [weak store] id in store?.reveal(id) }
        view.onCreate = { [weak store] day in store?.beginNewTask(start: day) }
        view.onToggle = { [weak store] id in store?.toggleCollapsed(id) }
        view.onNewSubtask = { [weak store] id in store?.beginNewSubtask(of: id) }
        view.onMoveOut = { [weak store] id in store?.moveOutOfParent(id) }
        view.parentTitle = { [weak store] id in store?.task(id)?.title }
        view.onReorder = { [weak store] id, before in store?.moveTask(id, before: before) }
        view.onMoveBy = { [weak store] id, offset in store?.moveTask(id, by: offset) }
        view.onComplete = { [weak store] id, done in store?.setCompleted(id, done) }
        view.canMoveBy = { [weak store] id, offset in store?.canMoveTask(id, by: offset) ?? false }
        view.onTodayColor = { [weak store] hex in store?.setTodayColor(hex) }
        view.onCustomTodayColor = { [weak store] in store?.beginTodayColor() }
        view.onFirstWeekday = { [weak store] day in store?.setFirstWeekday(day) }
        view.onShiftDays = { [weak store] days in store?.shiftWindow(days: days) }
        view.onAddMilestone = { [weak store] id in store?.beginNewMilestone(in: id) }
        view.onLink = { [weak store] from, fromSide, to, toSide in
            if store?.addDependency(from: from, to: to, type: DependencyType(exit: fromSide, entry: toSide),
                                    fromSide: fromSide, toSide: toSide) == nil { NSSound.beep() }
        }
        view.canLink = { [weak store] from, to in store?.linkProblem(from: from, to: to) == nil }
        view.onSelectLink = { [weak store] id in store?.selectedLinkID = id }
        view.onOpenLink = { [weak store] id in store?.openLink(id) }
        view.onDeleteLink = { [weak store] id in store?.deleteDependency(id) }
        view.onLinkType = { [weak store] id, type in store?.setDependencyType(id, type) }
        view.onLinkSide = { [weak store] id, exit, side in store?.setDependencySide(id, exit: exit, side) }
        view.itemTitle = { [weak store] id in store?.task(id)?.title }
        return view
    }

    func updateNSView(_ view: GanttChartView, context: Context) {
        view.model = store.chartModel
        if let request = store.scrollRequest, request.token != view.lastScrollToken {
            view.lastScrollToken = request.token
            view.scroll(toDay: request.day)
        }
    }
}

// MARK: - Container

/// Frozen-pane Gantt chart: a fixed corner, a header that scrolls horizontally,
/// a task list that scrolls vertically (never horizontally), and a scrollable timeline body.
/// The divider between the task list and the timeline can be dragged.
final class GanttChartView: NSView {
    static let headerHeight: CGFloat = 82
    static let monthRowHeight: CGFloat = 24
    static let weekRowHeight: CGFloat = 20
    /// Top of the weekday/date rows (below the month and week bars).
    static var dayRowsTop: CGFloat { monthRowHeight + weekRowHeight }
    static let rowHeight: CGFloat = 40
    static let barHeight: CGFloat = 24
    static let minDayWidth: CGFloat = 32

    // Task list width (user-adjustable).
    static let defaultTaskListWidth: CGFloat = 300
    static let minTaskListWidth: CGFloat = 180
    static let maxTaskListWidth: CGFloat = 640
    static let minTimelineWidth: CGFloat = 260
    static let taskListWidthKey = "TaskListWidth"

    // Task list row layout.
    static let indentStep: CGFloat = 16
    static func chevronX(depth: Int) -> CGFloat { 8 + CGFloat(min(depth, 10)) * indentStep }
    static func dotRect(depth: Int, rowTop y: CGFloat) -> NSRect {
        NSRect(x: chevronX(depth: depth) + 18, y: y + 9, width: 9, height: 9)
    }
    static func titleX(depth: Int) -> CGFloat { chevronX(depth: depth) + 34 }

    var model = GanttModel.empty {
        didSet {
            guard model != oldValue else { return }
            modelDidChange(from: oldValue)
        }
    }

    var onSelect: ((UUID?) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onCommit: ((UUID, Day, Day) -> Void)?
    var onReveal: ((UUID) -> Void)?
    var onCreate: ((Day) -> Void)?
    var onToggle: ((UUID) -> Void)?
    var onNewSubtask: ((UUID) -> Void)?
    var onMoveOut: ((UUID) -> Void)?
    var parentTitle: ((UUID) -> String?)?
    var onReorder: ((UUID, UUID?) -> Void)?
    var onMoveBy: ((UUID, Int) -> Void)?
    var onComplete: ((UUID, Bool) -> Void)?
    var canMoveBy: ((UUID, Int) -> Bool)?
    var onTodayColor: ((String) -> Void)?
    var onCustomTodayColor: (() -> Void)?
    var onFirstWeekday: ((Int) -> Void)?
    /// Scrolling sideways past either end of the range moves the range by this many days.
    var onShiftDays: ((Int) -> Void)?
    var onAddMilestone: ((UUID) -> Void)?
    /// A new arrow: (from, leaves at its end, to, arrives at its end).
    var onLink: ((UUID, LinkSide, UUID, LinkSide) -> Void)?
    var canLink: ((UUID, UUID) -> Bool)?
    var onSelectLink: ((UUID?) -> Void)?
    var onOpenLink: ((UUID) -> Void)?
    var onDeleteLink: ((UUID) -> Void)?
    var onLinkType: ((UUID, DependencyType) -> Void)?
    var onLinkSide: ((UUID, Bool, LinkSide) -> Void)?
    var itemTitle: ((UUID) -> String?)?
    private var timeScrollRemainder: CGFloat = 0

    /// An arrow being drawn from a connector handle.
    var linkDraft: LinkDraft? { didSet { timeline.needsDisplay = true } }
    /// The item under the pointer (its connector handles are shown).
    var hoverItem: HoverItem? {
        didSet { if hoverItem != oldValue { timeline.needsDisplay = true } }
    }
    /// The arrow under the pointer.
    var hoveredLinkID: UUID? {
        didSet { if hoveredLinkID != oldValue { timeline.needsDisplay = true } }
    }

    /// A task being dragged up or down in the task list.
    var reorder: ReorderSession? {
        didSet { left.needsDisplay = true; timeline.needsDisplay = true }
    }

    /// The width the user chose; the effective width is clamped to the space available.
    var preferredTaskListWidth: CGFloat = {
        let w = UserDefaults.standard.double(forKey: GanttChartView.taskListWidthKey)
        return w > 0 ? CGFloat(w) : GanttChartView.defaultTaskListWidth
    }()
    /// The current task list width.
    private(set) var taskListWidth: CGFloat = GanttChartView.defaultTaskListWidth
    let taskListHandle = ResizeHandleView()
    private var resizeStartWidth: CGFloat = 0

    private(set) var dayWidth: CGFloat = 40
    var drag: DragSession? { didSet { setAllNeedsDisplay() } }
    var hoveredRowID: UUID? {
        didSet { if hoveredRowID != oldValue { left.needsDisplay = true; timeline.needsDisplay = true } }
    }
    var lastScrollToken = 0
    private var didInitialScroll = false

    let corner = GanttCornerView()
    let header = GanttHeaderView()
    let left = GanttLeftView()
    /// Provides scrolling and scroll bars; its document view is an empty spacer sized to the content.
    let scrollView = TimelineScrollView()
    let documentView = FlippedSpacerView()
    /// Viewport-sized drawing layer above the clip view that renders the visible part of the timeline.
    let timeline = GanttTimelineView()

    /// The chart in the main window (used by the verification runner).
    static weak var current: GanttChartView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        GanttChartView.current = self
        wantsLayer = true
        scrollView.chart = self
        updateDividerColor()
        for v in [corner, header, left] as [GanttPane] { v.chart = self }
        timeline.chart = self

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        // Above the clip view, below the scroll bars.
        scrollView.addSubview(timeline, positioned: .above, relativeTo: scrollView.contentView)

        [corner, header, left, scrollView].forEach(addSubview)

        taskListHandle.onBegin = { [weak self] in
            guard let self else { return }
            self.resizeStartWidth = self.taskListWidth
        }
        taskListHandle.onDrag = { [weak self] dx in self?.setTaskListWidth(self!.resizeStartWidth + dx, save: false) }
        taskListHandle.onEnd = { [weak self] in self?.setTaskListWidth(self!.taskListWidth, save: true) }
        taskListHandle.onReset = { [weak self] in self?.setTaskListWidth(GanttChartView.defaultTaskListWidth, save: true) }
        taskListHandle.toolTip = "Drag to resize the task list. Double-click to reset."
        addSubview(taskListHandle)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The 1 pt gaps between panes show the layer color as the dividers.
    private func updateDividerColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = Theme.NS.divider.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDividerColor()
        setAllNeedsDisplay()
    }

    func setTaskListWidth(_ width: CGFloat, save: Bool) {
        preferredTaskListWidth = min(max(width.rounded(), Self.minTaskListWidth), Self.maxTaskListWidth)
        if save { UserDefaults.standard.set(Double(preferredTaskListWidth), forKey: Self.taskListWidthKey) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let available = max(Self.minTaskListWidth, bounds.width - Self.minTimelineWidth)
        taskListWidth = min(max(preferredTaskListWidth, Self.minTaskListWidth), available)
        let lw = taskListWidth, hh = Self.headerHeight
        let gap: CGFloat = 1 / (window?.backingScaleFactor ?? 2)
        taskListHandle.frame = NSRect(x: lw - 7, y: 0, width: 7 + gap, height: bounds.height)
        corner.frame = NSRect(x: 0, y: 0, width: lw, height: hh)
        header.frame = NSRect(x: lw + gap, y: 0, width: max(0, bounds.width - lw - gap), height: hh)
        left.frame = NSRect(x: 0, y: hh + gap, width: lw, height: max(0, bounds.height - hh - gap))
        scrollView.frame = NSRect(x: lw + gap, y: hh + gap, width: max(0, bounds.width - lw - gap),
                                  height: max(0, bounds.height - hh - gap))
        scrollView.tile()
        timeline.frame = scrollView.contentView.frame
        updateDocumentSize()
        updateToolTips()
        if !didInitialScroll && scrollView.contentSize.width > 0 {
            didInitialScroll = true
            // Never scroll (or re-enter layout) from inside a layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.window.contains(self.model.today) else { return }
                self.scroll(toDay: self.model.today, onlyIfHidden: true)
            }
        }
    }

    private func updateDocumentSize() {
        let clip = scrollView.contentSize
        let days = CGFloat(max(model.window.dayCount, 1))
        dayWidth = max(Self.minDayWidth, clip.width / days)
        let fullWidth = days * dayWidth
        let width = fullWidth <= clip.width + 0.5 ? clip.width : fullWidth
        let height = max(CGFloat(model.rows.count) * Self.rowHeight, clip.height)
        let size = NSSize(width: width, height: height)
        if documentView.frame.size != size { documentView.setFrameSize(size) }
        setAllNeedsDisplay()
    }

    private func modelDidChange(from old: GanttModel) {
        if let d = drag, !model.rows.contains(where: { $0.id == d.id || $0.marks.contains { $0.id == d.id } }) { drag = nil }
        if let h = hoverItem, h.row >= model.rows.count || (h.markID == nil && model.rows[h.row].id != h.itemID) { hoverItem = nil }
        if old.window != model.window || old.rows.count != model.rows.count {
            updateDocumentSize()
            needsLayout = true
        }
        needsLayout = true
        setAllNeedsDisplay()
        updateToolTips()
    }

    func updateToolTips() {
        left.updateToolTips()
        timeline.updateToolTips()
    }

    func setAllNeedsDisplay() {
        header.needsDisplay = true
        left.needsDisplay = true
        corner.needsDisplay = true
        timeline.needsDisplay = true
    }

    @objc private func clipBoundsChanged() {
        header.needsDisplay = true
        left.needsDisplay = true
        timeline.needsDisplay = true
        updateToolTips()
    }

    @objc private func clipFrameChanged() {
        if timeline.frame != scrollView.contentView.frame { timeline.frame = scrollView.contentView.frame }
        timeline.needsDisplay = true
    }

    var scrollOffset: NSPoint { scrollView.contentView.bounds.origin }

    /// The part of the timeline document currently visible.
    var visibleDocumentRect: NSRect { NSRect(origin: scrollOffset, size: scrollView.contentView.bounds.size) }

    /// Converts a timeline document point to window coordinates.
    func windowPoint(fromDocument p: NSPoint) -> NSPoint {
        timeline.convert(NSPoint(x: p.x - scrollOffset.x, y: p.y - scrollOffset.y), to: nil)
    }

    /// Scrolls horizontally so `day` is centered (when the timeline is wider than the view).
    func scroll(toDay day: Day, onlyIfHidden: Bool = false) {
        updateDocumentSize()
        let clip = scrollView.contentView
        let clipWidth = clip.bounds.width
        let docWidth = documentView.frame.width
        let clamped = min(max(day, model.window.start), model.window.end)
        let dayX = CGFloat(clamped - model.window.start) * dayWidth
        if onlyIfHidden && dayX >= clip.bounds.minX && dayX + dayWidth <= clip.bounds.maxX { return }
        var x = dayX + dayWidth / 2 - clipWidth / 2
        x = max(0, min(x, docWidth - clipWidth))
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Geometry

    func dates(for row: GanttRow) -> (Day, Day) {
        if let d = drag {
            if d.id == row.id { return (d.start, d.end) }
            if d.shifted.contains(row.id) { return (row.start + d.delta, row.end + d.delta) }
        }
        return (row.start, row.end)
    }

    /// A milestone mark's day, following a drag in progress.
    func day(for mark: GanttMark) -> Day {
        if let d = drag {
            if d.id == mark.id { return d.start }
            if d.shifted.contains(mark.id) { return mark.day + d.delta }
        }
        return mark.day
    }

    func dayX(_ d: Day) -> CGFloat { CGFloat(d - model.window.start) * dayWidth }

    static let milestoneSize: CGFloat = 18
    static let markSize: CGFloat = 13

    /// Where in its day a milestone sits: at its time, or in the middle of the day.
    func milestoneX(day: Day, minute: Int?) -> CGFloat {
        let fraction = minute.map { CGFloat(min(max($0, 0), 1440)) / 1440 } ?? 0.5
        return dayX(day) + dayWidth * fraction
    }

    /// Center of a milestone row's diamond.
    func milestoneCenter(index: Int, row: GanttRow) -> NSPoint {
        let (s, _) = dates(for: row)
        return NSPoint(x: milestoneX(day: s, minute: row.minute), y: CGFloat(index) * Self.rowHeight + Self.rowHeight / 2)
    }

    /// Center of a milestone mark on its task's row.
    func markCenter(index: Int, mark: GanttMark) -> NSPoint {
        NSPoint(x: milestoneX(day: day(for: mark), minute: mark.minute), y: CGFloat(index) * Self.rowHeight + Self.rowHeight / 2)
    }

    /// A task's or group's whole bar, even the part outside the visible range.
    func fullBarRect(index: Int, row: GanttRow) -> NSRect {
        let (s, e) = dates(for: row)
        let x0 = dayX(s) + 3, x1 = dayX(e + 1) - 3
        if row.kind == .group {
            return NSRect(x: x0, y: CGFloat(index) * Self.rowHeight + Self.groupBarTop, width: max(x1 - x0, 4), height: Self.groupBarHeight)
        }
        return NSRect(x: x0, y: CGFloat(index) * Self.rowHeight + (Self.rowHeight - Self.barHeight) / 2,
                      width: max(x1 - x0, 4), height: Self.barHeight)
    }

    static let groupBarTop: CGFloat = 10
    static let groupBarHeight: CGFloat = 15

    /// The box an arrow joins on an item: its whole bar, or the square around a diamond, in
    /// timeline document points.
    func itemFrame(_ id: UUID) -> NSRect? {
        guard let rowID = model.anchorRow[id], let i = model.rows.firstIndex(where: { $0.id == rowID }) else { return nil }
        let row = model.rows[i]
        func square(_ c: NSPoint, _ size: CGFloat) -> NSRect { NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size) }
        if id != rowID, let mark = row.marks.first(where: { $0.id == id }) {
            return square(markCenter(index: i, mark: mark), Self.markSize)
        }
        switch row.kind {
        case .milestone:
            return square(milestoneCenter(index: i, row: row), Self.milestoneSize)
        case .task, .group:
            guard row.hasDates else { return nil }
            return fullBarRect(index: i, row: row)
        }
    }

    /// Where an arrow leaves or arrives at an item: the middle of one of its four sides (left is
    /// its start, right its end), in timeline document points.
    func anchor(_ id: UUID, side: LinkSide) -> NSPoint? {
        itemFrame(id).map { Self.point(of: $0, side: side) }
    }

    static func point(of r: NSRect, side: LinkSide) -> NSPoint {
        switch side {
        case .left: return NSPoint(x: r.minX, y: r.midY)
        case .right: return NSPoint(x: r.maxX, y: r.midY)
        case .top: return NSPoint(x: r.midX, y: r.minY)
        case .bottom: return NSPoint(x: r.midX, y: r.maxY)
        }
    }

    /// The arrow's route: out of the predecessor, along the rows, into the successor, with
    /// right-angle turns. Returns nil when either end isn't on screen.
    func linkPoints(_ link: GanttLink) -> [NSPoint]? {
        guard let ra = itemFrame(link.from), let rb = itemFrame(link.to) else { return nil }
        if let rowA = model.anchorRow[link.from], rowA == model.anchorRow[link.to],
           let row = model.rows.first(where: { $0.id == rowA }) {
            let shown = { (id: UUID) in id == rowA || row.marks.contains { $0.id == id } }
            // Both ends are folded into the same collapsed group: nothing to draw.
            if !shown(link.from) && !shown(link.to) { return nil }
        }
        return bestRoute(from: ra, link.exitSide, to: rb, link.entrySide)
    }

    /// The route an arrow takes: of the right-angled routes that fit its sides, the one crossing the
    /// fewest other bars and diamonds (the simplest one when they tie).
    func bestRoute(from ra: NSRect, _ s1: LinkSide, to rb: NSRect, _ s2: LinkSide) -> [NSPoint] {
        let candidates = Self.routes(from: ra, s1, to: rb, s2)
        guard candidates.count > 1, !model.rows.isEmpty else { return candidates[0] }
        let lo = min(ra.minY, rb.minY) - Self.rowHeight, hi = max(ra.maxY, rb.maxY) + Self.rowHeight
        let first = max(0, Int(floor(lo / Self.rowHeight))), last = min(model.rows.count - 1, Int(floor(hi / Self.rowHeight)))
        var obstacles: [NSRect] = []
        if first <= last {
            for i in first...last {
                let row = model.rows[i]
                switch row.kind {
                case .milestone:
                    let c = milestoneCenter(index: i, row: row), h = Self.milestoneSize / 2
                    obstacles.append(NSRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h))
                case .task, .group:
                    if row.hasDates { obstacles.append(fullBarRect(index: i, row: row)) }
                }
            }
        }
        func crossings(_ pts: [NSPoint]) -> Int {
            var n = 0
            for k in 1..<pts.count {
                for r in obstacles where Self.crosses(pts[k - 1], pts[k], r.insetBy(dx: 1, dy: 1)) { n += 1 }
            }
            return n
        }
        let scores = candidates.map(crossings)
        return candidates[scores.indices.min { scores[$0] < scores[$1] } ?? 0]
    }

    /// Whether a horizontal or vertical segment passes through the inside of a box.
    static func crosses(_ a: NSPoint, _ b: NSPoint, _ r: NSRect) -> Bool {
        if abs(a.y - b.y) < 0.01 {
            return a.y > r.minY && a.y < r.maxY && max(a.x, b.x) > r.minX && min(a.x, b.x) < r.maxX
        }
        return a.x > r.minX && a.x < r.maxX && max(a.y, b.y) > r.minY && min(a.y, b.y) < r.maxY
    }

    /// Right-angled routes that leave box `ra` through side `s1` and enter box `rb` through `s2`,
    /// simplest first. Left and right ends take a short step sideways first; top and bottom ends a
    /// short step up or down, so lines run in the gaps between rows.
    static func routes(from ra: NSRect, _ s1: LinkSide, to rb: NSRect, _ s2: LinkSide) -> [[NSPoint]] {
        let a = point(of: ra, side: s1), b = point(of: rb, side: s2)
        let gapH: CGFloat = 10, gapV: CGFloat = 8
        var result: [[NSPoint]] = []
        func add(_ middle: [NSPoint]) { result.append(simplified([a] + middle + [b])) }
        switch (s1.isVertical, s2.isVertical) {
        case (false, false):
            let out = s1.dx                     // direction leaving the predecessor
            let into = -s2.dx                   // direction of travel entering the successor
            let e0 = a.x + out * gapH
            let e1 = b.x - into * gapH
            if abs(a.y - b.y) < 0.5 && (b.x - a.x) * into > gapH && out == into {
                add([])                         // straight along the row
            } else if out == into {
                if (e1 - e0) * out >= 0 {
                    add([NSPoint(x: e0, y: a.y), NSPoint(x: e0, y: b.y)])
                } else {
                    let yMid = a.y + (b.y >= a.y ? 1 : -1) * rowHeight / 2
                    add([NSPoint(x: e0, y: a.y), NSPoint(x: e0, y: yMid), NSPoint(x: e1, y: yMid), NSPoint(x: e1, y: b.y)])
                }
            } else {
                let xv = out > 0 ? max(e0, e1) : min(e0, e1)
                add([NSPoint(x: xv, y: a.y), NSPoint(x: xv, y: b.y)])
            }
        case (true, true):
            let out = s1.dy
            let into = -s2.dy
            let e0 = a.y + out * gapV
            let e1 = b.y - into * gapV
            if abs(a.x - b.x) < 0.5 && (b.y - a.y) * into > gapV && out == into {
                add([])                         // straight down or up
            } else if out == into {
                if (e1 - e0) * out >= 0 {
                    // Along the gap next to the successor, or the one next to the predecessor.
                    add([NSPoint(x: a.x, y: e1), NSPoint(x: b.x, y: e1)])
                    add([NSPoint(x: a.x, y: e0), NSPoint(x: b.x, y: e0)])
                } else {
                    // The successor is the wrong way: go round beside both items.
                    let left = min(ra.minX, rb.minX) - gapH, right = max(ra.maxX, rb.maxX) + gapH
                    let near = abs(a.x - left) + abs(b.x - left) <= abs(a.x - right) + abs(b.x - right)
                    for x in near ? [left, right] : [right, left] {
                        add([NSPoint(x: a.x, y: e0), NSPoint(x: x, y: e0), NSPoint(x: x, y: e1), NSPoint(x: b.x, y: e1)])
                    }
                }
            } else {
                let yv = out > 0 ? max(e0, e1) : min(e0, e1)
                add([NSPoint(x: a.x, y: yv), NSPoint(x: b.x, y: yv)])
            }
        case (false, true):
            let out = s1.dx, into = -s2.dy
            if (b.x - a.x) * out >= gapH && (b.y - a.y) * into >= gapV {
                add([NSPoint(x: b.x, y: a.y)])  // one turn
            }
            // Down (or up) beside the predecessor, then along the gap next to the successor.
            let x0 = a.x + out * gapH, y1 = b.y - into * gapV
            add([NSPoint(x: x0, y: a.y), NSPoint(x: x0, y: y1), NSPoint(x: b.x, y: y1)])
        case (true, false):
            let out = s1.dy, into = -s2.dx
            if (b.y - a.y) * out >= gapV && (b.x - a.x) * into >= gapH {
                add([NSPoint(x: a.x, y: b.y)])  // one turn
            }
            // Along the gap next to the predecessor, then down (or up) beside the successor.
            let y0 = a.y + out * gapV, x1 = b.x - into * gapH
            add([NSPoint(x: a.x, y: y0), NSPoint(x: x1, y: y0), NSPoint(x: x1, y: b.y)])
        }
        return result
    }

    /// Drops repeated points and points in the middle of a straight run.
    static func simplified(_ pts: [NSPoint]) -> [NSPoint] {
        var out: [NSPoint] = []
        for p in pts {
            if let last = out.last, abs(last.x - p.x) < 0.01 && abs(last.y - p.y) < 0.01 { continue }
            if out.count >= 2 {
                let a = out[out.count - 2], b = out[out.count - 1]
                let cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x)
                let dot = (b.x - a.x) * (p.x - b.x) + (b.y - a.y) * (p.y - b.y)
                if abs(cross) < 0.01 && dot >= 0 { out.removeLast() }
            }
            out.append(p)
        }
        return out
    }

    /// The arrow under a point (document coordinates), if any.
    func link(at p: NSPoint) -> UUID? {
        var best: (UUID, CGFloat)?
        for l in model.links {
            guard let pts = linkPoints(l) else { continue }
            let tolerance = max(4, l.width / 2 + 3)
            for k in 1..<pts.count {
                let d = Self.distance(p, pts[k - 1], pts[k])
                if d <= tolerance && d < (best?.1 ?? .infinity) { best = (l.id, d) }
            }
        }
        return best?.0
    }

    static func distance(_ p: NSPoint, _ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The item under a point when drawing an arrow, and the side of it nearest the point.
    func linkTarget(at p: NSPoint, excluding from: UUID) -> (id: UUID, side: LinkSide, point: NSPoint)? {
        guard let i = rowIndex(atY: p.y) else { return nil }
        let row = model.rows[i]
        var found: UUID?
        for mark in row.marks where mark.id != from {
            let c = markCenter(index: i, mark: mark)
            if abs(p.x - c.x) <= Self.markSize / 2 + 5 { found = mark.id }
        }
        if found == nil && row.id != from {
            switch row.kind {
            case .milestone:
                let c = milestoneCenter(index: i, row: row)
                if abs(p.x - c.x) <= Self.milestoneSize / 2 + 6 { found = row.id }
            case .task, .group:
                if row.hasDates {
                    let r = fullBarRect(index: i, row: row).insetBy(dx: -6, dy: -8)
                    if r.contains(p) { found = row.id }
                }
            }
        }
        guard let id = found, canLink?(from, id) ?? true, let frame = itemFrame(id) else { return nil }
        let side = LinkSide.allCases.min { a, b in
            let pa = Self.point(of: frame, side: a), pb = Self.point(of: frame, side: b)
            return hypot(p.x - pa.x, p.y - pa.y) < hypot(p.x - pb.x, p.y - pb.y)
        } ?? .left
        return (id, side, Self.point(of: frame, side: side))
    }

    /// Connector handles of the hovered item: just outside the middle of each of its four sides.
    func handles(for h: HoverItem) -> [(side: LinkSide, center: NSPoint)] {
        var result: [(LinkSide, NSPoint)] = []
        let visible = visibleDocumentRect
        for side in LinkSide.allCases {
            guard let a = anchor(h.itemID, side: side) else { continue }
            let d: CGFloat = side.isVertical ? 9 : 11
            var c = NSPoint(x: a.x + side.dx * d, y: a.y + side.dy * d)
            guard c.x > visible.minX + 2 && c.x < visible.maxX - 2 else { continue }
            // Keep the top and bottom handles fully in view.
            c.y = min(max(c.y, visible.minY + 7), visible.maxY - 7)
            result.append((side, c))
        }
        return result
    }

    func day(atX x: CGFloat) -> Day {
        model.window.start + Int(floor(x / dayWidth))
    }

    /// The visible part of a bar, plus whether it is cut off on the left/right by the window.
    func barRect(index: Int, start: Day, end: Day) -> (rect: NSRect, clippedLeft: Bool, clippedRight: Bool)? {
        let w = model.window
        let s = max(start, w.start), e = min(end, w.end)
        guard s <= e else { return nil }
        let inset: CGFloat = 3
        let x0 = CGFloat(s - w.start) * dayWidth + (start >= w.start ? inset : 0)
        let x1 = CGFloat(e - w.start + 1) * dayWidth - (end <= w.end ? inset : 0)
        let y = CGFloat(index) * Self.rowHeight + (Self.rowHeight - Self.barHeight) / 2
        return (NSRect(x: x0, y: y, width: max(x1 - x0, 4), height: Self.barHeight), start < w.start, end > w.end)
    }

    func rowIndex(atY y: CGFloat) -> Int? {
        let i = Int(floor(y / Self.rowHeight))
        return (y >= 0 && i < model.rows.count) ? i : nil
    }

    func selectNeighbor(_ offset: Int) {
        guard !model.rows.isEmpty else { return }
        var index = 0
        if let sel = model.selectedID, let i = model.rows.firstIndex(where: { $0.id == sel }) {
            index = min(max(i + offset, 0), model.rows.count - 1)
        } else if offset < 0 {
            index = model.rows.count - 1
        }
        let id = model.rows[index].id
        model.selectedID = id
        onSelect?(id)
        let rowRect = NSRect(x: scrollOffset.x, y: CGFloat(index) * Self.rowHeight, width: 1, height: Self.rowHeight)
        documentView.scrollToVisible(rowRect)
    }

    /// Updates the local copy immediately so the bar doesn't flash back before the store round-trips.
    func commit(_ session: DragSession) {
        guard session.changed else { return }
        for i in model.rows.indices {
            if model.rows[i].id == session.id {
                model.rows[i].start = session.start
                model.rows[i].end = session.end
            } else if session.shifted.contains(model.rows[i].id) {
                model.rows[i].start = model.rows[i].start + session.delta
                model.rows[i].end = model.rows[i].end + session.delta
            }
            for k in model.rows[i].marks.indices {
                let m = model.rows[i].marks[k]
                if m.id == session.id { model.rows[i].marks[k].day = session.start }
                else if session.shifted.contains(m.id) { model.rows[i].marks[k].day = m.day + session.delta }
            }
        }
        onCommit?(session.id, session.start, session.end)
    }

    /// What moves along when an item is dragged: everything below a group, a task's milestones.
    func shiftedIDs(forRow index: Int) -> Set<UUID> {
        let row = model.rows[index]
        var ids = Set(row.marks.map(\.id))
        guard row.kind == .group else { return ids }
        var k = index + 1
        while k < model.rows.count && model.rows[k].depth > row.depth {
            ids.insert(model.rows[k].id)
            ids.formUnion(model.rows[k].marks.map(\.id))
            k += 1
        }
        return ids
    }

    func select(_ id: UUID?) {
        model.selectedID = id
        if id != nil { model.selectedLinkID = nil }
        onSelect?(id)
    }

    // MARK: Scrolling through time

    /// Horizontal scrolling: first scrolls within the visible range; past either end it keeps
    /// going by moving the range itself, a day at a time, like scrolling in Calendar.
    /// `dx` is in points; positive moves later in time.
    func scrollTime(by dx: CGFloat) {
        let clip = scrollView.contentView
        let maxX = max(0, documentView.frame.width - clip.bounds.width)
        let x = clip.bounds.origin.x
        let wanted = x + dx
        let newX = min(max(wanted, 0), maxX)
        if newX != x {
            clip.scroll(to: NSPoint(x: newX, y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
        }
        let overflow = wanted - newX
        // Reset the leftover when the direction changes, so a reversal responds at once.
        if overflow == 0 || (overflow > 0) != (timeScrollRemainder > 0) { timeScrollRemainder = 0 }
        timeScrollRemainder += overflow
        let days = Int(timeScrollRemainder / dayWidth)
        if days != 0 {
            timeScrollRemainder -= CGFloat(days) * dayWidth
            onShiftDays?(days)
        }
    }

    // MARK: Reordering in the task list

    /// Starts dragging a task: it may only land among its siblings (same parent, same level).
    func beginReorder(id: UUID) {
        guard let i = model.rows.firstIndex(where: { $0.id == id }) else { return }
        let row = model.rows[i]
        let rh = Self.rowHeight
        // Among the siblings listed with it: unfinished items, or completed ones (listed after them).
        let siblings = model.rows.enumerated().filter {
            $0.element.parentID == row.parentID && $0.element.depth == row.depth && $0.element.completed == row.completed
        }
        var slots = siblings.map { ReorderSession.Slot(y: CGFloat($0.offset) * rh, beforeID: $0.element.id, depth: row.depth) }
        if let lastIndex = siblings.last?.offset {
            var end = lastIndex + 1
            while end < model.rows.count && model.rows[end].depth > row.depth { end += 1 }
            slots.append(ReorderSession.Slot(y: CGFloat(end) * rh, beforeID: nil, depth: row.depth))
        }
        reorder = ReorderSession(id: id, slots: slots, current: nil)
    }

    /// Picks the allowed slot nearest to a point in the task list (document y).
    func updateReorder(documentY y: CGFloat) {
        guard var r = reorder, !r.slots.isEmpty else { return }
        let best = r.slots.indices.min { abs(r.slots[$0].y - y) < abs(r.slots[$1].y - y) }
        if best != r.current { r.current = best; reorder = r }
    }

    func endReorder(commit: Bool) {
        guard let r = reorder else { return }
        reorder = nil
        guard commit, let c = r.current else { return }
        onReorder?(r.id, r.slots[c].beforeID)
    }

    // MARK: Header menu

    /// Right-click on the header: the Today spindle's color (on today's column) and the first day of the week.
    func headerMenu(onToday: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func swatch(_ hex: String) -> NSImage {
            NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
                NSColor(hex: hex).setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
        }
        func colorItems(into m: NSMenu) {
            for c in TodayStyle.choices {
                let item = ClosureMenuItem(title: c.name) { [weak self] in self?.onTodayColor?(c.hex) }
                item.image = swatch(c.hex)
                item.state = model.todayHex == c.hex ? .on : .off
                m.addItem(item)
            }
            let isCustom = !TodayStyle.choices.contains { $0.hex == model.todayHex }
            let custom = ClosureMenuItem(title: isCustom ? "Custom (\(model.todayHex))…" : "Custom Color…") { [weak self] in
                self?.onCustomTodayColor?()
            }
            if isCustom { custom.image = swatch(model.todayHex); custom.state = .on }
            m.addItem(custom)
        }
        if onToday {
            let title = NSMenuItem(title: "Today Color", action: nil, keyEquivalent: "")
            title.attributedTitle = NSAttributedString(string: "Today Color", attributes: [
                .font: Theme.nsFont(11), .foregroundColor: NSColor.secondaryLabelColor])
            title.isEnabled = false
            menu.addItem(title)
            colorItems(into: menu)
        } else {
            let sub = NSMenu()
            sub.autoenablesItems = false
            colorItems(into: sub)
            let item = ClosureMenuItem(title: "Today Color") {}
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let weekMenu = NSMenu()
        weekMenu.autoenablesItems = false
        for d in [0, 1, 6] {
            let item = ClosureMenuItem(title: DayFormat.weekdayLong[d]) { [weak self] in self?.onFirstWeekday?(d) }
            item.state = model.firstWeekday == d ? .on : .off
            weekMenu.addItem(item)
        }
        let weekItem = ClosureMenuItem(title: "First Day of Week") {}
        weekItem.submenu = weekMenu
        menu.addItem(weekItem)
        return menu
    }

    /// ← collapses the selected parent or moves to its parent; → expands it or moves to its first subtask.
    func outlineKey(right: Bool) {
        guard let sel = model.selectedID, let i = model.rows.firstIndex(where: { $0.id == sel }) else { return }
        let row = model.rows[i]
        if right {
            if row.hasChildren && row.collapsed { onToggle?(row.id) }
            else if row.hasChildren { selectNeighbor(1) }
        } else {
            if row.hasChildren && !row.collapsed { onToggle?(row.id) }
            else if let pid = row.parentID, let pi = model.rows.firstIndex(where: { $0.id == pid }) {
                selectNeighbor(pi - i)
            }
        }
    }

    func contextMenu(forRow index: Int?, day: Day?) -> NSMenu? {
        let menu = NSMenu()
        if let index {
            let row = model.rows[index]
            select(row.id)
            menu.addItem(ClosureMenuItem(title: "Show Details") { [weak self] in self?.onOpen?(row.id) })
            menu.addItem(ClosureMenuItem(title: row.completed ? "Return from Archive" : "Mark as Completed") { [weak self] in
                self?.onComplete?(row.id, !row.completed)
            })
            if row.kind != .milestone {
                menu.addItem(ClosureMenuItem(title: "Add Subtask") { [weak self] in self?.onNewSubtask?(row.id) })
                menu.addItem(ClosureMenuItem(title: row.kind == .task ? "Add Milestone to This Task" : "Add Milestone") { [weak self] in
                    self?.onAddMilestone?(row.id)
                })
            }
            if row.hasChildren {
                menu.addItem(ClosureMenuItem(title: row.collapsed ? "Expand Group" : "Collapse Group") { [weak self] in
                    self?.onToggle?(row.id)
                })
            }
            if let pid = row.parentID {
                let name = parentTitle?(pid).map { "Move Out of “\($0)”" } ?? "Move Up a Level"
                menu.addItem(ClosureMenuItem(title: name) { [weak self] in self?.onMoveOut?(row.id) })
            }
            let up = ClosureMenuItem(title: "Move Up") { [weak self] in self?.onMoveBy?(row.id, -1) }
            up.isEnabled = canMoveBy?(row.id, -1) ?? false
            let down = ClosureMenuItem(title: "Move Down") { [weak self] in self?.onMoveBy?(row.id, 1) }
            down.isEnabled = canMoveBy?(row.id, 1) ?? false
            menu.autoenablesItems = false
            menu.addItem(up)
            menu.addItem(down)
            if !(model.window.contains(row.start) || model.window.contains(row.end) ||
                 (row.start < model.window.start && row.end > model.window.end)) {
                menu.addItem(ClosureMenuItem(title: "Show in Timeline") { [weak self] in self?.onReveal?(row.id) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "Delete \(row.kind.title)…") { [weak self] in self?.onDelete?(row.id) })
        } else if let day {
            menu.addItem(ClosureMenuItem(title: "New Task on \(DayFormat.short(day))") { [weak self] in self?.onCreate?(day) })
        } else {
            return nil
        }
        return menu
    }

    /// Right-click on a milestone shown on a task's bar.
    func markMenu(_ mark: GanttMark) -> NSMenu {
        select(mark.id)
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Show Details") { [weak self] in self?.onOpen?(mark.id) })
        menu.addItem(ClosureMenuItem(title: mark.completed ? "Mark as Not Completed" : "Mark as Completed") { [weak self] in
            self?.onComplete?(mark.id, !mark.completed)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Delete Milestone…") { [weak self] in self?.onDelete?(mark.id) })
        return menu
    }

    /// Right-click on an arrow.
    func linkMenu(_ id: UUID) -> NSMenu {
        selectLink(id)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Show Details") { [weak self] in self?.onOpenLink?(id) })
        let current = model.links.first { $0.id == id }?.type
        let typeMenu = NSMenu()
        typeMenu.autoenablesItems = false
        for t in DependencyType.allCases {
            let item = ClosureMenuItem(title: t.title) { [weak self] in self?.onLinkType?(id, t) }
            item.state = t == current ? .on : .off
            typeMenu.addItem(item)
        }
        let typeItem = ClosureMenuItem(title: "Connect") {}
        typeItem.submenu = typeMenu
        menu.addItem(typeItem)
        let link = model.links.first { $0.id == id }
        for exit in [true, false] {
            let sideMenu = NSMenu()
            sideMenu.autoenablesItems = false
            let currentSide = exit ? link?.exitSide : link?.entrySide
            for side in LinkSide.allCases {
                let item = ClosureMenuItem(title: side.title) { [weak self] in self?.onLinkSide?(id, exit, side) }
                item.state = side == currentSide ? .on : .off
                sideMenu.addItem(item)
            }
            let sideItem = ClosureMenuItem(title: exit ? "Leaves From" : "Arrives At") {}
            sideItem.submenu = sideMenu
            menu.addItem(sideItem)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Delete Arrow") { [weak self] in self?.onDeleteLink?(id) })
        return menu
    }

    func selectLink(_ id: UUID?) {
        model.selectedLinkID = id
        if id != nil { model.selectedID = nil }
        onSelectLink?(id)
    }
}

/// Menu item with a closure action and a Helvetica title.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        attributedTitle = NSAttributedString(string: title, attributes: [.font: Theme.nsFont(13)])
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

final class FlippedSpacerView: NSView {
    override var isFlipped: Bool { true }
}

/// The timeline's scroll view: vertical scrolling as usual; sideways scrolling (trackpad,
/// or Shift + mouse wheel) moves through time, past the ends of the visible range.
final class TimelineScrollView: NSScrollView {
    weak var chart: GanttChartView?

    override func scrollWheel(with event: NSEvent) {
        guard let chart else { return super.scrollWheel(with: event) }
        var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { dx *= 10; dy *= 10 }
        if event.modifierFlags.contains(.shift) && dx == 0 { dx = dy; dy = 0 }
        if abs(dx) > abs(dy) {
            chart.scrollTime(by: -dx)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// A thin vertical strip that resizes the pane to its left when dragged.
/// Reports the horizontal distance since the mouse went down; double-click resets.
final class ResizeHandleView: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?
    private var startX: CGFloat = 0
    private(set) var dragging = false
    private var trackingArea: NSTrackingArea?

    static var cursor: NSCursor {
        if #available(macOS 15.0, *) { return .columnResize(directions: .all) }
        return .resizeLeftRight
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: Self.cursor) }
    override func cursorUpdate(with event: NSEvent) { Self.cursor.set() }
    override func mouseEntered(with event: NSEvent) { Self.cursor.set() }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?(); return }
        dragging = true
        startX = event.locationInWindow.x
        onBegin?()
        Self.cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(event.locationInWindow.x - startX)
        Self.cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onEnd?()
    }
}

// MARK: - Layer-drawn views

/// A view whose content is drawn by a CALayer (`draw(in:)`) instead of `NSView.draw(_:)`.
/// Mixing `draw(_:)` views into the SwiftUI hosting view kept SwiftUI's own content out
/// of window captures on macOS 27, so all custom drawing goes through this class.
class LayerDrawnView: NSView {
    let canvas = CanvasLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        canvas.owner = self
        canvas.needsDisplayOnBoundsChange = true
        canvas.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        layer?.addSublayer(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            super.needsDisplay = newValue
            if newValue { canvas.setNeedsDisplay() }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = layer?.bounds ?? bounds
        CATransaction.commit()
        canvas.setNeedsDisplay()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        canvas.contentsScale = window?.backingScaleFactor ?? 2
        canvas.setNeedsDisplay()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        canvas.setNeedsDisplay()
    }

    /// Draw here in flipped view coordinates (origin top-left).
    func drawContent() {}

    var hairline: CGFloat { 1 / (window?.backingScaleFactor ?? 2) }
}

final class CanvasLayer: CALayer {
    weak var owner: LayerDrawnView?

    override func draw(in ctx: CGContext) {
        guard let owner else { return }
        ctx.saveGState()
        if !contentsAreFlipped() {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        // Resolve the light/dark colors against the view's appearance.
        owner.effectiveAppearance.performAsCurrentDrawingAppearance { owner.drawContent() }
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}

// MARK: - Panes

class GanttPane: LayerDrawnView {
    weak var chart: GanttChartView?

    /// Scrolling over the frozen panes scrolls the timeline.
    override func scrollWheel(with event: NSEvent) {
        if let chart { chart.scrollView.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}

/// Drawing helpers shared by the panes.
enum Draw {
    static func text(_ string: String, font: NSFont, color: NSColor, in rect: NSRect,
                     alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    static func width(_ string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    static func roundedRect(_ r: NSRect, radius: CGFloat, roundLeft: Bool = true, roundRight: Bool = true) -> NSBezierPath {
        let rad = min(radius, r.height / 2, r.width / 2)
        let p = NSBezierPath()
        let lr = roundLeft ? rad : 0, rr = roundRight ? rad : 0
        // Flipped coordinates: minY is the top.
        p.move(to: NSPoint(x: r.minX + lr, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - rr, y: r.minY))
        if rr > 0 { p.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY + rr), radius: rr) }
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - rr))
        if rr > 0 { p.appendArc(from: NSPoint(x: r.maxX, y: r.maxY), to: NSPoint(x: r.maxX - rr, y: r.maxY), radius: rr) }
        p.line(to: NSPoint(x: r.minX + lr, y: r.maxY))
        if lr > 0 { p.appendArc(from: NSPoint(x: r.minX, y: r.maxY), to: NSPoint(x: r.minX, y: r.maxY - lr), radius: lr) }
        p.line(to: NSPoint(x: r.minX, y: r.minY + lr))
        if lr > 0 { p.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX + lr, y: r.minY), radius: lr) }
        p.close()
        return p
    }

    static func chevron(at center: NSPoint, pointingLeft: Bool, color: NSColor) {
        let p = NSBezierPath()
        let dx: CGFloat = pointingLeft ? 2.5 : -2.5
        p.move(to: NSPoint(x: center.x + dx, y: center.y - 4))
        p.line(to: NSPoint(x: center.x - dx, y: center.y))
        p.line(to: NSPoint(x: center.x + dx, y: center.y + 4))
        p.lineWidth = 1.6
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        color.setStroke()
        p.stroke()
    }

    static func pixelAligned(_ x: CGFloat, scale: CGFloat) -> CGFloat { (x * scale).rounded() / scale }

    /// A diamond (milestone) of the given width and height.
    static func diamond(center c: NSPoint, size: CGFloat) -> NSBezierPath {
        let h = size / 2
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y - h))
        p.line(to: NSPoint(x: c.x + h, y: c.y))
        p.line(to: NSPoint(x: c.x, y: c.y + h))
        p.line(to: NSPoint(x: c.x - h, y: c.y))
        p.close()
        p.lineJoinStyle = .round
        return p
    }

    /// A polyline with softly rounded corners.
    static func roundedPolyline(_ pts: [NSPoint], radius: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count > 2 {
            for k in 1..<(pts.count - 1) {
                let a = pts[k - 1], b = pts[k], c = pts[k + 1]
                let r = min(radius, hypot(b.x - a.x, b.y - a.y) / 2, hypot(c.x - b.x, c.y - b.y) / 2)
                if r > 0.5 { p.appendArc(from: b, to: c, radius: r) } else { p.line(to: b) }
            }
        }
        p.line(to: pts[pts.count - 1])
        return p
    }

    /// The fill and text colors of a completed item: a pale version of its color.
    static func completedColors(_ rgb: RGB) -> (fill: NSColor, text: NSColor) {
        let dark = NSAppearance.currentDrawing().isDark
        return dark ? (NSColor(rgb: rgb.mixed(with: .black, amount: 0.55)), NSColor(rgb: rgb.mixed(with: .white, amount: 0.55)))
                    : (NSColor(rgb: rgb.mixed(with: .white, amount: 0.62)), NSColor(rgb: rgb.mixed(with: .black, amount: 0.45)))
    }

    /// A check mark (✓) drawn with lines, `size` points wide.
    static func check(center c: NSPoint, size: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - size * 0.5, y: c.y))
        p.line(to: NSPoint(x: c.x - size * 0.12, y: c.y + size * 0.38))
        p.line(to: NSPoint(x: c.x + size * 0.5, y: c.y - size * 0.4))
        p.lineWidth = max(1.3, size * 0.2)
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        color.setStroke()
        p.stroke()
    }

    /// A filled circle with a white check: the list marker of a completed item.
    static func checkCircle(center c: NSPoint, diameter d: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
        check(center: c, size: d * 0.55, color: .white)
    }

    /// A filled arrowhead whose tip is at `tip`, pointing from `from`.
    static func arrowhead(tip: NSPoint, from: NSPoint, width lineWidth: CGFloat) -> NSBezierPath {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length = 6 + lineWidth * 1.6, half = 3.2 + lineWidth * 0.9
        let base = NSPoint(x: tip.x - cos(angle) * length, y: tip.y - sin(angle) * length)
        let p = NSBezierPath()
        p.move(to: tip)
        p.line(to: NSPoint(x: base.x + sin(angle) * half, y: base.y - cos(angle) * half))
        p.line(to: NSPoint(x: base.x - sin(angle) * half, y: base.y + cos(angle) * half))
        p.close()
        return p
    }
}

// MARK: Corner

final class GanttCornerView: GanttPane {
    override func drawContent() {
        Theme.NS.canvas.setFill()
        bounds.fill()
        guard let chart else { return }
        let x = GanttChartView.titleX(depth: 0)
        let count = chart.model.taskCount
        let countText = count == 1 ? "1 item" : "\(count) items"
        Draw.text(chart.model.archive ? "Archive · \(countText)" : countText, font: Theme.nsFont(11), color: Theme.NS.tertiaryText,
                  in: NSRect(x: x, y: 7, width: max(bounds.width - x - 8, 10), height: 14))
        // The single column header.
        Draw.text("Group / Task / Milestone", font: Theme.nsFont(12), color: Theme.NS.secondaryText,
                  in: NSRect(x: x, y: GanttChartView.headerHeight - 26, width: max(bounds.width - x - 8, 10), height: 16))
    }
}

// MARK: Header

final class GanttHeaderView: GanttPane {
    /// Right-click: Today color (on today's column) and first day of the week.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let chart else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let i = Int(floor((p.x + chart.scrollOffset.x) / chart.dayWidth))
        return chart.headerMenu(onToday: chart.model.window.start + i == chart.model.today)
    }

    override func drawContent() {
        Theme.NS.canvas.setFill()
        bounds.fill()
        guard let chart else { return }
        let m = chart.model, w = m.window, dw = chart.dayWidth
        let ox = chart.scrollOffset.x
        let scale = window?.backingScaleFactor ?? 2
        let monthBottom = GanttChartView.monthRowHeight
        let top = GanttChartView.dayRowsTop
        let first = max(0, Int(floor(ox / dw)))
        let last = min(w.dayCount - 1, Int(ceil((ox + bounds.width) / dw)))
        guard first <= last else { return }

        // Column backgrounds in the weekday/date rows: today's tint and weekends.
        // The tint never reaches into the month or week bars.
        for i in first...last {
            let day = w.start + i
            let x = CGFloat(i) * dw - ox
            if day == m.today {
                Theme.NS.todayFill.setFill()
                NSRect(x: x, y: top, width: dw, height: bounds.height - top).fill()
            } else if day.isWeekend {
                Theme.NS.weekend.setFill()
                NSRect(x: x, y: top, width: dw, height: bounds.height - top).fill()
            }
        }

        // Day separators.
        Theme.NS.gridLine.setFill()
        for i in first...(last + 1) {
            let x = Draw.pixelAligned(CGFloat(i) * dw - ox, scale: scale)
            NSRect(x: x, y: top + 6, width: 1 / scale, height: bounds.height - top - 6).fill()
        }

        // Hairlines between the month bar, the week bar and the date rows.
        Theme.NS.gridLine.setFill()
        NSRect(x: 0, y: monthBottom, width: bounds.width, height: 1 / scale).fill()
        NSRect(x: 0, y: top, width: bounds.width, height: 1 / scale).fill()

        // Month labels ("Nov 2026", sticky to the left edge) and month boundary lines.
        var monthStart = (w.start + first).firstOfMonth
        let monthFont = Theme.nsFont(12)
        while monthStart <= w.start + last {
            let nextMonth = monthStart.addingMonths(1)
            let si = max(monthStart - w.start, 0)
            let ei = min(nextMonth - w.start - 1, w.dayCount - 1)
            let sx = CGFloat(si) * dw - ox, ex = CGFloat(ei + 1) * dw - ox
            if monthStart > w.start {
                Theme.NS.monthLine.setFill()
                NSRect(x: Draw.pixelAligned(sx, scale: scale), y: 0, width: 1 / scale, height: monthBottom).fill()
            }
            let long = DayFormat.monthYear(monthStart)
            let short = DayFormat.monthShort[monthStart.month - 1]
            let longW = Draw.width(long, font: monthFont)
            let label = (ex - max(sx, 0)) >= longW + 16 ? long : short
            let lw = Draw.width(label, font: monthFont)
            let lx = min(max(sx, 0) + 8, ex - lw - 8)
            if lx + lw <= ex - 4 && ex - max(sx, 0) > lw + 8 {
                Draw.text(label, font: monthFont, color: Theme.NS.headerText,
                          in: NSRect(x: lx, y: 5, width: lw + 2, height: 16))
            }
            monthStart = nextMonth
        }

        // Week bar: "Week 46" over each week's columns (sticky), with week boundary lines.
        let weekFont = Theme.nsFont(11)
        var weekStart = Weeks.start(of: w.start + first, firstWeekday: m.firstWeekday)
        while weekStart <= w.start + last {
            let si = max(weekStart - w.start, 0)
            let ei = min(weekStart + 6 - w.start, w.dayCount - 1)
            let sx = CGFloat(si) * dw - ox, ex = CGFloat(ei + 1) * dw - ox
            if weekStart > w.start {
                Theme.NS.monthLine.setFill()
                NSRect(x: Draw.pixelAligned(sx, scale: scale), y: monthBottom, width: 1 / scale,
                       height: GanttChartView.weekRowHeight).fill()
            }
            let n = Weeks.number(of: weekStart, firstWeekday: m.firstWeekday)
            let room = ex - max(sx, 0) - 12
            let label = [("Week \(n)"), ("W\(n)"), ("\(n)")].first { Draw.width($0, font: weekFont) <= room }
            if let label {
                let lw = Draw.width(label, font: weekFont)
                let lx = min(max(sx, 0) + 6, ex - lw - 6)
                Draw.text(label, font: weekFont, color: Theme.NS.secondaryText,
                          in: NSRect(x: lx, y: monthBottom + 3.5, width: lw + 2, height: 14))
            }
            weekStart = weekStart + 7
        }

        // Weekday + day number; today is marked by color alone (weekday and date circle in the Today color).
        let weekdayFont = Theme.nsFont(10)
        let numberFont = Theme.nsFont(13)
        let circleText = (RGB(hex: m.todayHex)?.prefersLightText ?? true) ? NSColor.white : Theme.NS.barDarkText
        for i in first...last {
            let day = w.start + i
            let x = CGFloat(i) * dw - ox
            let isToday = day == m.today
            let weekday = dw >= 42 ? DayFormat.weekdayShort[day.weekday] : DayFormat.weekdayLetter[day.weekday]
            Draw.text(weekday, font: weekdayFont,
                      color: isToday ? Theme.NS.todayAccent : (day.isWeekend ? Theme.NS.tertiaryText : Theme.NS.secondaryText),
                      in: NSRect(x: x, y: top + 3, width: dw, height: 13), alignment: .center)
            let number = "\(day.dayOfMonth)"
            if isToday {
                let d: CGFloat = 22
                let circle = NSRect(x: x + (dw - d) / 2, y: top + 15, width: d, height: d)
                Theme.NS.todayAccent.setFill()
                NSBezierPath(ovalIn: circle).fill()
                Draw.text(number, font: numberFont, color: circleText,
                          in: NSRect(x: circle.minX, y: circle.minY + 4, width: d, height: 16), alignment: .center)
            } else {
                Draw.text(number, font: numberFont, color: day.isWeekend ? Theme.NS.secondaryText : Theme.NS.text,
                          in: NSRect(x: x, y: top + 19, width: dw, height: 16), alignment: .center)
            }
        }
    }
}

// MARK: Task list

/// The single "Task" column: disclosure chevron, category dot, bold title with its
/// tags inline in bold gray, and the dates underneath. Subtasks are indented.
final class GanttLeftView: GanttPane {
    private var trackingArea: NSTrackingArea?

    /// A click works right away even when the window isn't active (like the timeline).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private func rowIndex(at event: NSEvent) -> Int? {
        guard let chart else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        return chart.rowIndex(atY: p.y + chart.scrollOffset.y)
    }

    /// The clickable disclosure area of a row, in this view's coordinates.
    func chevronRect(row index: Int) -> NSRect? {
        guard let chart, index < chart.model.rows.count, chart.model.rows[index].hasChildren else { return nil }
        let row = chart.model.rows[index]
        let y = CGFloat(index) * GanttChartView.rowHeight - chart.scrollOffset.y
        return NSRect(x: GanttChartView.chevronX(depth: row.depth) - 4, y: y, width: 22, height: GanttChartView.rowHeight)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let chart else { return }
        chart.hoveredRowID = rowIndex(at: event).map { chart.model.rows[$0].id }
    }

    override func mouseExited(with event: NSEvent) { chart?.hoveredRowID = nil }

    /// The row pressed, for dragging it to a new position.
    private var press: (id: UUID, point: NSPoint)?

    override func mouseDown(with event: NSEvent) {
        guard let chart else { return }
        window?.makeFirstResponder(chart.timeline)
        press = nil
        if let i = rowIndex(at: event) {
            let id = chart.model.rows[i].id
            let p = convert(event.locationInWindow, from: nil)
            if let r = chevronRect(row: i), r.contains(p) {
                chart.onToggle?(id)
                return
            }
            chart.select(id)
            if event.clickCount == 2 { chart.onOpen?(id); return }
            press = (id, p)
        } else {
            chart.select(nil)
        }
    }

    /// Dragging a row moves the task up or down among its siblings (never to another level).
    override func mouseDragged(with event: NSEvent) {
        guard let chart, let press else { return }
        var p = convert(event.locationInWindow, from: nil)
        if chart.reorder == nil {
            guard hypot(p.x - press.point.x, p.y - press.point.y) > 4 else { return }
            chart.beginReorder(id: press.id)
            NSCursor.closedHand.set()
        }
        // Scroll when dragging near the top or bottom edge.
        let clip = chart.scrollView.contentView
        if p.y < 16 || p.y > bounds.height - 16 {
            let dy: CGFloat = p.y < 16 ? -10 : 10
            let maxY = max(0, chart.documentView.frame.height - clip.bounds.height)
            let y = min(max(clip.bounds.origin.y + dy, 0), maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            chart.scrollView.reflectScrolledClipView(clip)
            p = convert(event.locationInWindow, from: nil)
        }
        chart.updateReorder(documentY: p.y + chart.scrollOffset.y)
    }

    override func mouseUp(with event: NSEvent) {
        press = nil
        guard let chart, chart.reorder != nil else { return }
        chart.endReorder(commit: true)
        NSCursor.arrow.set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let chart, let i = rowIndex(at: event) else { return nil }
        return chart.contextMenu(forRow: i, day: nil)
    }

    override func drawContent() {
        Theme.NS.canvas.setFill()
        bounds.fill()
        guard let chart else { return }
        let m = chart.model
        let rh = GanttChartView.rowHeight
        let oy = chart.scrollOffset.y
        guard !m.rows.isEmpty else { return }

        let first = max(0, Int(floor(oy / rh)))
        let last = min(m.rows.count - 1, Int(floor((oy + bounds.height) / rh)))
        guard first <= last else { return }

        let titleFont = Theme.nsFont(13, bold: true)
        let tagFont = Theme.nsFont(12, bold: true)
        let dateFont = Theme.nsFont(11)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        for i in first...last {
            let row = m.rows[i]
            let y = CGFloat(i) * rh - oy
            if row.id == m.selectedID {
                Theme.NS.selection.setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: rh).fill()
            } else if row.id == chart.hoveredRowID {
                Theme.NS.hover.setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: rh).fill()
            }

            // Disclosure chevron for parents: › collapsed, ⌄ expanded.
            if row.hasChildren {
                let cx = GanttChartView.chevronX(depth: row.depth) + 7, cy = y + 13.5
                let p = NSBezierPath()
                if row.collapsed {
                    p.move(to: NSPoint(x: cx - 2, y: cy - 4.5))
                    p.line(to: NSPoint(x: cx + 2.5, y: cy))
                    p.line(to: NSPoint(x: cx - 2, y: cy + 4.5))
                } else {
                    p.move(to: NSPoint(x: cx - 4.5, y: cy - 2))
                    p.line(to: NSPoint(x: cx, y: cy + 2.5))
                    p.line(to: NSPoint(x: cx + 4.5, y: cy - 2))
                }
                p.lineWidth = 1.6
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                Theme.NS.chevron.setStroke()
                p.stroke()
            }

            // Kind marker in the item's color: dot (task), diamond (milestone), square (group).
            // A completed item's marker is a check in a circle.
            ColorCache.color(row.colorHex).setFill()
            let dot = GanttChartView.dotRect(depth: row.depth, rowTop: y)
            if row.completed {
                Draw.checkCircle(center: NSPoint(x: dot.midX, y: dot.midY), diameter: 12, color: ColorCache.color(row.colorHex))
            } else {
                switch row.kind {
                case .task: NSBezierPath(ovalIn: dot).fill()
                case .milestone: Draw.diamond(center: NSPoint(x: dot.midX, y: dot.midY), size: 11).fill()
                case .group: NSBezierPath(roundedRect: dot.insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2).fill()
                }
            }

            // Bold title, then the tags inline in bold gray. A note icon marks tasks with notes.
            let titleX = GanttChartView.titleX(depth: row.depth)
            let width = max(bounds.width - titleX - 10, 10)
            let titleWidth = row.notes == nil ? width : max(width - 20, 10)
            if row.notes != nil { drawNoteIcon(at: NSPoint(x: bounds.width - 22, y: y + 6)) }
            var titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: Theme.NS.text, .paragraphStyle: style]
            if row.completed {
                titleAttributes[.foregroundColor] = Theme.NS.secondaryText
                titleAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            let line = NSMutableAttributedString(string: row.title, attributes: titleAttributes)
            if !row.tags.isEmpty {
                line.append(NSAttributedString(string: "  " + row.tags.map { "#\($0)" }.joined(separator: " "), attributes: [
                    .font: tagFont, .foregroundColor: Theme.NS.tagText, .paragraphStyle: style]))
            }
            line.draw(with: NSRect(x: titleX, y: y + 5, width: titleWidth, height: 17),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            // Dates (regular). While dragging, the preview dates show in the accent color.
            let (start, end) = chart.dates(for: row)
            let dragging = chart.drag?.id == row.id || (chart.drag.map { $0.shifted.contains(row.id) } ?? false)
            var dateText: String
            switch row.kind {
            case .milestone: dateText = DayFormat.weekdayShortDate(start) + (start.year != m.today.year ? ", \(start.year)" : "")
            case .group where !row.hasDates: dateText = "Empty group"
            default: dateText = "\(DayFormat.range(start, end, referenceYear: m.today.year)) · \(DayFormat.dayCount(end - start + 1))"
            }
            if !row.detail.isEmpty { dateText += " · " + row.detail }
            if row.completed { dateText = "Completed · " + dateText }
            if let first = row.marks.first {
                dateText += " · ◆ \(first.title) \(DayFormat.short(chart.day(for: first)))"
                if row.marks.count > 1 { dateText += " +\(row.marks.count - 1)" }
            }
            Draw.text(dateText, font: dateFont, color: dragging ? Theme.NS.accent : Theme.NS.secondaryText,
                      in: NSRect(x: titleX, y: y + 22, width: width, height: 14))

            Theme.NS.rowLine.setFill()
            NSRect(x: 0, y: y + rh - hairline, width: bounds.width, height: hairline).fill()
        }
        drawReorderMarker(width: bounds.width, withDot: true)
    }

    /// A small page-with-lines icon.
    private func drawNoteIcon(at origin: NSPoint) {
        let r = NSRect(x: origin.x, y: origin.y, width: 11, height: 13)
        let page = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
        page.lineWidth = 1.1
        Theme.NS.chevron.setStroke()
        page.stroke()
        Theme.NS.chevron.setFill()
        for k in 0..<3 {
            NSRect(x: r.minX + 2.5, y: r.minY + 3 + CGFloat(k) * 2.8, width: k == 2 ? 4 : 6, height: 1.1).fill()
        }
    }

    /// Hover text for rows that have notes, times or a location.
    func updateToolTips() {
        removeAllToolTips()
        guard let chart, !chart.model.rows.isEmpty else { return }
        let rh = GanttChartView.rowHeight, oy = chart.scrollOffset.y
        let first = max(0, Int(floor(oy / rh)))
        let last = min(chart.model.rows.count - 1, Int(floor((oy + bounds.height) / rh)))
        guard first <= last else { return }
        for i in first...last where chart.model.rows[i].toolTip(today: chart.model.today) != nil {
            addToolTip(NSRect(x: 0, y: CGFloat(i) * rh - oy, width: bounds.width, height: rh), owner: self, userData: nil)
        }
    }

    /// The insertion line while a task is dragged to a new position.
    func drawReorderMarker(width: CGFloat, withDot: Bool) {
        guard let chart, let r = chart.reorder, let c = r.current else { return }
        let slot = r.slots[c]
        let y = slot.y - chart.scrollOffset.y
        let x0 = withDot ? GanttChartView.titleX(depth: slot.depth) - 8 : 0
        Theme.NS.accent.setFill()
        NSRect(x: x0, y: y - 1, width: width - x0, height: 2).fill()
        if withDot {
            let ring = NSBezierPath(ovalIn: NSRect(x: x0 - 7, y: y - 4, width: 8, height: 8))
            ring.lineWidth = 2
            Theme.NS.accent.setStroke()
            ring.stroke()
        }
    }
}

extension GanttLeftView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        guard let chart, let i = chart.rowIndex(atY: point.y + chart.scrollOffset.y) else { return "" }
        return chart.model.rows[i].toolTip(today: chart.model.today) ?? ""
    }
}

extension GanttTimelineView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        guard let chart, chart.drag == nil, chart.linkDraft == nil else { return "" }
        let p = NSPoint(x: point.x + chart.scrollOffset.x, y: point.y + chart.scrollOffset.y)
        guard let i = chart.rowIndex(atY: p.y) else { return "" }
        let row = chart.model.rows[i]
        for mark in row.marks {
            let c = chart.markCenter(index: i, mark: mark)
            if abs(p.x - c.x) <= 9 && abs(p.y - c.y) <= 9 { return mark.toolTip() }
        }
        return row.toolTip(today: chart.model.today) ?? ""
    }
}

// MARK: Timeline body

/// Viewport-sized view that draws the visible part of the timeline at the current
/// scroll offset and handles bar dragging. Points are converted to "document"
/// coordinates (the full timeline) for hit testing.
final class GanttTimelineView: LayerDrawnView {
    weak var chart: GanttChartView?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Event location in timeline document coordinates.
    private func documentPoint(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        let o = chart?.scrollOffset ?? .zero
        return NSPoint(x: p.x + o.x, y: p.y + o.y)
    }

    /// Width of the whole timeline document.
    private var documentWidth: CGFloat { chart?.documentView.frame.width ?? bounds.width }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                      .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    /// Hover text over items that have notes, times, a location or milestones.
    func updateToolTips() {
        removeAllToolTips()
        guard let chart, !chart.model.rows.isEmpty else { return }
        let rh = GanttChartView.rowHeight, o = chart.scrollOffset
        let first = max(0, Int(floor(o.y / rh)))
        let last = min(chart.model.rows.count - 1, Int(floor((o.y + bounds.height) / rh)))
        guard first <= last else { return }
        for i in first...last {
            let row = chart.model.rows[i]
            for mark in row.marks {
                let c = chart.markCenter(index: i, mark: mark)
                let r = NSRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16).offsetBy(dx: -o.x, dy: -o.y).intersection(bounds)
                if !r.isEmpty { addToolTip(r, owner: self, userData: nil) }
            }
            guard row.toolTip(today: chart.model.today) != nil else { continue }
            var rect: NSRect?
            switch row.kind {
            case .milestone:
                let c = chart.milestoneCenter(index: i, row: row)
                rect = NSRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)
            case .task, .group:
                if row.hasDates, let bar = chart.barRect(index: i, start: row.start, end: row.end) { rect = bar.rect }
            }
            if let rect {
                let r = rect.offsetBy(dx: -o.x, dy: -o.y).intersection(bounds)
                if !r.isEmpty { addToolTip(r, owner: self, userData: nil) }
            }
        }
    }

    // MARK: Hit testing

    enum Hit {
        case bar(Int, DragSession.Mode)
        case mark(Int, UUID)
        case handle(UUID, LinkSide, NSPoint)
        case link(UUID)
        case hint(Int)
        case row(Int)
        case empty
    }

    func hit(at p: NSPoint) -> Hit {
        guard let chart else { return .empty }
        // Connector handles of the hovered item come first: they sit just outside it.
        if let h = chart.hoverItem, chart.drag == nil {
            for handle in chart.handles(for: h) where hypot(p.x - handle.center.x, p.y - handle.center.y) <= 8 {
                return .handle(h.itemID, handle.side, chart.anchor(h.itemID, side: handle.side) ?? handle.center)
            }
        }
        guard let i = chart.rowIndex(atY: p.y) else {
            if let l = chart.link(at: p) { return .link(l) }
            return .empty
        }
        let row = chart.model.rows[i]
        for mark in row.marks.reversed() {
            let c = chart.markCenter(index: i, mark: mark)
            if abs(p.x - c.x) + abs(p.y - c.y) <= GanttChartView.markSize / 2 + 4 { return .mark(i, mark.id) }
        }
        switch row.kind {
        case .milestone:
            let c = chart.milestoneCenter(index: i, row: row)
            if abs(p.x - c.x) + abs(p.y - c.y) <= GanttChartView.milestoneSize / 2 + 4 && chart.model.window.contains(chart.dates(for: row).0) {
                return .bar(i, .move)
            }
        case .group:
            let (s, e) = chart.dates(for: row)
            if row.hasDates, let (r, _, _) = chart.barRect(index: i, start: s, end: e) {
                let g = NSRect(x: r.minX, y: CGFloat(i) * GanttChartView.rowHeight + GanttChartView.groupBarTop,
                               width: r.width, height: GanttChartView.groupBarHeight + 6)
                if g.insetBy(dx: -3, dy: -4).contains(p) { return .bar(i, .move) }
            }
        case .task:
            let (s, e) = chart.dates(for: row)
            if let (r, cl, cr) = chart.barRect(index: i, start: s, end: e), r.insetBy(dx: -3, dy: -3).contains(p) {
                let edge = min(8, max(4, r.width / 4))
                if !cl && p.x <= r.minX + edge { return .bar(i, .resizeStart) }
                if !cr && p.x >= r.maxX - edge { return .bar(i, .resizeEnd) }
                return .bar(i, .move)
            }
        }
        if let l = chart.link(at: p) { return .link(l) }
        if let h = hintRect(index: i, row: row), h.rect.contains(p) { return .hint(i) }
        return .row(i)
    }

    /// A small "‹ Oct 12 – Oct 14" pill for items entirely outside the visible window.
    func hintRect(index: Int, row: GanttRow) -> (rect: NSRect, text: String)? {
        guard let chart, row.hasDates else { return nil }
        let w = chart.model.window
        let before = row.end < w.start, after = row.start > w.end
        guard before || after else { return nil }
        let range = row.kind == .milestone ? "◆ \(DayFormat.short(row.start))" : DayFormat.range(row.start, row.end, referenceYear: chart.model.today.year)
        let text = before ? "‹  \(range)" : "\(range)  ›"
        let width = Draw.width(text, font: Theme.nsFont(11)) + 16
        let y = CGFloat(index) * GanttChartView.rowHeight + (GanttChartView.rowHeight - 20) / 2
        // Pinned to the visible edge, so the pill stays in view while scrolling sideways.
        let visible = chart.visibleDocumentRect
        let x = before ? visible.minX + 6 : visible.maxX - width - 6
        return (NSRect(x: x, y: y, width: width, height: 20), text)
    }

    private func cursor(for hit: Hit) -> NSCursor {
        switch hit {
        case .bar(_, .move), .mark: return .openHand
        case .bar(_, _):
            if #available(macOS 15.0, *) { return .columnResize(directions: .all) }
            return .resizeLeftRight
        case .handle: return .crosshair
        case .hint, .link: return .pointingHand
        default: return .arrow
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if chart?.drag != nil || chart?.linkDraft != nil { return }
        cursor(for: hit(at: documentPoint(event))).set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let chart else { return }
        let h = hit(at: documentPoint(event))
        if chart.drag == nil && chart.linkDraft == nil { cursor(for: h).set() }
        switch h {
        case .bar(let i, _):
            chart.hoveredRowID = chart.model.rows[i].id
            chart.hoverItem = HoverItem(row: i, markID: nil, itemID: chart.model.rows[i].id)
        case .mark(let i, let id):
            chart.hoveredRowID = chart.model.rows[i].id
            chart.hoverItem = HoverItem(row: i, markID: id, itemID: id)
        case .handle:
            break
        case .hint(let i), .row(let i):
            chart.hoveredRowID = chart.model.rows[i].id
            chart.hoverItem = nil
        case .link, .empty:
            chart.hoveredRowID = nil
            chart.hoverItem = nil
        }
        if case .link(let id) = h { chart.hoveredLinkID = id } else { chart.hoveredLinkID = nil }
    }

    override func mouseExited(with event: NSEvent) {
        chart?.hoveredRowID = nil
        chart?.hoveredLinkID = nil
        if chart?.linkDraft == nil { chart?.hoverItem = nil }
        if chart?.drag == nil { NSCursor.arrow.set() }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let chart else { return }
        window?.makeFirstResponder(self)
        let p = documentPoint(event)
        switch hit(at: p) {
        case .handle(let id, let side, let point):
            chart.linkDraft = LinkDraft(fromID: id, fromSide: side, origin: point, current: p, target: nil)
            NSCursor.crosshair.set()
        case .bar(let i, let mode):
            let row = chart.model.rows[i]
            chart.select(row.id)
            if event.clickCount >= 2 { chart.onOpen?(row.id); return }
            let (s, e) = chart.dates(for: row)
            chart.drag = DragSession(id: row.id, mode: mode, anchorX: p.x, originalStart: s,
                                     originalEnd: e, start: s, end: e, shifted: chart.shiftedIDs(forRow: i))
            (mode == .move ? NSCursor.closedHand : cursor(for: .bar(i, mode))).set()
        case .mark(let i, let id):
            chart.select(id)
            if event.clickCount >= 2 { chart.onOpen?(id); return }
            if let mark = chart.model.rows[i].marks.first(where: { $0.id == id }) {
                chart.drag = DragSession(id: id, mode: .move, anchorX: p.x, originalStart: mark.day,
                                         originalEnd: mark.day, start: mark.day, end: mark.day)
                NSCursor.closedHand.set()
            }
        case .link(let id):
            chart.selectLink(id)
            if event.clickCount >= 2 { chart.onOpenLink?(id) }
        case .hint(let i):
            chart.onReveal?(chart.model.rows[i].id)
        case .row(let i):
            chart.select(chart.model.rows[i].id)
            if event.clickCount == 2 { chart.onCreate?(chart.day(atX: p.x)) }
        case .empty:
            chart.select(nil)
            chart.selectLink(nil)
            if event.clickCount == 2 { chart.onCreate?(chart.day(atX: p.x)) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let chart else { return }
        if var draft = chart.linkDraft {
            chart.scrollView.contentView.autoscroll(with: event)
            let p = documentPoint(event)
            draft.current = p
            draft.target = chart.linkTarget(at: p, excluding: draft.fromID)
            chart.linkDraft = draft
            return
        }
        guard var d = chart.drag else { return }
        chart.scrollView.contentView.autoscroll(with: event)
        let p = documentPoint(event)
        let delta = Int(((p.x - d.anchorX) / chart.dayWidth).rounded())
        switch d.mode {
        case .move:
            d.start = d.originalStart + delta
            d.end = d.originalEnd + delta
        case .resizeStart:
            d.start = min(d.originalStart + delta, d.originalEnd)
            d.end = d.originalEnd
        case .resizeEnd:
            d.start = d.originalStart
            d.end = max(d.originalEnd + delta, d.originalStart)
        }
        if d.start != chart.drag?.start || d.end != chart.drag?.end {
            chart.drag = d
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let chart else { return }
        if let draft = chart.linkDraft {
            chart.linkDraft = nil
            if let t = draft.target { chart.onLink?(draft.fromID, draft.fromSide, t.id, t.side) }
            cursor(for: hit(at: documentPoint(event))).set()
            return
        }
        guard let d = chart.drag else { return }
        chart.drag = nil
        chart.commit(d)
        cursor(for: hit(at: documentPoint(event))).set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let chart else { return nil }
        let p = documentPoint(event)
        switch hit(at: p) {
        case .mark(let i, let id):
            guard let mark = chart.model.rows[i].marks.first(where: { $0.id == id }) else { return nil }
            return chart.markMenu(mark)
        case .link(let id): return chart.linkMenu(id)
        case .bar(let i, _), .hint(let i), .row(let i): return chart.contextMenu(forRow: i, day: nil)
        case .handle(let id, _, _):
            guard let i = chart.model.rows.firstIndex(where: { $0.id == id }) else { return nil }
            return chart.contextMenu(forRow: i, day: nil)
        case .empty: return chart.contextMenu(forRow: nil, day: chart.day(atX: p.x))
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let chart else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            if let link = chart.model.selectedLinkID { chart.onDeleteLink?(link) }
            else if let id = chart.model.selectedID { chart.onDelete?(id) }
        case 36, 76: // return, enter
            if let link = chart.model.selectedLinkID { chart.onOpenLink?(link) }
            else if let id = chart.model.selectedID { chart.onOpen?(id) }
        case 125 where event.modifierFlags.contains(.option), 126 where event.modifierFlags.contains(.option):
            // ⌥↑ / ⌥↓ move the selected item among its siblings.
            if let id = chart.model.selectedID { chart.onMoveBy?(id, event.keyCode == 126 ? -1 : 1) }
        case 125: chart.selectNeighbor(1)
        case 126: chart.selectNeighbor(-1)
        case 123: chart.outlineKey(right: false)
        case 124: chart.outlineKey(right: true)
        case 53: // escape cancels a drag, otherwise clears the selection
            if chart.linkDraft != nil { chart.linkDraft = nil }
            else if chart.reorder != nil { chart.endReorder(commit: false) }
            else if chart.drag != nil { chart.drag = nil }
            else { chart.select(nil); chart.selectLink(nil) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func drawContent() {
        Theme.NS.canvas.setFill()
        bounds.fill()
        guard let chart else { return }
        // Draw in document coordinates, shifted by the scroll offset.
        let dirtyRect = chart.visibleDocumentRect
        let shift = NSAffineTransform()
        shift.translateX(by: -dirtyRect.minX, yBy: -dirtyRect.minY)
        shift.concat()
        let m = chart.model, w = m.window, dw = chart.dayWidth
        let rh = GanttChartView.rowHeight
        let scale = window?.backingScaleFactor ?? 2
        let first = max(0, Int(floor(dirtyRect.minX / dw)))
        let last = min(w.dayCount - 1, Int(floor(dirtyRect.maxX / dw)))
        let firstRow = max(0, Int(floor(dirtyRect.minY / rh)))
        let lastRow = min(m.rows.count - 1, Int(floor(dirtyRect.maxY / rh)))

        // Weekend shading and the full-height Today column.
        if first <= last {
            for i in first...last {
                let day = w.start + i
                let col = NSRect(x: CGFloat(i) * dw, y: dirtyRect.minY, width: dw, height: dirtyRect.height)
                if day == m.today {
                    Theme.NS.todayFill.setFill()
                    col.fill()
                } else if day.isWeekend {
                    Theme.NS.weekend.setFill()
                    col.fill()
                }
            }
        }

        // Selected / hovered row bands.
        if firstRow <= lastRow {
            for r in firstRow...lastRow {
                let id = m.rows[r].id
                let band = NSRect(x: dirtyRect.minX, y: CGFloat(r) * rh, width: dirtyRect.width, height: rh)
                if id == m.selectedID {
                    Theme.NS.selection.setFill()
                    band.fill(using: .sourceOver)
                } else if id == chart.hoveredRowID {
                    Theme.NS.hover.setFill()
                    band.fill(using: .sourceOver)
                }
            }
        }

        // Day grid lines (month boundaries slightly darker).
        if first <= last {
            for i in first...(last + 1) {
                let day = w.start + i
                (day.dayOfMonth == 1 && i > 0 ? Theme.NS.monthLine : Theme.NS.gridLine).setFill()
                NSRect(x: Draw.pixelAligned(CGFloat(i) * dw, scale: scale), y: dirtyRect.minY,
                       width: 1 / scale, height: dirtyRect.height).fill()
            }
        }

        if let message = m.emptyMessage {
            let font = Theme.nsFont(13)
            let w = min(Draw.width(message, font: font) + 4, dirtyRect.width - 20)
            Draw.text(message, font: font, color: Theme.NS.secondaryText,
                      in: NSRect(x: dirtyRect.midX - w / 2, y: dirtyRect.minY + 80, width: w, height: 18), alignment: .center)
        }

        if firstRow <= lastRow {
            // Row separators.
            Theme.NS.rowLine.setFill()
            for r in firstRow...lastRow {
                NSRect(x: dirtyRect.minX, y: CGFloat(r + 1) * rh - 1 / scale, width: dirtyRect.width, height: 1 / scale).fill()
            }

            // Items (opaque, so the Today column never tints them) and off-window hints.
            for r in firstRow...lastRow {
                let row = m.rows[r]
                let (s, e) = chart.dates(for: row)
                let selected = row.id == m.selectedID
                let dragging = chart.drag?.id == row.id || (chart.drag?.shifted.contains(row.id) ?? false)
                let hovered = row.id == chart.hoveredRowID
                var drawn = false
                switch row.kind {
                case .milestone:
                    if w.contains(s) {
                        drawMilestone(row, center: chart.milestoneCenter(index: r, row: row), selected: selected,
                                      dragging: dragging, hovered: hovered)
                        drawn = true
                    }
                case .group:
                    if row.hasDates, let bar = chart.barRect(index: r, start: s, end: e) {
                        drawGroupBar(row, bar.rect, index: r, clippedLeft: bar.clippedLeft, clippedRight: bar.clippedRight,
                                     selected: selected, dragging: dragging, hovered: hovered)
                        drawn = true
                    } else if !row.hasDates {
                        drawn = true
                    }
                case .task:
                    if let bar = chart.barRect(index: r, start: s, end: e) {
                        drawBar(row, bar.rect, clippedLeft: bar.clippedLeft, clippedRight: bar.clippedRight,
                                selected: selected, dragging: dragging, hovered: hovered)
                        drawn = true
                    }
                }
                if !drawn, let h = hintRect(index: r, row: row) {
                    Theme.NS.chipFill.setFill()
                    Draw.roundedRect(h.rect, radius: 10).fill()
                    Draw.text(h.text, font: Theme.nsFont(11), color: Theme.NS.secondaryText,
                              in: NSRect(x: h.rect.minX + 8, y: h.rect.minY + 3.5, width: h.rect.width - 12, height: 14))
                }
                // A task's milestones, on its bar.
                for mark in row.marks where w.contains(chart.day(for: mark)) {
                    drawMark(mark, center: chart.markCenter(index: r, mark: mark), barHex: row.colorHex,
                             selected: mark.id == m.selectedID, dragging: chart.drag?.id == mark.id)
                }
            }
        }

        drawLinks()
        drawNowLine()
        if let h = chart.hoverItem, chart.drag == nil { drawHandles(h) }
        if let draft = chart.linkDraft { drawLinkDraft(draft) }

        if let d = chart.drag, let r = m.rows.firstIndex(where: { $0.id == d.id || $0.marks.contains { $0.id == d.id } }) {
            drawDragBubble(d, rowIndex: r)
        }
        if let r = chart.reorder, let c = r.current {
            Theme.NS.accent.setFill()
            NSRect(x: dirtyRect.minX, y: r.slots[c].y - 1, width: dirtyRect.width, height: 2).fill()
        }
    }

    private func drawBar(_ row: GanttRow, _ rect: NSRect, clippedLeft: Bool, clippedRight: Bool,
                         selected: Bool, dragging: Bool, hovered: Bool) {
        let rgb = RGB(hex: row.colorHex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        let done = row.completed ? Draw.completedColors(rgb) : nil
        let fill = done?.fill ?? NSColor(rgb: rgb)
        let textColor = done?.text ?? (rgb.prefersLightText ? NSColor.white : Theme.NS.barDarkText)
        let path = Draw.roundedRect(rect, radius: 6, roundLeft: !clippedLeft, roundRight: !clippedRight)

        NSGraphicsContext.saveGraphicsState()
        if dragging || hovered {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dragging ? 0.28 : 0.16)
            shadow.shadowBlurRadius = dragging ? 6 : 3
            shadow.shadowOffset = NSSize(width: 0, height: dragging ? -2 : -1)
            shadow.set()
        }
        fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        if selected {
            let ring = Draw.roundedRect(rect.insetBy(dx: -2, dy: -2), radius: 8, roundLeft: !clippedLeft, roundRight: !clippedRight)
            ring.lineWidth = 1.5
            let dark = NSAppearance.currentDrawing().isDark
            NSColor(rgb: rgb.mixed(with: dark ? .white : .black, amount: dark ? 0.45 : 0.35)).setStroke()
            ring.stroke()
        }

        var textMinX = rect.minX + 8
        var textMaxX = rect.maxX - 8
        if clippedLeft {
            Draw.chevron(at: NSPoint(x: rect.minX + 7, y: rect.midY), pointingLeft: true, color: textColor.withAlphaComponent(0.85))
            textMinX = rect.minX + 15
        }
        if clippedRight {
            Draw.chevron(at: NSPoint(x: rect.maxX - 7, y: rect.midY), pointingLeft: false, color: textColor.withAlphaComponent(0.85))
            textMaxX = rect.maxX - 15
        }

        // Bold title inside the bar, or just to its right when the bar is too short.
        let font = Theme.nsFont(12, bold: true)
        let title = row.completed ? "✓ " + row.title : row.title
        let titleW = Draw.width(title, font: font)
        let available = textMaxX - textMinX
        let outsideRoom = documentWidth - rect.maxX - 12
        if available < min(titleW, 64) && !clippedRight && outsideRoom > 40 {
            Draw.text(title, font: font, color: row.completed ? Theme.NS.secondaryText : Theme.NS.text,
                      in: NSRect(x: rect.maxX + 6, y: rect.minY + 5, width: min(titleW + 1, outsideRoom), height: 16))
        } else if available > 12 {
            Draw.text(title, font: font, color: textColor,
                      in: NSRect(x: textMinX, y: rect.minY + 5, width: available, height: 16))
        }
    }

    /// A group: a slim bar spanning everything inside it, with tabs pointing down at both ends.
    private func drawGroupBar(_ row: GanttRow, _ rect: NSRect, index: Int, clippedLeft: Bool, clippedRight: Bool,
                              selected: Bool, dragging: Bool, hovered: Bool) {
        let rgb = RGB(hex: row.colorHex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        let dark = NSAppearance.currentDrawing().isDark
        let done = row.completed ? Draw.completedColors(rgb) : nil
        let fill = done?.fill ?? NSColor(rgb: rgb.mixed(with: dark ? .white : .black, amount: dark ? 0.08 : 0.12))
        let top = CGFloat(index) * GanttChartView.rowHeight + GanttChartView.groupBarTop
        let h = GanttChartView.groupBarHeight
        let r = NSRect(x: rect.minX, y: top, width: rect.width, height: h)
        let tab: CGFloat = 7
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.minY + 3))
        p.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX + 3, y: r.minY), radius: 3)
        p.line(to: NSPoint(x: r.maxX - 3, y: r.minY))
        p.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY + 3), radius: 3)
        if clippedRight {
            p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        } else {
            p.line(to: NSPoint(x: r.maxX, y: r.maxY + tab))
            p.line(to: NSPoint(x: r.maxX - tab, y: r.maxY))
        }
        if clippedLeft {
            p.line(to: NSPoint(x: r.minX, y: r.maxY))
        } else {
            p.line(to: NSPoint(x: r.minX + tab, y: r.maxY))
            p.line(to: NSPoint(x: r.minX, y: r.maxY + tab))
        }
        p.close()

        NSGraphicsContext.saveGraphicsState()
        if dragging || hovered {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dragging ? 0.28 : 0.16)
            shadow.shadowBlurRadius = dragging ? 6 : 3
            shadow.shadowOffset = NSSize(width: 0, height: dragging ? -2 : -1)
            shadow.set()
        }
        fill.setFill()
        p.fill()
        NSGraphicsContext.restoreGraphicsState()

        if selected {
            p.lineWidth = 1.5
            NSColor(rgb: rgb.mixed(with: dark ? .white : .black, amount: dark ? 0.5 : 0.4)).setStroke()
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: -2.5, dy: -2.5), xRadius: 5, yRadius: 5)
            ring.lineWidth = 1.5
            ring.stroke()
        }

        let textColor = done?.text ?? (rgb.prefersLightText ? NSColor.white : Theme.NS.barDarkText)
        let font = Theme.nsFont(11, bold: true)
        let title = row.completed ? "✓ " + row.title : row.title
        let titleW = Draw.width(title, font: font)
        let inner = r.insetBy(dx: tab + 3, dy: 0)
        let outsideRoom = documentWidth - r.maxX - 12
        if inner.width >= min(titleW, 60) {
            Draw.text(title, font: font, color: textColor, in: NSRect(x: inner.minX, y: r.minY + 1.5, width: inner.width, height: 14))
        } else if !clippedRight && outsideRoom > 40 {
            Draw.text(title, font: font, color: row.completed ? Theme.NS.secondaryText : Theme.NS.text,
                      in: NSRect(x: r.maxX + 8, y: r.minY + 1.5, width: min(titleW + 1, outsideRoom), height: 14))
        }
    }

    /// A milestone with its own row: a diamond at its date (and time), its title beside it.
    private func drawMilestone(_ row: GanttRow, center c: NSPoint, selected: Bool, dragging: Bool, hovered: Bool) {
        let rgb = RGB(hex: row.colorHex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        let size = GanttChartView.milestoneSize
        let d = Draw.diamond(center: c, size: size)
        NSGraphicsContext.saveGraphicsState()
        if dragging || hovered {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dragging ? 0.28 : 0.16)
            shadow.shadowBlurRadius = dragging ? 6 : 3
            shadow.shadowOffset = NSSize(width: 0, height: dragging ? -2 : -1)
            shadow.set()
        }
        (row.completed ? Draw.completedColors(rgb).fill : NSColor(rgb: rgb)).setFill()
        d.fill()
        NSGraphicsContext.restoreGraphicsState()
        if row.completed { Draw.check(center: c, size: 7, color: Draw.completedColors(rgb).text) }
        if selected {
            let ring = Draw.diamond(center: c, size: size + 7)
            ring.lineWidth = 1.5
            let dark = NSAppearance.currentDrawing().isDark
            NSColor(rgb: rgb.mixed(with: dark ? .white : .black, amount: dark ? 0.45 : 0.35)).setStroke()
            ring.stroke()
        }
        let font = Theme.nsFont(12, bold: true)
        let title = row.completed ? "✓ " + row.title : row.title
        let titleW = Draw.width(title, font: font)
        let room = documentWidth - c.x - size
        if room > 30 {
            Draw.text(title, font: font, color: row.completed ? Theme.NS.secondaryText : Theme.NS.text,
                      in: NSRect(x: c.x + size / 2 + 6, y: c.y - 8, width: min(titleW + 1, room), height: 16))
        }
    }

    /// A milestone on its task's bar: a small diamond with a light outline.
    private func drawMark(_ mark: GanttMark, center c: NSPoint, barHex: String, selected: Bool, dragging: Bool) {
        var rgb = RGB(hex: mark.colorHex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        if mark.colorHex.uppercased() == barHex.uppercased() { rgb = rgb.mixed(with: .black, amount: 0.35) }
        let size = GanttChartView.markSize
        let outline = Draw.diamond(center: c, size: size + 4)
        Theme.NS.canvas.setFill()
        outline.fill()
        NSGraphicsContext.saveGraphicsState()
        if dragging {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 5
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
        }
        (mark.completed ? Draw.completedColors(rgb).fill : NSColor(rgb: rgb)).setFill()
        Draw.diamond(center: c, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        if mark.completed { Draw.check(center: c, size: 5.5, color: Draw.completedColors(rgb).text) }
        if selected {
            let ring = Draw.diamond(center: c, size: size + 9)
            ring.lineWidth = 1.5
            Theme.NS.accent.setStroke()
            ring.stroke()
        }
    }

    /// Dependency arrows: thin right-angled lines with an arrowhead at the successor.
    private func drawLinks() {
        guard let chart else { return }
        let dark = NSAppearance.currentDrawing().isDark
        for link in chart.model.links {
            guard let pts = chart.linkPoints(link), pts.count >= 2 else { continue }
            let selected = link.id == chart.model.selectedLinkID
            let hovered = link.id == chart.hoveredLinkID
            let base = link.colorHex.flatMap { RGB(hex: $0) }.map { NSColor(rgb: $0) } ?? Theme.NS.linkLine
            let width = max(0.25, link.width)
            if selected || hovered {
                let halo = Draw.roundedPolyline(pts, radius: 5)
                halo.lineWidth = width + (selected ? 5 : 3.5)
                halo.lineCapStyle = .round
                halo.lineJoinStyle = .round
                Theme.NS.accent.withAlphaComponent(selected ? (dark ? 0.45 : 0.3) : 0.16).setStroke()
                halo.stroke()
            }
            let path = Draw.roundedPolyline(Array(pts.dropLast()) + [arrowBase(pts, width: width)], radius: 5)
            path.lineWidth = width
            path.lineCapStyle = .butt
            path.lineJoinStyle = .round
            base.setStroke()
            path.stroke()
            base.setFill()
            Draw.arrowhead(tip: pts[pts.count - 1], from: pts[pts.count - 2], width: width).fill()
        }
    }

    /// Where the line stops, so it doesn't poke through the arrowhead's tip.
    private func arrowBase(_ pts: [NSPoint], width: CGFloat) -> NSPoint {
        let tip = pts[pts.count - 1], prev = pts[pts.count - 2]
        let len = hypot(tip.x - prev.x, tip.y - prev.y)
        guard len > 0 else { return tip }
        let back = min(len, 4 + width)
        return NSPoint(x: tip.x - (tip.x - prev.x) / len * back, y: tip.y - (tip.y - prev.y) / len * back)
    }

    /// Small round handles just outside the hovered item: drag one to another item to add an arrow.
    private func drawHandles(_ h: HoverItem) {
        guard let chart else { return }
        for handle in chart.handles(for: h) {
            let c = handle.center
            let r = NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
            Theme.NS.canvas.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: -1.5, dy: -1.5)).fill()
            Theme.NS.accent.setFill()
            NSBezierPath(ovalIn: r).fill()
            // A small white arrow pointing away from the item.
            let dx = handle.side.dx, dy = handle.side.dy
            func at(_ along: CGFloat, _ across: CGFloat) -> NSPoint {
                NSPoint(x: c.x + along * dx - across * dy, y: c.y + along * dy + across * dx)
            }
            let a = NSBezierPath()
            a.move(to: at(-2.8, 0))
            a.line(to: at(2.6, 0))
            a.move(to: at(0.2, -2.6))
            a.line(to: at(2.8, 0))
            a.line(to: at(0.2, 2.6))
            a.lineWidth = 1.4
            a.lineCapStyle = .round
            a.lineJoinStyle = .round
            NSColor.white.setStroke()
            a.stroke()
        }
    }

    /// The arrow being drawn: dashed from the handle to the pointer, and the route it will take
    /// once it's over an item it can join.
    private func drawLinkDraft(_ draft: LinkDraft) {
        guard let chart else { return }
        Theme.NS.accent.setStroke()
        Theme.NS.accent.setFill()
        if let t = draft.target, let ra = chart.itemFrame(draft.fromID), let rb = chart.itemFrame(t.id) {
            let pts = chart.bestRoute(from: ra, draft.fromSide, to: rb, t.side)
            let line = Draw.roundedPolyline(Array(pts.dropLast()) + [arrowBase(pts, width: 1.5)], radius: 5)
            line.lineWidth = 1.5
            line.stroke()
            Draw.arrowhead(tip: pts[pts.count - 1], from: pts[pts.count - 2], width: 1.5).fill()
        } else {
            let line = NSBezierPath()
            line.move(to: draft.origin)
            line.line(to: draft.current)
            line.lineWidth = 1.5
            line.setLineDash([4, 3], count: 2, phase: 0)
            line.stroke()
            Draw.arrowhead(tip: draft.current, from: draft.origin, width: 1.5).fill()
        }
        NSBezierPath(ovalIn: NSRect(x: draft.origin.x - 3.5, y: draft.origin.y - 3.5, width: 7, height: 7)).fill()
        if let t = draft.target, let rowID = chart.model.anchorRow[t.id],
           let i = chart.model.rows.firstIndex(where: { $0.id == rowID }) {
            let row = chart.model.rows[i]
            var outline: NSBezierPath
            if let mark = row.marks.first(where: { $0.id == t.id }) {
                outline = Draw.diamond(center: chart.markCenter(index: i, mark: mark), size: GanttChartView.markSize + 9)
            } else if row.kind == .milestone {
                outline = Draw.diamond(center: chart.milestoneCenter(index: i, row: row), size: GanttChartView.milestoneSize + 8)
            } else {
                outline = NSBezierPath(roundedRect: chart.fullBarRect(index: i, row: row).insetBy(dx: -3, dy: -3), xRadius: 7, yRadius: 7)
            }
            outline.lineWidth = 2
            Theme.NS.accent.setStroke()
            outline.stroke()
            let label = "\(DependencyType(exit: draft.fromSide, entry: t.side).title) · into its \(t.side.word)"
            let font = Theme.nsFont(11)
            let w = Draw.width(label, font: font) + 16
            let r = NSRect(x: t.point.x - w / 2, y: t.point.y - 36, width: w, height: 20)
            Theme.NS.bubbleFill.setFill()
            Draw.roundedRect(r, radius: 6).fill()
            Draw.text(label, font: font, color: Theme.NS.bubbleText, in: NSRect(x: r.minX + 8, y: r.minY + 3.5, width: w - 16, height: 14))
        }
    }

    /// A thin line at the current time in the Today column.
    private func drawNowLine() {
        guard let chart, let minute = chart.model.nowMinute, chart.model.window.contains(chart.model.today) else { return }
        let x = chart.milestoneX(day: chart.model.today, minute: minute)
        let visible = chart.visibleDocumentRect
        Theme.NS.todayAccent.setFill()
        NSRect(x: x - 0.75, y: visible.minY, width: 1.5, height: visible.height).fill()
    }

    private func drawDragBubble(_ d: DragSession, rowIndex: Int) {
        guard let chart else { return }
        let row = chart.model.rows[rowIndex]
        let anchorRect: NSRect
        if let mark = row.marks.first(where: { $0.id == d.id }) {
            let c = chart.markCenter(index: rowIndex, mark: mark)
            anchorRect = NSRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)
        } else if row.kind == .milestone {
            let c = chart.milestoneCenter(index: rowIndex, row: row)
            anchorRect = NSRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)
        } else {
            guard let bar = chart.barRect(index: rowIndex, start: d.start, end: d.end) else { return }
            anchorRect = bar.rect
        }
        let single = d.start == d.end && (row.kind == .milestone || row.id != d.id)
        let text = single ? DayFormat.weekdayShortDate(d.start)
            : "\(DayFormat.range(d.start, d.end, referenceYear: chart.model.today.year)) · \(DayFormat.dayCount(d.end - d.start + 1))"
        let font = Theme.nsFont(11)
        let w = Draw.width(text, font: font) + 16, h: CGFloat = 20
        let visible = chart.visibleDocumentRect
        var x = anchorRect.midX - w / 2
        x = max(visible.minX + 4, min(x, visible.maxX - w - 4))
        var y = anchorRect.minY - h - 4
        if y < visible.minY + 2 { y = anchorRect.maxY + 4 }
        let r = NSRect(x: x, y: y, width: w, height: h)
        Theme.NS.bubbleFill.setFill()
        Draw.roundedRect(r, radius: 6).fill()
        Draw.text(text, font: font, color: Theme.NS.bubbleText, in: NSRect(x: r.minX + 8, y: r.minY + 3.5, width: w - 16, height: 14))
    }
}
