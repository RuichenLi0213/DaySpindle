import AppKit
import Foundation
import os

let appLog = Logger(subsystem: "org.dayspindle.DaySpindle", category: "app")

// MARK: - Persistence

/// Reads and writes a workspace's data file, `dayspindle-data.json`, in the workspace folder.
/// Reads and writes are coordinated, so a folder in iCloud Drive (or another synced folder)
/// is downloaded first and never written halfway.
final class Persistence {
    static let fileName = "dayspindle-data.json"

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    var backupURL: URL { directory.appendingPathComponent("dayspindle-data.previous.json") }
    /// The bytes last read from or written to the file, to notice changes made elsewhere.
    private(set) var lastKnownData: Data?

    init(directory: URL) {
        self.directory = directory
    }

    /// Where DaySpindle 2.0 and earlier kept their data (one file for the whole app): the 2.0 on
    /// GitHub used a folder named after its bundle identifier, earlier builds a "DaySpindle" folder.
    static var legacyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let candidates = [Bundle.main.bundleIdentifier, "DaySpindle"].compactMap { $0 }
            .map { base.appendingPathComponent($0, isDirectory: true).appendingPathComponent(fileName) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[candidates.count - 1]
    }

    static func hasData(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
    }

    enum LoadResult {
        case loaded(AppData)
        case missing
        case unreadable(Error)
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in
            result = Result { try Data(contentsOf: u) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func decode(_ raw: Data) throws -> AppData { try JSONDecoder().decode(AppData.self, from: raw) }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let raw = try coordinatedRead(fileURL)
            lastKnownData = raw
            return .loaded(try Self.decode(raw))
        } catch {
            return .unreadable(error)
        }
    }

    /// The file's contents when they differ from what this app last read or wrote.
    func changedOnDisk() -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let raw = try? coordinatedRead(fileURL), raw != lastKnownData else { return nil }
        return raw
    }

    func markKnown(_ raw: Data) { lastKnownData = raw }

    /// Keeps a copy of the last file from a previous session.
    func backUpExistingFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: fileURL, to: backupURL)
    }

    /// Keeps a copy of the file under another name (before an upgrade), unless one exists.
    func keepCopy(named name: String) {
        let dest = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.copyItem(at: fileURL, to: dest)
    }

    /// Moves an unreadable file aside so it is never silently overwritten.
    func quarantineUnreadableFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = directory.appendingPathComponent("dayspindle-data.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: dest)
    }

    func save(_ data: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        guard encoded != lastKnownData else { return }
        // Never recreate a workspace folder that was moved or deleted while the app was open.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The workspace folder isn't there any more."])
        }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { u in
            do { try encoded.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
        lastKnownData = encoded
    }
}

// MARK: - Clock

/// Supplies "now".
///
/// For testing midnight rollover, launch with `-DaySpindleSimulatedNow 2026-11-09T23:59:50`;
/// the clock then starts at that local time and advances in real time.
final class Clock {
    let offset: TimeInterval

    init(defaults: UserDefaults = .standard) {
        if let text = defaults.string(forKey: "DaySpindleSimulatedNow"), let date = Clock.parseLocal(text) {
            offset = date.timeIntervalSinceNow
        } else {
            offset = 0
        }
    }

    var isSimulated: Bool { offset != 0 }
    func now() -> Date { Date().addingTimeInterval(offset) }
    func today(in tz: TimeZone) -> Day { Day.from(now(), timeZone: tz) }

    /// Minutes since midnight in `tz`.
    func minuteOfDay(in tz: TimeZone) -> Int {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        let p = c.dateComponents([.hour, .minute], from: now())
        return (p.hour ?? 0) * 60 + (p.minute ?? 0)
    }

    static func parseLocal(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: text)
    }
}

// MARK: - Time zone setting

/// The time zone DaySpindle shows times in. Like Apple Calendar, it's your Mac's own time zone
/// (and follows it when you travel) unless you choose another one.
@MainActor
final class TimeZoneSettings: ObservableObject {
    static let shared = TimeZoneSettings()
    static let defaultsKey = "TimeZoneOverride"
    static let changed = Notification.Name("DaySpindleTimeZoneChanged")

