import Foundation

// MARK: - Day

/// A calendar day with no time-of-day component.
///
/// Stored as the number of days since 1970-01-01 in the proleptic Gregorian
/// calendar, so day arithmetic is independent of time zones and DST.
/// Serialized as an ISO `yyyy-MM-dd` string.
struct Day: Hashable, Comparable, Strideable, Codable, CustomStringConvertible {
    let ordinal: Int

    init(ordinal: Int) { self.ordinal = ordinal }

    init(year: Int, month: Int, day: Int) {
        ordinal = Day.daysFromCivil(year, month, day)
    }

    /// The local calendar day containing `date`, using the Mac's current time zone.
    static func from(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Day {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(year: c.year!, month: c.month!, day: c.day!)
    }

    static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }
    func distance(to other: Day) -> Int { other.ordinal - ordinal }
    func advanced(by n: Int) -> Day { Day(ordinal: ordinal + n) }
    static func + (d: Day, n: Int) -> Day { Day(ordinal: d.ordinal + n) }
    static func - (d: Day, n: Int) -> Day { Day(ordinal: d.ordinal - n) }
    static func - (a: Day, b: Day) -> Int { a.ordinal - b.ordinal }

    var ymd: (year: Int, month: Int, day: Int) { Day.civilFromDays(ordinal) }
    var year: Int { ymd.year }
    var month: Int { ymd.month }
    var dayOfMonth: Int { ymd.day }

    /// 0 = Sunday … 6 = Saturday.
    var weekday: Int {
        let w = (ordinal + 4) % 7 // 1970-01-01 was a Thursday.
        return w < 0 ? w + 7 : w
    }

    var isWeekend: Bool { weekday == 0 || weekday == 6 }

    var firstOfMonth: Day { let c = ymd; return Day(year: c.year, month: c.month, day: 1) }

    /// Adds calendar months, clamping the day to the target month's length.
    func addingMonths(_ n: Int) -> Day {
        let c = ymd
        var total = c.year * 12 + (c.month - 1) + n
        if total < 0 { total = 0 }
        let y = total / 12, m = total % 12 + 1
        return Day(year: y, month: m, day: min(c.day, Day.daysInMonth(year: y, month: m)))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        }
    }

    var iso: String {
        let c = ymd
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= Day.daysInMonth(year: y, month: m)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    var description: String { iso }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = Day(iso: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(string)")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    // Howard Hinnant's civil-calendar algorithms.
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}

// MARK: - English date formatting (independent of the system locale)

enum DayFormat {
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthLong = ["January", "February", "March", "April", "May", "June", "July",
                            "August", "September", "October", "November", "December"]
    static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let weekdayLetter = ["S", "M", "T", "W", "T", "F", "S"]

    /// "Nov 9"
    static func short(_ d: Day) -> String { "\(monthShort[d.month - 1]) \(d.dayOfMonth)" }
    /// "Nov 9, 2026"
    static func medium(_ d: Day) -> String { "\(monthShort[d.month - 1]) \(d.dayOfMonth), \(d.year)" }
    /// "Mon, Nov 9"
    static func weekdayShortDate(_ d: Day) -> String { "\(weekdayShort[d.weekday]), \(short(d))" }
    /// "Nov 2026" (month names are always three letters).
    static func monthYear(_ d: Day) -> String { "\(monthShort[d.month - 1]) \(d.year)" }

    /// "Nov 9 – Nov 12", "Nov 9", or with years when the range is not within `referenceYear`.
    static func range(_ start: Day, _ end: Day, referenceYear: Int? = nil) -> String {
        let showYear = start.year != end.year || (referenceYear != nil && start.year != referenceYear)
        let f: (Day) -> String = showYear ? medium : short
        return start == end ? f(start) : "\(f(start)) – \(f(end))"
    }

    static func dayCount(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    static let weekdayLong = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}

// MARK: - Times of day

enum TimeOfDay {
    /// Without a start time a task starts at 00:00 on its first day; without an end time it
    /// ends at 24:00 on its last day.
    static let defaultStart = "00:00"
    static let defaultEnd = "24:00"

    /// Reads "9", "0930", "9:30", "9.30", "21:05", "9pm", "9:30 am" … as "HH:mm" (24-hour).
    /// "24:00" (end of the day) is accepted only when `allowEndOfDay` is set.
    /// Returns nil when the text isn't a time.
    static func normalize(_ text: String, allowEndOfDay: Bool = false) -> String? {
        if allowEndOfDay, ["24", "24:00", "2400", "24.00"].contains(text.filter { !$0.isWhitespace }) { return defaultEnd }
        var s = text.lowercased().filter { !$0.isWhitespace }
        var pm = false, am = false
        if s.hasSuffix("pm") || s.hasSuffix("p") { pm = true; s = String(s.dropLast(s.hasSuffix("pm") ? 2 : 1)) }
        else if s.hasSuffix("am") || s.hasSuffix("a") { am = true; s = String(s.dropLast(s.hasSuffix("am") ? 2 : 1)) }
        s = s.replacingOccurrences(of: ".", with: ":")
        var h: Int?, m: Int?
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2 else { return nil }
            h = Int(parts[0]); m = Int(parts[1])
        } else if s.allSatisfy(\.isNumber) {
            switch s.count {
            case 1, 2: h = Int(s); m = 0
            case 3, 4: h = Int(s.prefix(s.count - 2)); m = Int(s.suffix(2))
            default: return nil
            }
        }
        guard var hour = h, let minute = m, (0...59).contains(minute) else { return nil }
        if pm || am {
            guard (1...12).contains(hour) else { return nil }
            if pm && hour < 12 { hour += 12 }
            if am && hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func range(_ start: String?, _ end: String?) -> String? {
        if start == nil && end == nil { return nil }
        return "\(start ?? defaultStart)–\(end ?? defaultEnd)"
    }

    /// "09:30" → 570; "24:00" → 1440.
    static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...24).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 570 → "09:30"; 1440 → "24:00".
    static func text(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}

// MARK: - Time zones

/// Time zones work like Apple Calendar: a task with a time keeps its moment in time and is
/// shown in the time zone you're viewing in (normally your Mac's own, so 10:00 entered in Tokyo
/// shows as 02:00 once the Mac is in Berlin). A task without any time keeps its dates in every
/// time zone.
enum Zones {
    static func zone(_ identifier: String?) -> TimeZone? { identifier.flatMap { TimeZone(identifier: $0) } }

    private static func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    /// The same moment, as a day and minutes after midnight in another time zone.
    static func convert(day: Day, minutes: Int, from: TimeZone, to: TimeZone) -> (day: Day, minutes: Int) {
        guard from.identifier != to.identifier else { return (day, minutes) }
        let c = day.ymd
        guard let midnight = calendar(from).date(from: DateComponents(year: c.year, month: c.month, day: c.day)) else {
            return (day, minutes)
        }
        let moment = midnight.addingTimeInterval(TimeInterval(minutes * 60))
        let r = calendar(to).dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        return (Day(year: r.year!, month: r.month!, day: r.day!), r.hour! * 60 + r.minute!)
    }

    /// "GMT+9", "GMT-3:30", "GMT".
    static func offsetText(_ tz: TimeZone, at date: Date = Date()) -> String {
        let s = tz.secondsFromGMT(for: date)
        if s == 0 { return "GMT" }
        let h = abs(s) / 3600, m = abs(s) % 3600 / 60
        return "GMT\(s < 0 ? "-" : "+")\(h)\(m == 0 ? "" : String(format: ":%02d", m))"
    }

    /// "Tokyo" for "Asia/Tokyo", "Argentina/Buenos Aires" for "America/Argentina/Buenos_Aires".
    static func city(_ tz: TimeZone) -> String {
        let parts = tz.identifier.split(separator: "/")
        return (parts.count > 1 ? parts.dropFirst().joined(separator: "/") : tz.identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// "Asia/Tokyo (GMT+9)".
    static func label(_ tz: TimeZone) -> String { "\(tz.identifier.replacingOccurrences(of: "_", with: " ")) (\(offsetText(tz)))" }
}

// MARK: - Week numbers

/// Week numbering for the header's week bar.
/// - Sunday or Saturday first: week 1 is the week that contains January 1 (US style).
/// - Monday first: ISO 8601, where week 1 is the week that contains January 4.
enum Weeks {
    /// `firstWeekday`: 0 = Sunday … 6 = Saturday.
    static func start(of d: Day, firstWeekday: Int) -> Day {
        d - ((d.weekday - firstWeekday + 7) % 7)
    }

    static func minimumDaysInFirstWeek(firstWeekday: Int) -> Int { firstWeekday == 1 ? 4 : 1 }

    static func number(of d: Day, firstWeekday: Int) -> Int {
        let ws = start(of: d, firstWeekday: firstWeekday)
        let m = minimumDaysInFirstWeek(firstWeekday: firstWeekday)
        let year = (ws + (7 - m)).year
        let week1 = start(of: Day(year: year, month: 1, day: m), firstWeekday: firstWeekday)
        return (ws - week1) / 7 + 1
    }
}

// MARK: - Colors

struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var hex: String {
        let c = { (x: Double) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    /// Accepts "#2F6FEB", "2f6feb", "#2F6" or "2F6" (spaces ignored) and returns "#2F6FEB",
    /// or nil if it isn't a hex color.
    static func normalizedHex(_ text: String) -> String? {
        var s = text.filter { !$0.isWhitespace }.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 else { return nil }
        return "#" + s
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// White text unless the fill is light enough that dark text reads better.
    var prefersLightText: Bool { contrast(with: RGB(r: 1, g: 1, b: 1)) >= 2.4 }

    func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)
}

enum Palette {
    static let colors: [(name: String, hex: String)] = [
        ("Red", "#E5484D"), ("Orange", "#F2811D"), ("Yellow", "#F5C518"), ("Green", "#30A46C"),
        ("Mint", "#12A594"), ("Teal", "#0E9FC2"), ("Blue", "#2F6FEB"), ("Indigo", "#5B5BD6"),
        ("Purple", "#8E4EC6"), ("Pink", "#D6409F"), ("Brown", "#A07553"), ("Gray", "#8B8D98"),
    ]
    static let blue = "#2F6FEB"
    static let green = "#30A46C"
}

// MARK: - Data model

struct Category: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    /// A free-form note about the category (right-click › Add Note…).
    var notes: String? = nil
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    /// Inclusive first day.
    var start: Day
    /// Inclusive last day; never before `start`.
    var end: Day
    var categoryID: UUID
    /// Tag names without the leading `#`.
    var tags: [String]
    /// The task this one is a subtask of (nil for a top-level task).
    var parentID: UUID? = nil
    /// Its own bar color; nil uses the category color.
    var colorHex: String? = nil
    /// Free-form notes.
    var notes: String? = nil
    /// Where it happens.
    var location: String? = nil
    /// Time of day on the start date, "HH:mm" (24-hour). Empty means 00:00.
    var startTime: String? = nil
    /// Time of day on the end date, "HH:mm" (24-hour, up to "24:00"). Empty means 24:00.
    var endTime: String? = nil
    /// Task, milestone or group as created (nil = task, as in files from version 2).
    /// A task that has subtasks is shown as a group whatever this says.
    var kind: ItemKind? = nil
    /// The time zone its times were entered in (Apple Calendar style). Nil when it has no times:
    /// then its dates are the same in every time zone.
    var timeZone: String? = nil
    /// Marked as completed (whenever it was finished; its dates stay as they are). Completed items
    /// are listed after the others at their level; their place in the order is kept, so unmarking
    /// one puts it back where it was. Nil (left out of the file) when not completed.
    var completed: Bool? = nil

    var isCompleted: Bool { completed == true }

    /// "09:30–17:00"; with one time set, the other is its default ("14:00–24:00").
    /// Nil when neither is set (the task runs whole days).
    var timeText: String? {
        if storedKind == .milestone { return startTime }
        return TimeOfDay.range(startTime, endTime)
    }

    var storedKind: ItemKind { kind ?? .task }
    var isTimed: Bool { startTime != nil || endTime != nil }

    var dayCount: Int { end - start + 1 }
    func includes(_ day: Day) -> Bool { start <= day && day <= end }
    func hasTag(key: String) -> Bool { tags.contains { $0.lowercased() == key } }

    /// This item as seen from `view`: a timed item's dates and times are converted from the time
    /// zone they were entered in; an item without times is unchanged.
    func displayed(in view: TimeZone) -> TaskItem {
        guard isTimed, let from = Zones.zone(timeZone), from.identifier != view.identifier else { return self }
        var t = self
        let s = Zones.convert(day: start, minutes: TimeOfDay.minutes(startTime ?? TimeOfDay.defaultStart) ?? 0, from: from, to: view)
        if storedKind == .milestone {
            t.start = s.day
            t.end = s.day
            t.startTime = TimeOfDay.text(s.minutes)
            t.endTime = nil
        } else {
            var e = Zones.convert(day: end, minutes: TimeOfDay.minutes(endTime ?? TimeOfDay.defaultEnd) ?? 1440, from: from, to: view)
            // Ending exactly at midnight means 24:00 on the day before.
            if e.minutes == 0 && e.day - 1 >= s.day { e = (e.day - 1, 1440) }
            t.start = s.day
            t.startTime = TimeOfDay.text(s.minutes)
            t.end = max(e.day, s.day)
            t.endTime = TimeOfDay.text(e.minutes)
        }
        t.timeZone = view.identifier
        return t
    }
}

/// What an item is: a task (a bar), a milestone (a diamond on one day) or a group (spans its subtasks).
enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case task, milestone, group
    var id: String { rawValue }
    var title: String {
        switch self {
        case .task: return "Task"
        case .milestone: return "Milestone"
        case .group: return "Group"
        }
    }
}

/// Which ends of two items an arrow joins: Finish→Start is the usual "B starts after A finishes".
enum DependencyType: String, Codable, CaseIterable, Identifiable {
    case finishToStart = "FS", startToStart = "SS", finishToFinish = "FF", startToFinish = "SF"

    var id: String { rawValue }
    /// The arrow leaves the predecessor at its end (otherwise at its start).
    var fromEnd: Bool { self == .finishToStart || self == .finishToFinish }
    /// The arrow arrives at the successor's end (otherwise at its start).
    var toEnd: Bool { self == .finishToFinish || self == .startToFinish }

    init(fromEnd: Bool, toEnd: Bool) {
        switch (fromEnd, toEnd) {
        case (true, false): self = .finishToStart
        case (false, false): self = .startToStart
        case (true, true): self = .finishToFinish
        case (false, true): self = .startToFinish
        }
    }

    var title: String {
        switch self {
        case .finishToStart: return "Finish → Start"
        case .startToStart: return "Start → Start"
        case .finishToFinish: return "Finish → Finish"
        case .startToFinish: return "Start → Finish"
        }
    }
}

/// The side of an item an arrow leaves from or arrives at. Left is the item's start and right
/// its end; top and bottom are the middle of its upper and lower edge.
enum LinkSide: String, Codable, CaseIterable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
    /// How the drawing bubble names it: "start", "end", "top", "bottom".
    var word: String {
        switch self {
        case .left: return "start"
        case .right: return "end"
        case .top: return "top"
        case .bottom: return "bottom"
        }
    }
    var symbol: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        }
    }
    var isVertical: Bool { self == .top || self == .bottom }
    /// The unit direction pointing out of the item through this side (y grows downward).
    var dx: CGFloat { self == .left ? -1 : self == .right ? 1 : 0 }
    var dy: CGFloat { self == .top ? -1 : self == .bottom ? 1 : 0 }
    /// Left or right: the side that stands for an item's start or end.
    static func horizontal(atEnd: Bool) -> LinkSide { atEnd ? .right : .left }
}

extension DependencyType {
    /// The type an arrow drawn between these sides gets: left is a start and right an end;
    /// top and bottom keep the usual Finish → Start meaning for that end.
    init(exit: LinkSide, entry: LinkSide) {
        self.init(fromEnd: exit != .left, toEnd: entry == .right)
    }
}

/// An arrow from one item (the predecessor) to another (the successor).
struct Dependency: Identifiable, Codable, Hashable {
    var id: UUID
    var from: UUID
    var to: UUID
    var type: DependencyType = .finishToStart
    /// Line color; nil uses the default gray.
    var colorHex: String? = nil
    /// Line thickness in points; nil uses the default.
    var width: Double? = nil
    /// The side the arrow leaves the first item from and arrives at the second, when it's the top or
    /// bottom. Nil (or left/right) means the side of the end the type names: left = start, right = end.
    var fromSide: LinkSide? = nil
    var toSide: LinkSide? = nil

    static let defaultWidth = 1.25
    static let widths: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4]
    var lineWidth: Double { width ?? Self.defaultWidth }
    /// The side the arrow actually leaves the first item from.
    var exitSide: LinkSide { fromSide.flatMap { $0.isVertical ? $0 : nil } ?? .horizontal(atEnd: type.fromEnd) }
    /// The side the arrow actually arrives at the second item.
    var entrySide: LinkSide { toSide.flatMap { $0.isVertical ? $0 : nil } ?? .horizontal(atEnd: type.toEnd) }
}