    /// A chosen time zone identifier, or nil for the Mac's own time zone.
    @Published var overrideID: String? {
        didSet {
            guard overrideID != oldValue else { return }
            if let id = overrideID { UserDefaults.standard.set(id, forKey: Self.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.defaultsKey) }
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    private init() {
        overrideID = Zones.zone(UserDefaults.standard.string(forKey: Self.defaultsKey))?.identifier
    }

    /// The Mac's own time zone (`-DaySpindleSimulatedTimeZone Asia/Tokyo` pretends another one, for testing).
    var system: TimeZone {
        Zones.zone(UserDefaults.standard.string(forKey: "DaySpindleSimulatedTimeZone")) ?? TimeZone.current
    }

    var current: TimeZone { Zones.zone(overrideID) ?? system }

    func systemChanged() {
        NSTimeZone.resetSystemTimeZone()
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

// MARK: - Drafts

/// A whole item at once (used to create items from scripts and the self-check).
struct TaskDraft {
    var taskID: UUID?
    var title: String
    var start: Day
    var end: Day
    var categoryID: UUID
    var tags: [String]
    var parentID: UUID? = nil
    /// The task's own bar color, or nil for its category's color.
    var colorHex: String? = nil
    var notes = ""
    var location = ""
    /// As typed; checked and normalized on save.
    var startTime = ""
    var endTime = ""
    var kind: ItemKind = .task
}

struct CategoryDraft {
    var categoryID: UUID?
    var name: String
    var colorHex: String
    var notes = ""
}

struct TagDraft {
    var original: String
    var name: String
}

struct Confirmation {
    var title: String
    /// A task title inside `title`, rendered in bold.
    var emphasis: String? = nil
    var message: String
    var confirmTitle: String
    var action: () -> Void
}

enum ActiveSheet: Identifiable {
    case category(UUID, CategoryDraft)
    case tag(UUID, TagDraft)
    case confirm(UUID, Confirmation)
    case todayColor(UUID, String)
    /// The note of a category: (sheet id, category id, current text).
    case categoryNote(UUID, UUID, String)

    var id: UUID {
        switch self {
        case .category(let id, _), .tag(let id, _), .confirm(let id, _), .todayColor(let id, _),
             .categoryNote(let id, _, _): return id
        }
    }
}

struct ScrollRequest: Equatable {
    var token: Int
    var day: Day
}

// MARK: - Store

/// One workspace: its items, categories, tags and arrows, and how it's shown.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var content: AppContent
    @Published private(set) var window: DateWindow
    @Published private(set) var today: Day
    /// Minutes since midnight, for the "now" line.
    @Published private(set) var nowMinute: Int
    /// The time zone everything is shown in.
    @Published private(set) var viewZoneID: String

    /// Parent tasks whose subtasks are hidden. Saved with the data, not part of undo.
    @Published private(set) var collapsedIDs: Set<UUID> = []

    /// Categories whose sidebar checkbox is off, like calendars in Calendar. Saved with the data.
    @Published private(set) var hiddenCategoryIDs: Set<UUID> = []
    /// Tag filter (not saved; the app opens with no tag filter).
    @Published var selectedTagKeys: Set<String> = []
    /// Showing the Archive (completed items) instead of the main list.
    @Published var showingArchive = false

    /// First day of the week for the week bar and calendars: 0 = Sunday … 6 = Saturday. A preference.
    @Published private(set) var firstWeekday: Int = {
        let v = UserDefaults.standard.object(forKey: "FirstWeekday") as? Int ?? 0
        return (0...6).contains(v) ? v : 0
    }()
    /// The Today spindle color (a preference; see `TodayStyle`).
    @Published private(set) var todayColorHex: String = TodayStyle.hex

    /// The selected item (group, task or milestone). Selecting one clears the arrow selection.
    @Published var selectedTaskID: UUID? {
        didSet { if selectedTaskID != nil && selectedLinkID != nil { selectedLinkID = nil } }
    }
    /// The selected dependency arrow.
    @Published var selectedLinkID: UUID? {
        didSet { if selectedLinkID != nil && selectedTaskID != nil { selectedTaskID = nil } }
    }
    /// The details pane on the right.
    @Published var inspectorVisible: Bool {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: "InspectorVisible") }
    }
    /// A new item whose title field should take the focus in the details pane.
    @Published var titleFocusID: UUID?
    @Published var activeSheet: ActiveSheet?
    @Published private(set) var scrollRequest: ScrollRequest?
    @Published private(set) var saveError: String?
    /// A one-time message (after an upgrade or a reload), shown above the chart.
    @Published var notice: String?

    /// This workspace's own undo history. Each change is grouped explicitly, so one Undo
    /// always reverts exactly one change.
    let undo = UndoManager()
    var undoManager: UndoManager? { undo }
    let persistence: Persistence
    let clock: Clock
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    var workspaceURL: URL { persistence.directory }
    var workspaceName: String { workspaceURL.lastPathComponent }

    init(directory: URL, clock: Clock = Clock()) {
        persistence = Persistence(directory: directory)
        self.clock = clock
        undo.groupsByEvent = false
        let zone = TimeZoneSettings.shared.current
        viewZoneID = zone.identifier
        let today = clock.today(in: zone)
        self.today = today
        nowMinute = clock.minuteOfDay(in: zone)
        inspectorVisible = UserDefaults.standard.object(forKey: "InspectorVisible") as? Bool ?? true

        switch persistence.load() {
        case .loaded(let data):
            content = data.content
            window = data.window
            collapsedIDs = Set(data.collapsed ?? [])
            hiddenCategoryIDs = Set(data.hiddenCategories ?? [])
            if data.version < AppData.currentVersion {
                persistence.keepCopy(named: "dayspindle-data.v\(data.version)-backup.json")
                let parents = content.tasks.filter { content.hasStructuralChildren($0.id) }.count
                let before = content.tasks.count
                content.migrateParentsToGroups()
                content.assignTimeZone(TimeZoneSettings.shared.system.identifier)
                let kept = content.tasks.count - before
                if parents > 0 {
                    notice = "Upgraded for DaySpindle 2.1: \(parents == 1 ? "1 task with subtasks is now a group" : "\(parents) tasks with subtasks are now groups")"
                        + (kept > 0 ? ", and \(kept == 1 ? "its own dates are" : "their own dates are") kept as \(kept == 1 ? "a task" : "tasks") of the same name inside." : ".")
                }
                appLog.notice("Upgraded data from version \(data.version): \(parents) groups, \(kept) tasks added for their own dates")
            } else {
                persistence.backUpExistingFile()
            }
            appLog.notice("Loaded \(data.content.tasks.count) items from \(self.persistence.fileURL.path, privacy: .public)")
        case .missing:
            content = .starter()
            window = DateWindow.around(today)
            appLog.notice("New workspace at \(self.persistence.fileURL.path, privacy: .public)")
        case .unreadable(let error):
            persistence.quarantineUnreadableFile()
            content = .starter()
            window = DateWindow.around(today)
            saveError = "The data file could not be read and was set aside: \(error.localizedDescription)"
            appLog.error("Unreadable data file: \(error.localizedDescription, privacy: .public)")
        }
        if content.categories.isEmpty { content.categories = AppContent.starter().categories }
        content.repairHierarchy()
        collapsedIDs = collapsedIDs.intersection(content.tasks.map(\.id))
        hiddenCategoryIDs = hiddenCategoryIDs.intersection(content.categories.map(\.id))
        normalizeWindow()
        persist()
        startClock()
    }

    // MARK: Lookups

    var categories: [Category] { content.categories }
    var tags: [String] { content.tags }
    var tasks: [TaskItem] { content.tasks }
    var dependencies: [Dependency] { content.dependencies }
    var viewTimeZone: TimeZone { Zones.zone(viewZoneID) ?? TimeZone.current }

    func category(_ id: UUID) -> Category? { content.categories.first { $0.id == id } }
    /// The item as stored.
    func task(_ id: UUID) -> TaskItem? { content.item(id) }
    /// The item as shown: a timed item's dates and times converted to the time zone being viewed.
    func shown(_ id: UUID) -> TaskItem? { task(id)?.displayed(in: viewTimeZone) }
    func kind(of id: UUID) -> ItemKind { task(id).map(content.effectiveKind) ?? .task }
    func isMark(_ id: UUID) -> Bool { task(id).map(content.isMark) ?? false }
    /// The item's bar color: its own color if set, otherwise its category's.
    func colorHex(for task: TaskItem) -> String { task.colorHex ?? category(task.categoryID)?.colorHex ?? Palette.colors[11].hex }

    /// First and last day as shown. A group spans everything inside it; an empty group has none.
    func displayDates(_ id: UUID) -> (start: Day, end: Day)? {
        guard let t = task(id) else { return nil }
        if content.effectiveKind(t) != .group {
            let s = t.displayed(in: viewTimeZone)
            return (s.start, s.end)
        }
        let inside = content.descendants(of: id).compactMap { task($0) }.filter { content.effectiveKind($0) != .group }
        let shownInside = inside.map { $0.displayed(in: viewTimeZone) }
        guard let s = shownInside.map(\.start).min(), let e = shownInside.map(\.end).max() else { return nil }
        return (s, e)
    }

    func taskCount(category id: UUID) -> Int { content.tasks.filter { $0.categoryID == id }.count }
    func taskCount(tag: String) -> Int { content.tasks.filter { $0.hasTag(key: tag.lowercased()) }.count }

    /// Milestones attached to a task, in date order.
    func marks(of id: UUID) -> [TaskItem] {
        guard let t = task(id), content.effectiveKind(t) == .task else { return [] }
        return content.tasks.filter { $0.parentID == id && $0.storedKind == .milestone }
            .map { $0.displayed(in: viewTimeZone) }
            .sorted { ($0.start, $0.startTime ?? "") < ($1.start, $1.startTime ?? "") }
    }

    /// Items directly inside a group (subtasks, subgroups and milestones), in order.
    func children(of id: UUID) -> [TaskItem] { content.tasks.filter { $0.parentID == id } }

    // MARK: Filters

    var filtersActive: Bool { !hiddenCategoryIDs.isEmpty || !selectedTagKeys.isEmpty }

    // MARK: Archive

    /// Items in the Archive: completed items and everything inside them. A milestone drawn on a task's
    /// bar stays with its task (on the bar), so it's in the Archive only when its task is.
    var archivedIDs: Set<UUID> {
        let byID = Dictionary(content.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var memo: [UUID: Bool] = [:]
        func completedHereOrAbove(_ id: UUID?, _ hops: Int) -> Bool {
            guard let id, hops < 10_000, let t = byID[id] else { return false }
            if let m = memo[id] { return m }
            let r = t.isCompleted || completedHereOrAbove(t.parentID, hops + 1)
            memo[id] = r
            return r
        }
        var out = Set<UUID>()
        for t in content.tasks {
            let archived = content.isMark(t) ? completedHereOrAbove(t.parentID, 0) : completedHereOrAbove(t.id, 0)
            if archived { out.insert(t.id) }
        }
        return out
    }

    /// How many items (not counting milestones on bars) are in the Archive, and outside it.
    var archiveCount: Int { let a = archivedIDs; return content.tasks.filter { a.contains($0.id) && !content.isMark($0) }.count }
    var mainCount: Int { let a = archivedIDs; return content.tasks.filter { !a.contains($0.id) && !content.isMark($0) }.count }

    func showArchive(_ on: Bool) {
        guard showingArchive != on else { return }
        showingArchive = on
        selectedTaskID = nil
    }

    /// Shows the list (main or Archive) that an item is in.
    private func showList(for id: UUID) {
        let archived = archivedIDs.contains(id)
        if task(id).map(content.isMark) == true {
            // A milestone on a bar is shown where its task is.
            if let p = task(id)?.parentID { showingArchive = archivedIDs.contains(p) }
        } else if archived != showingArchive {
            showingArchive = archived
        }
    }

    /// A task shows when its category is checked and it has every selected tag.
    func matchesFilters(_ t: TaskItem) -> Bool {
        if hiddenCategoryIDs.contains(t.categoryID) { return false }
        if !selectedTagKeys.isEmpty {
            let keys = Set(t.tags.map { $0.lowercased() })
            if !selectedTagKeys.isSubset(of: keys) { return false }
        }
        return true
    }

    var visibleTasks: [TaskItem] { content.tasks.filter(matchesFilters) }

    /// Shows every category and clears the tag filter.
    func clearFilters() {
        selectedTagKeys = []
        setHiddenCategories([])
        showingArchive = false
    }

    func isCategoryShown(_ id: UUID) -> Bool { !hiddenCategoryIDs.contains(id) }

    /// The categories whose checkbox is on.
    var shownCategories: [Category] { content.categories.filter { isCategoryShown($0.id) } }

    /// Click on a category: turns its checkbox on or off; any combination can be on.
    func toggleCategory(_ id: UUID) {
        var hidden = hiddenCategoryIDs
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        setHiddenCategories(hidden)
    }

    /// ⌘-click on a category: shows only that category (or everything again if it
    /// was already the only one shown).
    func showOnlyCategory(_ id: UUID) {
        let others = Set(content.categories.map(\.id)).subtracting([id])
        setHiddenCategories(hiddenCategoryIDs == others ? [] : others)
    }

    func showAllCategories() { setHiddenCategories([]) }

    private func setHiddenCategories(_ hidden: Set<UUID>) {
        guard hidden != hiddenCategoryIDs else { return }
        hiddenCategoryIDs = hidden
        if let sel = selectedTaskID, let t = task(sel), hidden.contains(t.categoryID) { selectedTaskID = nil }
        persist()
    }

    func selectTag(_ tag: String, additive: Bool) {
        let key = tag.lowercased()
        if additive {
            if selectedTagKeys.contains(key) { selectedTagKeys.remove(key) } else { selectedTagKeys.insert(key) }
        } else {
            selectedTagKeys = selectedTagKeys == [key] ? [] : [key]
        }
    }

    private func pruneFilters() {
        let ids = Set(content.categories.map(\.id))
        hiddenCategoryIDs = hiddenCategoryIDs.intersection(ids)
        let keys = Set(content.tags.map { $0.lowercased() })
        selectedTagKeys = selectedTagKeys.intersection(keys)
        if let sel = selectedTaskID, task(sel) == nil { selectedTaskID = nil }
        if let link = selectedLinkID, !content.dependencies.contains(where: { $0.id == link }) { selectedLinkID = nil }
    }

    // MARK: Visible window

    func setWindowStart(_ day: Day) {
        var w = window
        if day > w.end {
            let n = w.dayCount
            w = DateWindow(start: day, end: day + (n - 1))
        } else {
            w.start = day
        }
        setWindow(w)
    }

    func setWindowEnd(_ day: Day) {
        setWindow(DateWindow(start: window.start, end: max(day, window.start)))
    }

    /// The preset that matches the visible range exactly, if any.
    var currentPreset: WindowPreset? { WindowPreset.matching(window) }

    /// Applies a preset length, keeping the first visible day.
    func applyPreset(_ preset: WindowPreset) {
        setWindow(preset.window(startingAt: window.start))
    }

    /// Steps back or forward by one window. Month-based presets step by whole months.
    func shiftWindow(by direction: Int) {
        if let p = currentPreset, case .months(let months) = p.length {
            setWindow(p.window(startingAt: window.start.addingMonths(months * direction)))
            return
        }
        let n = window.dayCount * direction
        setWindow(DateWindow(start: window.start + n, end: window.end + n))
    }

    /// Moves the visible range by whole days, keeping its time scale (sideways scrolling).
    func shiftWindow(days: Int) {
        guard days != 0 else { return }
        if let p = currentPreset {
            setWindow(p.window(startingAt: window.start + days))
        } else {
            setWindow(DateWindow(start: window.start + days, end: window.end + days))
        }
    }

    /// Brings today into view, keeping the window length (or preset).
    func goToToday() {
        refreshToday()
        let n = window.dayCount
        let start = today - (n - 1) / 4
        if let p = currentPreset {
            setWindow(p.window(startingAt: start))
        } else {
            setWindow(DateWindow(start: start, end: start + (n - 1)))
        }
        requestScroll(to: today)
    }

    /// Shifts the window (same length) so an item outside it becomes visible.
    func reveal(_ id: UUID) {
        showList(for: id)
        guard let d = displayDates(id) else { selectedTaskID = id; return }
        selectedTaskID = id
        if d.end < window.start || d.start > window.end {
            let n = window.dayCount
            let start = d.start - min(2, (n - 1) / 4)
            setWindow(DateWindow(start: start, end: start + (n - 1)))
        }
        requestScroll(to: max(d.start, window.start))
    }

    func setWindow(_ w: DateWindow) {
        var w = w
        if w.end < w.start { w.end = w.start }
        if w.dayCount > DateWindow.maxDays { w.end = w.start + (DateWindow.maxDays - 1) }
        guard w != window else { return }
        window = w
        persist()
    }

    private func normalizeWindow() {
        if window.end < window.start { window.end = window.start }
        if window.dayCount > DateWindow.maxDays { window.end = window.start + (DateWindow.maxDays - 1) }
    }

    private var scrollToken = 0
    private func requestScroll(to day: Day) {
        scrollToken += 1
        scrollRequest = ScrollRequest(token: scrollToken, day: day)
    }

    // MARK: Today and time zone

    private func startClock() {
        let interval: TimeInterval = clock.isSimulated ? 1 : 15
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshToday() }
        }
        t.tolerance = clock.isSimulated ? 0.1 : 2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let nc = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshToday() }
        }
        observers.append(nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: TimeZoneSettings.changed, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: refresh))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh))
    }

    /// Stops the clock and notifications (when the workspace's tab is closed).
    func stop() {
        timer?.invalidate()
        timer = nil
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers = []
    }

    func refreshToday() {
        let zone = TimeZoneSettings.shared.current
        if zone.identifier != viewZoneID {
            appLog.notice("Showing times in \(zone.identifier, privacy: .public)")
            viewZoneID = zone.identifier
        }
        let t = clock.today(in: zone)
        if t != today {
            appLog.notice("Day changed to \(t.iso, privacy: .public)")
            today = t
        }
        let m = clock.minuteOfDay(in: zone)
        if m != nowMinute { nowMinute = m }
    }

    // MARK: Saving & undo

    func persist() {
        do {
            let collapsed = content.tasks.map(\.id).filter { collapsedIDs.contains($0) }
            let hidden = content.categories.map(\.id).filter { hiddenCategoryIDs.contains($0) }
            try persistence.save(AppData(version: AppData.currentVersion, content: content, window: window,
                                         collapsed: collapsed, hiddenCategories: hidden))
            if saveError != nil { saveError = nil }
        } catch {
            saveError = "Could not save to \(persistence.fileURL.path): \(error.localizedDescription)"
            appLog.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads the file again when another app or another computer (through iCloud Drive, for
    /// example) changed it since DaySpindle last read or saved it.
    func reloadIfChangedOnDisk() {
        guard let raw = persistence.changedOnDisk(), var data = try? Persistence.decode(raw) else { return }
        persistence.markKnown(raw)
        if data.version < AppData.currentVersion {
            data.content.migrateParentsToGroups()
            data.content.assignTimeZone(TimeZoneSettings.shared.system.identifier)
        }
        data.content.repairHierarchy()
        content = data.content
        window = data.window
        collapsedIDs = Set(data.collapsed ?? []).intersection(content.tasks.map(\.id))
        hiddenCategoryIDs = Set(data.hiddenCategories ?? []).intersection(content.categories.map(\.id))
        pruneFilters()
        undo.removeAllActions()
        notice = "This workspace changed on disk and was loaded again."
        appLog.notice("Reloaded \(self.persistence.fileURL.path, privacy: .public) after an outside change")
    }

    /// Changes in a row with the same key within a couple of seconds (dragging a color, say)
    /// become one undo step.
    private var coalescing: (key: String, time: Date)?

    private func mutate(_ actionName: String, coalesceKey: String? = nil, _ change: (inout AppContent) -> Void) {
        var next = content
        change(&next)
        next.repairHierarchy()
        guard next != content else { return }
        if let key = coalesceKey, let c = coalescing, c.key == key, Date().timeIntervalSince(c.time) < 2 {
            content = next
            afterChange()
            coalescing = (key, Date())
            return
        }
        apply(next, actionName: actionName)
        coalescing = coalesceKey.map { ($0, Date()) }
    }

    private func apply(_ next: AppContent, actionName: String) {
        let previous = content
        content = next
        coalescing = nil
        afterChange()
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.apply(previous, actionName: actionName) }
        }
        undo.setActionName(actionName)
        undo.endUndoGrouping()
    }

    private func afterChange() {
        pruneFilters()
        collapsedIDs = collapsedIDs.intersection(content.tasks.map(\.id))
        persist()
    }

    // MARK: Tags

    /// Returns the stored spelling of a tag that matches case-insensitively, or the input.
    private func canonicalTag(_ name: String, in content: AppContent) -> String {
        content.tags.first { $0.lowercased() == name.lowercased() } ?? name
    }

    private func register(tags: [String], into content: inout AppContent) -> [String] {
        var result: [String] = []
        for raw in tags {
            guard let normalized = Tags.normalize(raw) else { continue }
            let canonical = canonicalTag(normalized, in: content)
            if !content.tags.contains(canonical) { content.tags.append(canonical) }
            if !result.contains(where: { $0.lowercased() == canonical.lowercased() }) { result.append(canonical) }
        }
        content.tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return result
    }

    func beginRenameTag(_ tag: String) {
        activeSheet = .tag(UUID(), TagDraft(original: tag, name: tag))
    }

    /// Renames a tag everywhere; renaming onto an existing tag merges them.
    @discardableResult
    func saveTagDraft(_ draft: TagDraft) -> String? {
        guard let newName = Tags.normalize(draft.name) else { return "Enter a tag name." }
        let oldKey = draft.original.lowercased()
        mutate("Rename Tag") { c in
            let target = c.tags.first { $0.lowercased() == newName.lowercased() && $0.lowercased() != oldKey } ?? newName
            c.tags.removeAll { $0.lowercased() == oldKey || $0.lowercased() == target.lowercased() }
            c.tags.append(target)
            c.tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for i in c.tasks.indices {
                var seen = Set<String>()
                c.tasks[i].tags = c.tasks[i].tags
                    .map { $0.lowercased() == oldKey ? target : $0 }
                    .filter { seen.insert($0.lowercased()).inserted }
            }
        }
        if selectedTagKeys.remove(oldKey) != nil { selectedTagKeys.insert(newName.lowercased()) }
        activeSheet = nil
        return nil
    }

    func requestDeleteTag(_ tag: String) {
        let n = taskCount(tag: tag)
        let message = n == 0 ? "No items use this tag."
            : "The tag will be removed from \(n == 1 ? "1 item" : "\(n) items"). The items themselves are kept."
        activeSheet = .confirm(UUID(), Confirmation(
            title: "Delete the tag #\(tag)?", message: message, confirmTitle: "Delete Tag",
            action: { [weak self] in self?.deleteTag(tag) }))
    }

    func deleteTag(_ tag: String) {
        let key = tag.lowercased()
        mutate("Delete Tag") { c in
            c.tags.removeAll { $0.lowercased() == key }
            for i in c.tasks.indices { c.tasks[i].tags.removeAll { $0.lowercased() == key } }
        }
    }

    // MARK: Creating items

    /// Creates a group, task or milestone, selects it and shows it in the details pane with its
    /// title ready to type. A milestone created inside a task marks a key moment of that task.
    @discardableResult
    func newItem(_ kind: ItemKind, parentID: UUID? = nil, start: Day? = nil, title: String? = nil) -> UUID? {
        // New items aren't completed: show the main list, unless it goes inside an archived item.
        if showingArchive && !(parentID.map { archivedIDs.contains($0) } ?? false) { showingArchive = false }
        var parent = parentID.flatMap { task($0) }
        // Nothing goes inside a milestone: use the milestone's own parent.
        while let p = parent, p.storedKind == .milestone { parent = p.parentID.flatMap { task($0) } }
        let fallback = window.contains(today) ? today : window.start
        let parentDates = parent.flatMap { displayDates($0.id) }
        let s: Day, e: Day
        switch kind {
        case .milestone:
            s = start ?? parentDates?.end ?? fallback
            e = s
        case .task, .group:
            s = start ?? parentDates?.start ?? fallback
            e = start == nil ? (parentDates?.end ?? s) : s
        }
        let categoryID = parent?.categoryID ?? shownCategories.first?.id ?? content.categories[0].id
        let prefillTags = content.tags.filter { selectedTagKeys.contains($0.lowercased()) }
        let defaultTitle: String
        switch kind {
        case .task: defaultTitle = parent == nil ? "New Task" : "New Subtask"
        case .milestone: defaultTitle = "New Milestone"
        case .group: defaultTitle = "New Group"
        }
        let id = UUID()
        let item = TaskItem(id: id, title: title ?? defaultTitle, start: s, end: e, categoryID: categoryID,
                            tags: prefillTags, parentID: parent?.id, kind: kind)
        mutate("New \(kind == .task && parent != nil ? "Subtask" : kind.title)") { c in c.tasks.append(item) }
        expandAncestors(of: id)
        selectedTaskID = id
        inspectorVisible = true
        titleFocusID = id
        reveal(id)
        return id
    }

    func beginNewTask(start: Day? = nil) { newItem(.task, start: start) }
    func beginNewSubtask(of parentID: UUID) { newItem(.task, parentID: parentID) }
    func beginNewMilestone(in parentID: UUID? = nil) { newItem(.milestone, parentID: parentID) }
    func beginNewGroup() { newItem(.group) }

    /// Shows an item in the details pane.
    func openInspector(_ id: UUID) {
        showList(for: id)
        selectedTaskID = id
        inspectorVisible = true
    }

    func beginEdit(_ id: UUID) { openInspector(id) }

    func openLink(_ id: UUID) {
        selectedLinkID = id
        inspectorVisible = true
    }

    /// Items `taskID` may be placed under: groups and tasks (never milestones), except itself
    /// and anything inside it, in outline order.
    func parentCandidates(for taskID: UUID?) -> [(task: TaskItem, depth: Int)] {
        let excluded = taskID.map { content.descendants(of: $0).union([$0]) } ?? []
        return content.outline().filter { !excluded.contains($0.task.id) && $0.task.storedKind != .milestone }
    }

    /// Creates or replaces a whole item. Returns an error message, or nil on success.
    @discardableResult
    func saveTaskDraft(_ draft: TaskDraft) -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "Enter a title." }
        guard draft.end >= draft.start else { return "The end date can't be before the start date." }
        guard category(draft.categoryID) != nil else { return "Choose a category." }
        var customColor: String?
        if let raw = draft.colorHex, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let h = RGB.normalizedHex(raw) else { return "Enter the bar color as a hex value, like #2F6FEB." }
            customColor = h
        }
        let times: (String?, String?)
        switch parseTimes(draft.startTime, draft.endTime, start: draft.start, end: draft.end, milestone: draft.kind == .milestone) {
        case .failure(let message): return message.text
        case .success(let t): times = t
        }
        let notes = Store.trimmed(draft.notes)
        let location = Store.trimmed(draft.location)
        if let pid = draft.parentID {
            guard task(pid) != nil else { return "The parent no longer exists." }
            if let id = draft.taskID, pid == id || content.descendants(of: id).contains(pid) {
                return "An item can't go inside itself or one of its own subtasks."
            }
        }
        let zone = viewTimeZone
        var savedID = draft.taskID ?? UUID()
        mutate(draft.taskID == nil ? "New \(draft.kind.title)" : "Edit \(draft.kind.title)") { c in
            let tags = register(tags: draft.tags, into: &c)
            var t = TaskItem(id: savedID, title: title, start: draft.start, end: draft.end, categoryID: draft.categoryID,
                             tags: tags, parentID: draft.parentID, colorHex: customColor, notes: notes, location: location,
                             startTime: times.0, endTime: times.1, kind: draft.kind)
            Store.normalize(&t, zone: zone)
            if let id = draft.taskID, let i = c.tasks.firstIndex(where: { $0.id == id }) {
                c.tasks[i] = t
                savedID = id
            } else {
                c.tasks.append(t)
            }
        }
        expandAncestors(of: savedID)
        selectedTaskID = savedID
        return nil
    }

    struct Problem: Error { let text: String }

    /// Checks typed times; blank means 00:00 on the first day and 24:00 on the last day.
    private func parseTimes(_ startText: String, _ endText: String, start: Day, end: Day, milestone: Bool)
        -> Result<(String?, String?), Problem> {
        var startTime: String?, endTime: String?
        if let raw = Store.trimmed(startText) {
            guard let t = TimeOfDay.normalize(raw) else { return .failure(Problem(text: "Enter the time like 9:30 or 14:00.")) }
            startTime = t
        }
        if milestone { return .success((startTime, nil)) }
        if let raw = Store.trimmed(endText) {
            guard let t = TimeOfDay.normalize(raw, allowEndOfDay: true) else {
                return .failure(Problem(text: "Enter the end time like 17:00, 5pm or 24:00."))
            }
            endTime = t
        }
        if start == end, (endTime ?? TimeOfDay.defaultEnd) < (startTime ?? TimeOfDay.defaultStart) {
            return .failure(Problem(text: "On a one-day task the end time can't be before the start time."))
        }
        return .success((startTime, endTime))
    }

    static func trimmed(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Keeps an item consistent after an edit made in time zone `zone`.
    static func normalize(_ t: inout TaskItem, zone: TimeZone) {
        if t.storedKind == .milestone {
            t.end = t.start
            t.endTime = nil
        }
        if t.end < t.start { t.end = t.start }
        t.timeZone = t.isTimed ? zone.identifier : nil
    }

    // MARK: Editing items (the details pane)

    /// Applies one edit. A timed item is first expressed in the time zone being viewed, so what
    /// you see is what you change (and its moment in time stays right).
    @discardableResult
    private func updateItem(_ id: UUID, _ action: String, coalesce: String? = nil, _ change: (inout TaskItem) -> Void) -> Bool {
        guard task(id) != nil else { return false }
        let zone = viewTimeZone
        var changed = false
        mutate(action, coalesceKey: coalesce.map { "\($0):\(id)" }) { c in
            guard let i = c.tasks.firstIndex(where: { $0.id == id }) else { return }
            var before = c.tasks[i].displayed(in: zone)
            Store.normalize(&before, zone: zone)
            var t = before
            change(&t)
            Store.normalize(&t, zone: zone)
            guard t != before else { return }
            c.tasks[i] = t
            changed = true
        }
        return changed
    }

    @discardableResult
    func setTitle(_ id: UUID, _ text: String) -> String? {
        guard let title = Store.trimmed(text) else { return "Enter a title." }
        updateItem(id, "Rename") { $0.title = title }
        return nil
    }

    /// Changes what an item is. An item with subtasks is always a group.
    @discardableResult
    func setKind(_ id: UUID, _ kind: ItemKind) -> String? {
        guard task(id) != nil else { return nil }
        if content.hasStructuralChildren(id) && kind != .group { return "An item with subtasks is always a group." }
        let zone = viewTimeZone
        mutate("Change to \(kind.title)") { c in
            guard let i = c.tasks.firstIndex(where: { $0.id == id }) else { return }
            var item = c.tasks[i].displayed(in: zone)
            if kind == .group, let d = displayDates(id) { item.start = d.start; item.end = d.end }
            item.kind = kind
            if kind == .milestone {
                item.end = item.start
                item.endTime = nil
                // Its own milestones can't stay inside a milestone: they move up with it.
                for j in c.tasks.indices where c.tasks[j].parentID == id { c.tasks[j].parentID = item.parentID }
            }
            Store.normalize(&item, zone: zone)
            c.tasks[i] = item
        }
        return nil
    }

    /// New first and last day (as shown). For a milestone, `end` is ignored.
    @discardableResult
    func setDates(_ id: UUID, start: Day, end: Day) -> String? {
        guard let t = task(id) else { return nil }
        if content.effectiveKind(t) == .group { return "A group's dates come from what's inside it." }
        if t.storedKind != .milestone && end < start { return "The end date can't be before the start date." }
        let shownItem = t.displayed(in: viewTimeZone)
        if t.storedKind != .milestone && start == end,
           (shownItem.endTime ?? TimeOfDay.defaultEnd) < (shownItem.startTime ?? TimeOfDay.defaultStart) {
            return "On a one-day task the end time can't be before the start time."
        }
        updateItem(id, "Change Dates") { $0.start = start; $0.end = t.storedKind == .milestone ? start : end }
        return nil
    }

    /// New times of day (as typed; blank removes a time). Returns an error message or nil.
    @discardableResult
    func setTimes(_ id: UUID, start startText: String, end endText: String) -> String? {
        guard let t = shown(id) else { return nil }
        switch parseTimes(startText, endText, start: t.start, end: t.end, milestone: t.storedKind == .milestone) {
        case .failure(let p): return p.text
        case .success(let times):
            updateItem(id, "Change Time") { $0.startTime = times.0; $0.endTime = times.1 }
            return nil
        }
    }

    /// Puts an item inside another (nil = top level). Returns an error message or nil.
    @discardableResult
    func setParent(_ id: UUID, _ parentID: UUID?) -> String? {
        if let pid = parentID {
            guard let p = task(pid) else { return "That item no longer exists." }
            if p.storedKind == .milestone { return "Nothing can go inside a milestone." }
            if pid == id || content.descendants(of: id).contains(pid) { return "An item can't go inside itself or one of its own subtasks." }
        }
        mutate("Move Into Group") { c in
            if let i = c.tasks.firstIndex(where: { $0.id == id }) { c.tasks[i].parentID = parentID }
            // An arrow can't join an item to a group it's inside.
            let content = c
            let invalid = Set(content.dependencies.filter { content.related($0.from, $0.to) }.map(\.id))
            c.dependencies.removeAll { invalid.contains($0.id) }
        }
        expandAncestors(of: id)
        return nil
    }

    func setCategory(_ id: UUID, _ categoryID: UUID) {
        guard category(categoryID) != nil else { return }
        updateItem(id, "Change Category") { $0.categoryID = categoryID }
    }

    /// The item's own color (nil = its category's).
    func setColor(_ id: UUID, _ hex: String?) {
        let h = hex.flatMap { RGB.normalizedHex($0) }
        updateItem(id, "Change Color", coalesce: "color") { $0.colorHex = h }
    }

    func setLocation(_ id: UUID, _ text: String) {
        updateItem(id, "Change Location") { $0.location = Store.trimmed(text) }
    }

    func setNotes(_ id: UUID, _ text: String) {
        let note = Store.trimmed(text).map { _ in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        updateItem(id, "Change Notes") { $0.notes = note }
    }

    func setTags(_ id: UUID, _ tags: [String]) {
        guard task(id) != nil else { return }
        let zone = viewTimeZone
        mutate("Change Tags") { c in
            let registered = register(tags: tags, into: &c)
            if let i = c.tasks.firstIndex(where: { $0.id == id }) {
                var t = c.tasks[i].displayed(in: zone)
                t.tags = registered
                Store.normalize(&t, zone: zone)
                c.tasks[i] = t
            }
        }
    }

    /// Saves new dates from a timeline drag (as shown). Dragging a group moves everything in it;
    /// moving a task takes its milestones along.
    func updateDates(_ id: UUID, start: Day, end: Day) {
        guard end >= start, let t = task(id) else { return }
        switch content.effectiveKind(t) {
        case .group:
            guard let span = displayDates(id) else { return }
            shift(content.descendants(of: id).union([id]), by: start - span.start, action: "Move Group")
        case .milestone:
            updateItem(id, "Move Milestone") { $0.start = start; $0.end = start }
        case .task:
            let s = t.displayed(in: viewTimeZone)
            if s.dayCount == end - start + 1 {
                let marks = Set(content.tasks.filter { $0.parentID == id && $0.storedKind == .milestone }.map(\.id))
                shift(marks.union([id]), by: start - s.start, action: "Move Task")
            } else {
                updateItem(id, "Resize Task") { $0.start = start; $0.end = end }
            }
        }
    }

    /// Moves items by whole days (as shown), as one undo step.
    private func shift(_ ids: Set<UUID>, by days: Int, action: String) {
        guard days != 0 else { return }
        let zone = viewTimeZone
        mutate(action) { c in
            for i in c.tasks.indices where ids.contains(c.tasks[i].id) {
                var t = c.tasks[i].displayed(in: zone)
                t.start = t.start + days
                t.end = t.end + days
                Store.normalize(&t, zone: zone)
                c.tasks[i] = t
            }
        }
    }

    func requestDelete(_ id: UUID) {
        guard let t = task(id) else { return }
        let kind = content.effectiveKind(t)
        var parts: [String] = []
        let marks = content.tasks.filter { $0.parentID == id && $0.storedKind == .milestone }.count
        let inside = content.tasks.filter { $0.parentID == id }.count
        if kind == .task && marks > 0 {
            parts.append(marks == 1 ? "Its milestone is deleted too." : "Its \(marks) milestones are deleted too.")
        } else if inside > 0 {
            let what = inside == 1 ? "The item inside it moves" : "The \(inside) items inside it move"
            let destination = t.parentID.flatMap { task($0) }.map { "into “\($0.title)”" } ?? "to the top level"
            parts.append("\(what) \(destination).")
        }
        let links = content.dependencies.filter { $0.from == id || $0.to == id }.count
        if links > 0 { parts.append(links == 1 ? "Its arrow is removed." : "Its \(links) arrows are removed.") }
        parts.append("You can undo this with Edit › Undo (⌘Z).")
        activeSheet = .confirm(UUID(), Confirmation(
            title: "Delete “\(t.title)”?", emphasis: t.title, message: parts.joined(separator: " "),
            confirmTitle: "Delete \(kind.title)", action: { [weak self] in self?.deleteTask(id) }))
    }

    /// Deletes an item. A task's milestones go with it; anything else inside moves up one level.
    func deleteTask(_ id: UUID) {
        guard let t = task(id) else { return }
        let kind = content.effectiveKind(t)
        mutate("Delete \(kind.title)") { c in
            var removed: Set<UUID> = [id]
            if kind == .task {
                removed.formUnion(c.tasks.filter { $0.parentID == id && $0.storedKind == .milestone }.map(\.id))
            }
            for i in c.tasks.indices where c.tasks[i].parentID == id && !removed.contains(c.tasks[i].id) {
                c.tasks[i].parentID = t.parentID
            }
            c.tasks.removeAll { removed.contains($0.id) }
            c.dependencies.removeAll { removed.contains($0.from) || removed.contains($0.to) }
        }
        if selectedTaskID == id { selectedTaskID = nil }
    }

    /// Moves an item up one level (under its grandparent, or to the top level).
    func moveOutOfParent(_ id: UUID) {
        guard let t = task(id), let pid = t.parentID else { return }
        let grandparent = task(pid)?.parentID
        mutate("Move Out of Group") { c in
            if let i = c.tasks.firstIndex(where: { $0.id == id }) { c.tasks[i].parentID = grandparent }
        }
        selectedTaskID = id
    }

    // MARK: Dependencies

    func dependency(_ id: UUID) -> Dependency? { content.dependencies.first { $0.id == id } }
    /// Arrows that end at this item (the items before it).
    func predecessors(of id: UUID) -> [Dependency] { content.dependencies.filter { $0.to == id } }
    /// Arrows that start at this item (the items after it).
    func successors(of id: UUID) -> [Dependency] { content.dependencies.filter { $0.from == id } }

    /// Why an arrow from `a` to `b` isn't possible, or nil when it is.
    func linkProblem(from a: UUID, to b: UUID) -> String? {
        guard task(a) != nil, task(b) != nil else { return "That item no longer exists." }
        if a == b { return "An arrow needs two different items." }
        if content.related(a, b) { return "A group and an item inside it can't be joined by an arrow." }
        if content.dependencies.contains(where: { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }) {
            return "These two items are already joined by an arrow."
        }
        return nil
    }

    /// Adds an arrow and selects it. Returns its id, or nil when it isn't possible.
    @discardableResult
    func addDependency(from a: UUID, to b: UUID, type: DependencyType = .finishToStart,
                       fromSide: LinkSide? = nil, toSide: LinkSide? = nil, select: Bool = true) -> UUID? {
        guard linkProblem(from: a, to: b) == nil else { return nil }
        // Only top and bottom are kept: left and right always follow the type.
        let d = Dependency(id: UUID(), from: a, to: b, type: type,
                           fromSide: fromSide?.isVertical == true ? fromSide : nil,
                           toSide: toSide?.isVertical == true ? toSide : nil)
        mutate("Add Arrow") { c in c.dependencies.append(d) }
        if select { selectedLinkID = d.id }
        return d.id
    }

    private func updateDependency(_ id: UUID, _ action: String, coalesce: String? = nil, _ change: (inout Dependency) -> Void) {
        mutate(action, coalesceKey: coalesce.map { "\($0):\(id)" }) { c in
            if let i = c.dependencies.firstIndex(where: { $0.id == id }) { change(&c.dependencies[i]) }
        }
    }

    func setDependencyType(_ id: UUID, _ type: DependencyType) { updateDependency(id, "Change Arrow") { $0.type = type } }
    /// Moves one end of an arrow to a side of its item. Left and right also set which end of the
    /// item the arrow joins (its start or its end); top and bottom keep that.
    func setDependencySide(_ id: UUID, exit: Bool, _ side: LinkSide) {
        updateDependency(id, "Change Arrow Side") { d in
            if exit {
                d.fromSide = side.isVertical ? side : nil
                if !side.isVertical { d.type = DependencyType(fromEnd: side == .right, toEnd: d.type.toEnd) }
            } else {
                d.toSide = side.isVertical ? side : nil
                if !side.isVertical { d.type = DependencyType(fromEnd: d.type.fromEnd, toEnd: side == .right) }
            }
        }
    }
    func setDependencyColor(_ id: UUID, _ hex: String?) {
        let h = hex.flatMap { RGB.normalizedHex($0) }
        updateDependency(id, "Change Arrow Color", coalesce: "linkcolor") { $0.colorHex = h }
    }
    func setDependencyWidth(_ id: UUID, _ width: Double?) {
        updateDependency(id, "Change Arrow Thickness") { $0.width = width.map { min(max($0, 0.25), 8) } }
    }
    func reverseDependency(_ id: UUID) {
        updateDependency(id, "Reverse Arrow") { d in
            (d.from, d.to) = (d.to, d.from)
            d.type = DependencyType(fromEnd: d.type.toEnd, toEnd: d.type.fromEnd)
            (d.fromSide, d.toSide) = (d.toSide, d.fromSide)
        }
    }
    func deleteDependency(_ id: UUID) {
        mutate("Delete Arrow") { c in c.dependencies.removeAll { $0.id == id } }
        if selectedLinkID == id { selectedLinkID = nil }
    }

    // MARK: Examples

    /// Help › Add Example Tasks: adds the sample tasks (undoable), reusing categories by name.
    func addExampleTasks() {
        mutate("Add Example Tasks") { c in
            let ex = AppContent.examples(today: today, keeping: c.categories)
            c.categories = ex.categories
            c.tasks += ex.tasks
            for t in ex.tags where !c.tags.contains(where: { $0.lowercased() == t.lowercased() }) { c.tags.append(t) }
            c.tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    // MARK: Order

    /// Moves an item among its siblings so it comes just before `beforeID`, or last when
    /// `beforeID` is nil. Its level never changes; what's inside it moves with it.
    func moveTask(_ id: UUID, before beforeID: UUID?) {
        guard let t = task(id), beforeID != id else { return }
        if let b = beforeID, task(b)?.parentID != t.parentID { return }
        mutate("Reorder") { c in
            guard let from = c.tasks.firstIndex(where: { $0.id == id }) else { return }
            let item = c.tasks.remove(at: from)
            if let b = beforeID, let to = c.tasks.firstIndex(where: { $0.id == b }) {
                c.tasks.insert(item, at: to)
            } else if let last = c.tasks.lastIndex(where: { $0.parentID == item.parentID }) {
                c.tasks.insert(item, at: last + 1)
            } else {
                c.tasks.append(item)
            }
        }
        selectedTaskID = id
    }

    /// Siblings of an item that have their own rows, in order, among those listed with it: the
    /// unfinished ones, or the completed ones (which are listed after them).
    private func siblings(of id: UUID) -> [TaskItem] {
        guard let t = task(id) else { return [] }
        return content.tasks.filter { $0.parentID == t.parentID && !content.isMark($0) && $0.isCompleted == t.isCompleted }
    }

    // MARK: Completed

    /// Marks an item as completed (or not). A completed item moves to the Archive (with everything
    /// inside it); its place in the order is kept, so unmarking it returns it to where it was.
    func setCompleted(_ id: UUID, _ done: Bool) {
        guard let t = task(id), t.isCompleted != done else { return }
        mutate(done ? "Mark as Completed" : "Mark as Not Completed") { c in
            if let i = c.tasks.firstIndex(where: { $0.id == id }) { c.tasks[i].completed = done ? true : nil }
        }
        selectedTaskID = id
    }

    func toggleCompleted(_ id: UUID) {
        if let t = task(id) { setCompleted(id, !t.isCompleted) }
    }

    func canMoveTask(_ id: UUID, by offset: Int) -> Bool {
        let sibs = siblings(of: id)
        guard let i = sibs.firstIndex(where: { $0.id == id }) else { return false }
        return sibs.indices.contains(i + offset)
    }

    /// Move Up / Move Down (⌥↑ / ⌥↓): one place among its siblings.
    func moveTask(_ id: UUID, by offset: Int) {
        let sibs = siblings(of: id)
        guard let i = sibs.firstIndex(where: { $0.id == id }), sibs.indices.contains(i + offset) else { return }
        if offset < 0 {
            moveTask(id, before: sibs[i + offset].id)
        } else {
            // Before the next one in the list, or (at the end) before the first item listed after
            // this part, so the stored order matches what's shown.
            let after = i + offset + 1
            let next = after < sibs.count ? sibs[after].id : nil
            moveTask(id, before: next ?? firstListedAfter(sibs))
        }
    }

    /// The first sibling (in stored order) after the last of these, if any.
    private func firstListedAfter(_ sibs: [TaskItem]) -> UUID? {
        guard let last = sibs.last, let i = content.tasks.firstIndex(where: { $0.id == last.id }) else { return nil }
        return content.tasks[(i + 1)...].first { $0.parentID == last.parentID && !content.isMark($0) }?.id
    }

    /// Moves a category to a new position in the sidebar.
    func moveCategory(_ id: UUID, to index: Int) {
        guard let from = content.categories.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), content.categories.count - 1)
        guard to != from else { return }
        mutate("Reorder Categories") { c in
            let item = c.categories.remove(at: from)
            c.categories.insert(item, at: to)
        }
    }

    // MARK: Preferences

    func setFirstWeekday(_ day: Int) {
        guard (0...6).contains(day), day != firstWeekday else { return }
        firstWeekday = day
        UserDefaults.standard.set(day, forKey: "FirstWeekday")
    }

    func beginTodayColor() {
        activeSheet = .todayColor(UUID(), todayColorHex)
    }

    func setTodayColor(_ hex: String) {
        guard let h = RGB.normalizedHex(hex), h != todayColorHex else { return }
        TodayStyle.set(h)
        todayColorHex = h
    }

    // MARK: Collapsing groups

    func hasSubtasks(_ id: UUID) -> Bool { content.hasStructuralChildren(id) }
    func isCollapsed(_ id: UUID) -> Bool { collapsedIDs.contains(id) }

    func setCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard collapsed != collapsedIDs.contains(id) else { return }
        if collapsed {
            collapsedIDs.insert(id)
            // Keep the selection visible.
            if let sel = selectedTaskID, content.ancestors(of: sel).contains(id) { selectedTaskID = id }
        } else {
            collapsedIDs.remove(id)
        }
        persist()
    }

    func toggleCollapsed(_ id: UUID) { setCollapsed(id, !collapsedIDs.contains(id)) }

    func expandAll() {
        guard !collapsedIDs.isEmpty else { return }
        collapsedIDs = []
        persist()
    }

    func collapseAll() {
        let parents = Set(content.tasks.filter { content.hasStructuralChildren($0.id) }.map(\.id))
        guard parents != collapsedIDs else { return }
        collapsedIDs = parents
        if let sel = selectedTaskID, let top = content.ancestors(of: sel).last { selectedTaskID = top }
        persist()
    }

    private func expandAncestors(of id: UUID) {
        let ancestors = Set(content.ancestors(of: id))
        guard !collapsedIDs.isDisjoint(with: ancestors) else { return }
        collapsedIDs.subtract(ancestors)
        persist()
    }

    // MARK: Categories

    func beginNewCategory() {
        let used = Set(content.categories.map { $0.colorHex.uppercased() })
        let hex = Palette.colors.first { !used.contains($0.hex.uppercased()) }?.hex ?? Palette.colors[0].hex
        activeSheet = .category(UUID(), CategoryDraft(categoryID: nil, name: "", colorHex: hex))
    }

    func beginEditCategory(_ id: UUID) {
        guard let c = category(id) else { return }
        activeSheet = .category(UUID(), CategoryDraft(categoryID: id, name: c.name, colorHex: c.colorHex, notes: c.notes ?? ""))
    }

    /// Right-click a category › Add Note… / Edit Note…
    func beginCategoryNote(_ id: UUID) {
        guard let c = category(id) else { return }
        activeSheet = .categoryNote(UUID(), id, c.notes ?? "")
    }

    /// Saves (or, with empty text, removes) a category's note.
    func saveCategoryNote(_ id: UUID, _ text: String) {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(note.isEmpty ? "Remove Category Note" : "Edit Category Note") { c in
            if let i = c.categories.firstIndex(where: { $0.id == id }) { c.categories[i].notes = note.isEmpty ? nil : note }
        }
        activeSheet = nil
    }

    @discardableResult
    func saveCategoryDraft(_ draft: CategoryDraft) -> String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a category name." }
        guard RGB(hex: draft.colorHex) != nil else { return "Choose a color." }
        if content.categories.contains(where: { $0.name.lowercased() == name.lowercased() && $0.id != draft.categoryID }) {
            return "A category named “\(name)” already exists."
        }
        let note = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(draft.categoryID == nil ? "New Category" : "Edit Category") { c in
            if let id = draft.categoryID, let i = c.categories.firstIndex(where: { $0.id == id }) {
                c.categories[i].name = name
                c.categories[i].colorHex = draft.colorHex
                c.categories[i].notes = note.isEmpty ? nil : note
            } else {
                c.categories.append(Category(id: UUID(), name: name, colorHex: draft.colorHex, notes: note.isEmpty ? nil : note))
            }
        }
        activeSheet = nil
        return nil
    }

    func requestDeleteCategory(_ id: UUID) {
        guard let cat = category(id) else { return }
        guard let fallback = content.categories.first(where: { $0.id != id }) else {
            activeSheet = .confirm(UUID(), Confirmation(
                title: "Can't delete “\(cat.name)”", message: "Every item needs a category, so at least one category must remain.",
                confirmTitle: "", action: {}))
            return
        }
        let n = taskCount(category: id)
        let message = n == 0 ? "No items use this category."
            : "\(n == 1 ? "Its 1 item" : "Its \(n) items") will move to “\(fallback.name)”."
        activeSheet = .confirm(UUID(), Confirmation(
            title: "Delete the category “\(cat.name)”?", message: message, confirmTitle: "Delete Category",
            action: { [weak self] in self?.deleteCategory(id) }))
    }

    func deleteCategory(_ id: UUID) {
        guard let fallback = content.categories.first(where: { $0.id != id }) else { return }
        mutate("Delete Category") { c in
            c.categories.removeAll { $0.id == id }
            for i in c.tasks.indices where c.tasks[i].categoryID == id { c.tasks[i].categoryID = fallback.id }
        }
    }

    // MARK: Chart model

    /// Rows in outline order. An item matching the filters appears under its nearest ancestor
    /// that also matches (or at the top level); collapsed groups hide what's inside them.
    /// Milestones attached to a task are drawn on that task's row instead of their own.
    var chartModel: GanttModel {
        let zone = viewTimeZone
        let colorByID = Dictionary(uniqueKeysWithValues: content.categories.map { ($0.id, $0.colorHex) })
        let shownByID = Dictionary(uniqueKeysWithValues: content.tasks.map { ($0.id, $0.displayed(in: zone)) })
        var childrenOf: [UUID: [TaskItem]] = [:]
        for t in content.tasks { if let p = t.parentID { childrenOf[p, default: []].append(t) } }
        func kind(_ t: TaskItem) -> ItemKind {
            if t.storedKind == .milestone { return .milestone }
            if t.storedKind == .group || (childrenOf[t.id] ?? []).contains(where: { $0.storedKind != .milestone }) { return .group }
            return .task
        }
        var spanCache: [UUID: (Day, Day)?] = [:]
        func span(_ t: TaskItem, depth: Int = 0) -> (Day, Day)? {
            if let cached = spanCache[t.id] { return cached }
            var result: (Day, Day)?
            if kind(t) != .group || depth > 100 {
                let s = shownByID[t.id] ?? t
                result = (s.start, s.end)
            } else {
                for c in childrenOf[t.id] ?? [] {
                    guard let cs = span(c, depth: depth + 1) else { continue }
                    result = result.map { (min($0.0, cs.0), max($0.1, cs.1)) } ?? cs
                }
            }
            spanCache[t.id] = result
            return result
        }
        func color(_ t: TaskItem) -> String { t.colorHex ?? colorByID[t.categoryID] ?? "#8B8D98" }
        func minute(_ t: TaskItem) -> Int? { t.startTime.flatMap(TimeOfDay.minutes) }
        let markIDs = Set(content.tasks.filter { t in
            t.storedKind == .milestone && t.parentID.flatMap { p in content.item(p).map { kind($0) == .task } } == true
        }.map(\.id))

        // The main list or the Archive (completed items and what's inside them).
        let archived = archivedIDs
        let inList = { (t: TaskItem) in archived.contains(t.id) == self.showingArchive }
        let matched = content.tasks.filter { !markIDs.contains($0.id) && matchesFilters($0) && inList($0) }
        let matchedIDs = Set(matched.map(\.id))
        let parentByID = Dictionary(uniqueKeysWithValues: content.tasks.map { ($0.id, $0.parentID) })
        var byParent: [UUID?: [TaskItem]] = [:]
        for t in matched {
            var p = t.parentID
            var hops = 0
            while let pid = p, !matchedIDs.contains(pid), hops < 10_000 { p = parentByID[pid] ?? nil; hops += 1 }
            byParent[p, default: []].append(t)
        }
        var rows: [GanttRow] = []
        var visited = Set<UUID>()
        func visit(_ parent: UUID?, depth: Int) {
            // Completed items come after the others at the same level, each part in its own order.
            let items = byParent[parent] ?? []
            for t in items.filter({ !$0.isCompleted }) + items.filter(\.isCompleted) where visited.insert(t.id).inserted {
                let s = shownByID[t.id] ?? t
                let k = kind(t)
                let hasChildren = !(byParent[t.id] ?? []).isEmpty
                let collapsed = hasChildren && collapsedIDs.contains(t.id)
                let dates = span(t)
                let marks: [GanttMark] = k == .task
                    ? (childrenOf[t.id] ?? []).filter { markIDs.contains($0.id) && matchesFilters($0) && inList($0) }.map { m in
                        let ms = shownByID[m.id] ?? m
                        return GanttMark(id: m.id, day: ms.start, minute: minute(ms), title: m.title, colorHex: color(m),
                                         detail: [ms.startTime, ms.location].compactMap { $0 }.joined(separator: " · "),
                                         completed: m.isCompleted)
                    }.sorted { ($0.day, $0.minute ?? 0) < ($1.day, $1.minute ?? 0) }
                    : []
                var detail: [String] = []
                switch k {
                case .group:
                    let n = (childrenOf[t.id] ?? []).count
                    detail.append(n == 1 ? "1 item" : "\(n) items")
                case .milestone:
                    if let time = s.startTime { detail.append(time) }
                case .task:
                    if let time = s.timeText { detail.append(time) }
                }
                if let loc = s.location { detail.append(loc) }
                rows.append(GanttRow(id: t.id, title: t.title, start: dates?.0 ?? s.start, end: dates?.1 ?? s.end,
                                     colorHex: color(t), tags: t.tags, depth: depth, hasChildren: hasChildren,
                                     collapsed: collapsed, parentID: t.parentID, detail: detail.joined(separator: " · "),
                                     notes: t.notes, kind: k, hasDates: dates != nil,
                                     minute: k == .milestone ? minute(s) : nil, marks: marks, completed: t.isCompleted))
                if !collapsed { visit(t.id, depth: depth + 1) }
            }
        }
        visit(nil, depth: 0)

        // Where each item is drawn: its own row, its task's row (a milestone mark), or the row
        // of the nearest group it's folded into.
        let rowIDs = Set(rows.map(\.id))
        var anchorRow: [UUID: UUID] = [:]
        for t in content.tasks {
            var current: UUID? = t.id
            var hops = 0
            while let c = current, !rowIDs.contains(c), hops < 10_000 { current = parentByID[c] ?? nil; hops += 1 }
            if let r = current { anchorRow[t.id] = r }
        }
        let links = content.dependencies.map {
            GanttLink(id: $0.id, from: $0.from, to: $0.to, type: $0.type, exitSide: $0.exitSide, entrySide: $0.entrySide,
                      colorHex: $0.colorHex, width: CGFloat($0.lineWidth))
        }

        var empty: String?
        if rows.isEmpty && showingArchive {
            empty = filtersActive && archiveCount > 0
                ? "Nothing in the Archive matches the current filters."
                : "The Archive is empty. Mark an item as completed (⇧⌘C) and it moves here; unmark it to return it to its place."
        } else if rows.isEmpty {
            empty = content.tasks.isEmpty
                ? "Nothing here yet. Click New, or double-click the timeline to add a task."
                : "Nothing matches the current filters."
        }
        return GanttModel(rows: rows, window: window, today: today, selectedID: selectedTaskID, emptyMessage: empty,
                          taskCount: matched.count, firstWeekday: firstWeekday, todayHex: todayColorHex,
                          links: links, anchorRow: anchorRow, selectedLinkID: selectedLinkID, nowMinute: nowMinute,
                          archive: showingArchive)
    }
}