/// Everything that undo/redo snapshots: tasks (groups, tasks and milestones), categories, tags
/// and the dependency arrows.
struct AppContent: Codable, Equatable {
    var categories: [Category]
    var tags: [String]
    var tasks: [TaskItem]
    var dependencies: [Dependency] = []

    enum CodingKeys: String, CodingKey { case categories, tags, tasks, dependencies }

    static func starter() -> AppContent {
        AppContent(categories: [
            Category(id: UUID(), name: "Work", colorHex: Palette.blue),
            Category(id: UUID(), name: "Personal", colorHex: Palette.green),
        ], tags: [], tasks: [])
    }

    /// Sample tasks for the very first launch, placed around `today`, all tagged #example.
    /// Reuses categories with the same names when they exist.
    static func examples(today t: Day, keeping existing: [Category]) -> AppContent {
        var categories = existing
        func category(_ name: String, _ hex: String) -> UUID {
            if let c = categories.first(where: { $0.name.lowercased() == name.lowercased() }) { return c.id }
            let c = Category(id: UUID(), name: name, colorHex: hex)
            categories.append(c)
            return c.id
        }
        let work = category("Work", Palette.blue)
        let personal = category("Personal", Palette.green)
        let home = category("Home", "#F2811D")
        func task(_ title: String, _ start: Int, _ end: Int, _ cat: UUID, _ tags: [String], parent: UUID? = nil,
                  notes: String? = nil, location: String? = nil, startTime: String? = nil, endTime: String? = nil,
                  color: String? = nil) -> TaskItem {
            TaskItem(id: UUID(), title: title, start: t + start, end: t + end, categoryID: cat, tags: tags + ["example"],
                     parentID: parent, colorHex: color, notes: notes, location: location, startTime: startTime, endTime: endTime)
        }
        let launch = task("Launch website", -2, 12, work, ["web"],
                          notes: "A parent task: click the chevron to hide or show its subtasks.")
        let tasks = [
            launch,
            task("Write copy", -2, 1, work, ["writing"], parent: launch.id),
            task("Design mockups", 0, 4, work, ["design"], parent: launch.id,
                 notes: "Two options for the home page. Drag the bar to move it, or drag an end to change the dates."),
            task("Publish site", 10, 12, work, ["web"], parent: launch.id, location: "Online", startTime: "10:00"),
            task("Team meeting", 1, 1, work, ["meeting"], notes: "Agenda: progress, risks, next steps.",
                 location: "Room 204", startTime: "09:30", endTime: "10:30"),
            task("Quarterly report", -4, 3, work, ["follow-up"]),
            task("Dentist", 3, 3, personal, ["health"], location: "City Dental", startTime: "14:00", endTime: "15:00"),
            task("Plan trip", 5, 9, personal, ["travel", "follow-up"], notes: "Book train tickets and a hotel."),
            task("Garden cleanup", 6, 7, home, ["outdoor"], notes: "This bar has its own color, set in the editor under Bar Color.",
                 color: "#A07553"),
        ]
        let tags = Array(Set(tasks.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return AppContent(categories: categories, tags: tags, tasks: tasks)
    }

    // MARK: Subtask hierarchy

    /// Clears parent links that point at missing tasks, at the task itself, or form a cycle
    /// (only possible if the file was edited by hand).
    mutating func repairHierarchy() {
        let ids = Set(tasks.map(\.id))
        for i in tasks.indices {
            if let p = tasks[i].parentID, p == tasks[i].id || !ids.contains(p) { tasks[i].parentID = nil }
        }
        // A milestone can't hold other items: they move up to the milestone's own parent.
        let milestoneParent = Dictionary(uniqueKeysWithValues: tasks.filter { $0.storedKind == .milestone }.map { ($0.id, $0.parentID) })
        for i in tasks.indices {
            var hops = 0
            while let p = tasks[i].parentID, let up = milestoneParent[p], hops < 100 { tasks[i].parentID = up; hops += 1 }
        }
        // Milestones are a single day.
        for i in tasks.indices where tasks[i].storedKind == .milestone {
            tasks[i].end = tasks[i].start
            tasks[i].endTime = nil
        }
        // Arrows need two different items that exist; one arrow per pair.
        var seenPairs = Set<String>()
        dependencies.removeAll { d in
            d.from == d.to || !ids.contains(d.from) || !ids.contains(d.to)
                || !seenPairs.insert("\(d.from)>\(d.to)").inserted
        }
        var parentOf: [UUID: UUID] = [:]
        for t in tasks { if let p = t.parentID { parentOf[t.id] = p } }
        for i in tasks.indices {
            let start = tasks[i].id
            var seen: Set<UUID> = [start]
            var current = parentOf[start]
            while let c = current {
                if c == start { tasks[i].parentID = nil; parentOf[start] = nil; break }
                if !seen.insert(c).inserted { break }
                current = parentOf[c]
            }
        }
    }

    func children(of id: UUID?) -> [TaskItem] { tasks.filter { $0.parentID == id } }

    /// Every subtask below `id`, at any depth.
    func descendants(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var frontier = [id]
        while let next = frontier.popLast() {
            for t in tasks where t.parentID == next && result.insert(t.id).inserted { frontier.append(t.id) }
        }
        return result
    }

    /// Parent, grandparent, … of `id`, nearest first.
    func ancestors(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var current = tasks.first { $0.id == id }?.parentID
        while let c = current, !result.contains(c) {
            result.append(c)
            current = tasks.first { $0.id == c }?.parentID
        }
        return result
    }

    /// All tasks in outline order (each parent followed by its subtasks), with their depth.
    func outline() -> [(task: TaskItem, depth: Int)] {
        var byParent: [UUID?: [TaskItem]] = [:]
        for t in tasks { byParent[t.parentID, default: []].append(t) }
        var result: [(TaskItem, Int)] = []
        var visited = Set<UUID>()
        func visit(_ parent: UUID?, _ depth: Int) {
            for t in byParent[parent] ?? [] where visited.insert(t.id).inserted {
                result.append((t, depth))
                visit(t.id, depth + 1)
            }
        }
        visit(nil, 0)
        return result
    }

    // MARK: Groups, tasks and milestones

    func item(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    /// Has subtasks or subgroups (milestones attached to a task don't count).
    func hasStructuralChildren(_ id: UUID) -> Bool {
        tasks.contains { $0.parentID == id && $0.storedKind != .milestone }
    }

    /// What an item is shown as: a task with subtasks becomes a group on its own.
    func effectiveKind(_ t: TaskItem) -> ItemKind {
        if t.storedKind == .milestone { return .milestone }
        if t.storedKind == .group || hasStructuralChildren(t.id) { return .group }
        return .task
    }

    /// A milestone attached to a task: drawn as a diamond on that task's row.
    func isMark(_ t: TaskItem) -> Bool {
        guard t.storedKind == .milestone, let p = t.parentID, let parent = item(p) else { return false }
        return effectiveKind(parent) == .task
    }

    /// Whether `a` is an ancestor or a descendant of `b`.
    func related(_ a: UUID, _ b: UUID) -> Bool {
        ancestors(of: a).contains(b) || ancestors(of: b).contains(a)
    }

    /// Version 2 → 3: each task with subtasks becomes a group spanning its subtasks. When the
    /// parent's own dates differ from that span, they're kept as a task of the same name, first
    /// inside the group, so nothing that was on the chart disappears.
    mutating func migrateParentsToGroups() {
        var inserted: [(after: UUID, task: TaskItem)] = []
        for i in tasks.indices {
            let p = tasks[i]
            guard p.storedKind != .milestone, hasStructuralChildren(p.id) else { continue }
            let below = descendants(of: p.id).compactMap { item($0) }
            guard let s = below.map(\.start).min(), let e = below.map(\.end).max() else { continue }
            if (p.start, p.end) != (s, e) {
                let own = TaskItem(id: UUID(), title: p.title, start: p.start, end: p.end, categoryID: p.categoryID,
                                   tags: p.tags, parentID: p.id, colorHex: p.colorHex, notes: nil, location: p.location,
                                   startTime: p.startTime, endTime: p.endTime, kind: .task, timeZone: p.timeZone)
                inserted.append((p.id, own))
                tasks[i].location = nil
                tasks[i].startTime = nil
                tasks[i].endTime = nil
                tasks[i].timeZone = nil
            }
            tasks[i].kind = .group
        }
        for entry in inserted {
            if let at = tasks.firstIndex(where: { $0.id == entry.after }) { tasks.insert(entry.task, at: at + 1) }
        }
    }

    /// Timed tasks from before time zones were stored were entered in this Mac's time zone.
    mutating func assignTimeZone(_ identifier: String) {
        for i in tasks.indices where tasks[i].isTimed && tasks[i].timeZone == nil { tasks[i].timeZone = identifier }
    }
}

extension AppContent {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decode([Category].self, forKey: .categories)
        tags = try c.decode([String].self, forKey: .tags)
        tasks = try c.decode([TaskItem].self, forKey: .tasks)
        dependencies = try c.decodeIfPresent([Dependency].self, forKey: .dependencies) ?? []
    }
}

/// The visible range of the timeline, inclusive on both ends.
struct DateWindow: Codable, Equatable {
    var start: Day
    var end: Day

    var dayCount: Int { end - start + 1 }
    func contains(_ d: Day) -> Bool { start <= d && d <= end }

    static let maxDays = 732

    /// The default window: 14 days with today near the start.
    static func around(_ today: Day, days: Int = 14) -> DateWindow {
        let start = today - (days - 1) / 4
        return DateWindow(start: start, end: start + (days - 1))
    }
}

/// Preset lengths for the visible range. Each keeps the first visible day.
enum WindowPreset: Int, CaseIterable, Identifiable {
    case week1, week2, week3, month1, month2, month3, month6, year1

    var id: Int { rawValue }

    var title: String {
        ["1 Week", "2 Weeks", "3 Weeks", "1 Month", "2 Months", "3 Months", "6 Months", "1 Year"][rawValue]
    }


    enum Length: Equatable { case weeks(Int), months(Int) }

    var length: Length {
        switch self {
        case .week1: return .weeks(1)
        case .week2: return .weeks(2)
        case .week3: return .weeks(3)
        case .month1: return .months(1)
        case .month2: return .months(2)
        case .month3: return .months(3)
        case .month6: return .months(6)
        case .year1: return .months(12)
        }
    }

    func window(startingAt start: Day) -> DateWindow {
        switch length {
        case .weeks(let n): return DateWindow(start: start, end: start + (7 * n - 1))
        case .months(let n): return DateWindow(start: start, end: start.addingMonths(n) - 1)
        }
    }

    /// The preset that produces exactly this window, if any.
    static func matching(_ w: DateWindow) -> WindowPreset? {
        allCases.first { $0.window(startingAt: w.start) == w }
    }
}

/// The file format stored on disk.
struct AppData: Codable {
    var version: Int
    var content: AppContent
    var window: DateWindow
    /// Parent tasks whose subtasks are hidden (added in version 2).
    var collapsed: [UUID]? = nil
    /// Categories whose checkbox is off in the sidebar (added in version 2).
    var hiddenCategories: [UUID]? = nil

    /// 3: groups, milestones, dependency arrows and time zones (DaySpindle 2.1).
    static let currentVersion = 3
}

enum Tags {
    /// Normalizes user input like "#Follow up" to "Follow-up". Returns nil for empty input.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: "-")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ",;#"))
        guard !s.isEmpty else { return nil }
        return String(s.prefix(40))
    }

    /// Splits free text ("#a, b c") into normalized tag names.
    static func parse(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ", ;\n\t"))
            .compactMap(normalize)
    }
}
