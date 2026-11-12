import AppKit
import Foundation

/// Scripted self-check used to verify the app end to end.
///
/// Only active when the app is launched with `-DaySpindleVerifyScript <file>`
/// (optionally `-DaySpindleVerifyOut <dir>`). It drives the same code paths as the UI:
/// store actions behind the sidebar/editor, and synthesized mouse and keyboard
/// events delivered to the real windows. Snapshots are rendered from the app's own
/// windows, so no screen-recording permission is needed.
@MainActor
final class VerifyRunner {
    private let lines: [String]
    private var index = 0
    private let outDir: URL
    private weak var app: AppDelegate?
    private var log: [String] = []
    private var passed = 0
    private var failed = 0

    init?(scriptPath: String, app: AppDelegate) {
        guard let text = try? String(contentsOfFile: scriptPath, encoding: .utf8) else { return nil }
        lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let out = UserDefaults.standard.string(forKey: "DaySpindleVerifyOut")
            ?? (scriptPath as NSString).deletingLastPathComponent
        outDir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        self.app = app
    }

    private var inputGuard: Any?
    /// The last control clicked, to reopen a popover that closed.
    private var lastClicked: (name: String, window: NSWindow)?
    /// A snapshot to take in the middle of the next drag.
    private var pendingSnapshot = ""
    private var ignoredInput = 0

    func start() {
        record("Verification started \(Date()) pid \(getpid()) bundle \(Bundle.main.bundlePath)")
        // Real mouse and keyboard input from the person at the Mac is ignored while the
        // check runs, so a stray click can't change the results. (The check's own events
        // are delivered straight to the window and don't pass through this monitor.)
        inputGuard = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .scrollWheel, .keyDown, .keyUp,
        ]) { [weak self] _ in
            MainActor.assumeIsolated { self?.ignoredInput += 1 }
            return nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.step() }
    }

    private var store: Store { app!.store }
    private var window: NSWindow { app!.window }
    private var chart: GanttChartView? { GanttChartView.current }

    private func step() {
        guard index < lines.count else { finish(); return }
        let line = lines[index]
        index += 1
        let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        record("> \(line)")
        run(parts) { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.step() }
        }
    }

    private func finish() {
        if ignoredInput > 0 { record("(ignored \(ignoredInput) real mouse/keyboard events during the check)") }
        record("Finished: \(passed) passed, \(failed) failed")
        flush()
    }

    private func record(_ s: String) {
        log.append(s)
        flush()
    }

    private func flush() {
        try? log.joined(separator: "\n").appending("\n")
            .write(to: outDir.appendingPathComponent("verify-log.txt"), atomically: true, encoding: .utf8)
    }

    private func check(_ ok: Bool, _ what: String) {
        if ok { passed += 1 } else { failed += 1 }
        record("  \(ok ? "PASS" : "FAIL"): \(what)")
    }

    private func arg(_ p: [String], _ i: Int) -> String { i < p.count ? p[i] : "" }
    /// "today" in the script: the day the script started on (in the time zone shown then), so that
    /// dates stay put while the script switches time zones, whatever the hour is.
    private var scriptToday: Day?
    private func day(_ s: String) -> Day? {
        let today = scriptToday ?? store.today
        scriptToday = today
        if s == "today" { return today }
        if s.hasPrefix("today+"), let n = Int(s.dropFirst(6)) { return today + n }
        if s.hasPrefix("today-"), let n = Int(s.dropFirst(6)) { return today - n }
        return Day(iso: s)
    }
    private func taskNamed(_ title: String) -> TaskItem? { store.tasks.first { $0.title == title } }

    // MARK: Commands

    private func run(_ p: [String], done: @escaping (TimeInterval) -> Void) {
        switch p[0] {
        case "wait":
            done(Double(arg(p, 1)) ?? 1)

        case "snapshot":
            snapshot(window, name: arg(p, 1))
            done(0.2)

        case "snapshotSheet":
            if let sheet = window.attachedSheet { snapshot(sheet, name: arg(p, 1)) } else { record("  (no sheet open)") }
            done(0.2)

        case "snapshotPopover":
            if let pop = NSApp.windows.first(where: { $0.isVisible && $0 != window && $0.className.contains("Popover") }) {
                snapshot(pop, name: arg(p, 1))
            } else { record("  (no popover open)") }
            done(0.2)

        case "state":
            writeState(arg(p, 1))
            done(0.1)

        case "addCategory":
            if store.categories.contains(where: { $0.name == arg(p, 1) }) {
                record("  category exists")
            } else {
                let err = store.saveCategoryDraft(CategoryDraft(categoryID: nil, name: arg(p, 1), colorHex: arg(p, 2)))
                check(err == nil, "created category \(arg(p, 1)) \(err ?? "")")
            }
            done(0.4)

        case "addTask":
            guard let s = day(arg(p, 2)), let e = day(arg(p, 3)),
                  let cat = store.categories.first(where: { $0.name == arg(p, 4) }) else {
                check(false, "addTask arguments"); done(0.1); return
            }
            let tags = Tags.parse(arg(p, 5))
            let parent = arg(p, 6).isEmpty ? nil : taskNamed(arg(p, 6))?.id
            let err = store.saveTaskDraft(TaskDraft(taskID: nil, title: arg(p, 1), start: s, end: e, categoryID: cat.id,
                                                    tags: tags, parentID: parent))
            check(err == nil, "created task \(arg(p, 1))\(parent != nil ? " under \(arg(p, 6))" : "") \(err ?? "")")
            done(0.4)

        case "openNewTask", "newItem":
            // newItem|kind|parent title|day : the same as New Task / New Milestone / New Group,
            // which opens the details pane with the title ready to type.
            let kind = ItemKind(rawValue: p[0] == "openNewTask" ? "task" : arg(p, 1)) ?? .task
            let parent = arg(p, 2).isEmpty ? nil : taskNamed(arg(p, 2))?.id
            let id = store.newItem(kind, parentID: parent, start: day(arg(p, 3)))
            check(id != nil, "new \(kind.title) \(parent != nil ? "inside \(arg(p, 2))" : "")")
            done(1.0)

        case "addItem":
            // addItem|kind|title|start|end|category|tags|parent title|start time|end time
            guard let kind = ItemKind(rawValue: arg(p, 1)), let s = day(arg(p, 3)), let e = day(arg(p, 4)),
                  let cat = store.categories.first(where: { $0.name == arg(p, 5) }) else {
                check(false, "addItem arguments"); done(0.1); return
            }
            let parent = arg(p, 7).isEmpty ? nil : taskNamed(arg(p, 7))?.id
            let err = store.saveTaskDraft(TaskDraft(taskID: nil, title: arg(p, 2), start: s, end: e, categoryID: cat.id,
                                                    tags: Tags.parse(arg(p, 6)), parentID: parent,
                                                    startTime: arg(p, 8), endTime: arg(p, 9), kind: kind))
            check(err == nil, "created \(kind.title) \(arg(p, 2)) \(err ?? "")")
            done(0.4)

        case "link":
            // link|from title|to title|FS
            guard let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)) else { check(false, "link: items"); done(0.1); return }
            let id = store.addDependency(from: a.id, to: b.id, type: DependencyType(rawValue: arg(p, 3)) ?? .finishToStart)
            check(id != nil, "arrow \(arg(p, 1)) → \(arg(p, 2)) \(store.linkProblem(from: a.id, to: b.id) ?? "")")
            done(0.4)

        case "expectNoLink":
            // expectNoLink|from|to : adding this arrow must be refused.
            guard let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)) else { check(false, "expectNoLink: items"); done(0.1); return }
            let problem = store.linkProblem(from: a.id, to: b.id)
            check(problem != nil, "arrow \(arg(p, 1)) → \(arg(p, 2)) refused: \(problem ?? "allowed!")")
            done(0.1)

        case "expectLinks":
            // expectLinks|count|from>to:FS,...  (in memory and on disk)
            let mem = store.dependencies.map { "\(store.task($0.from)?.title ?? "?")>\(store.task($0.to)?.title ?? "?"):\($0.type.rawValue)" }
            var diskCount = -1
            if case .loaded(let data) = store.persistence.load() { diskCount = data.content.dependencies.count }
            let want = arg(p, 2).split(separator: ",").map(String.init)
            check(mem.count == Int(arg(p, 1)) && diskCount == mem.count && Set(want).isSubset(of: Set(mem)),
                  "arrows = \(mem) (on disk \(diskCount); expected \(arg(p, 1)) incl. \(want))")
            done(0.1)

        case "linkStyle":
            // linkStyle|from|to|#hex|width|type
            guard let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)),
                  let d = store.dependencies.first(where: { $0.from == a.id && $0.to == b.id }) else { check(false, "linkStyle: no arrow"); done(0.1); return }
            if !arg(p, 3).isEmpty { store.setDependencyColor(d.id, arg(p, 3)) }
            if let w = Double(arg(p, 4)) { store.setDependencyWidth(d.id, w) }
            if let t = DependencyType(rawValue: arg(p, 5)) { store.setDependencyType(d.id, t) }
            done(0.4)

        case "reverseLink":
            if let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)),
               let d = store.dependencies.first(where: { $0.from == a.id && $0.to == b.id }) { store.reverseDependency(d.id) }
            else { check(false, "reverseLink: no arrow") }
            done(0.4)

        case "selectLink":
            if let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)),
               let d = store.dependencies.first(where: { $0.from == a.id && $0.to == b.id }) { store.openLink(d.id) }
            done(0.6)

        case "dragLink":
            // dragLink|from title|side|to title|side|snapshot : points at the item, presses the connector
            // handle on that side (start, end, top or bottom) and drags onto that side of the other item,
            // like a pointer would.
            dragLink(from: arg(p, 1), fromSide: side(arg(p, 2)), to: arg(p, 3), toSide: side(arg(p, 4)),
                     snapshotName: arg(p, 5), done: done)

        case "linkSide":
            // linkSide|from|to|exit side|entry side : sets the sides in the details pane's way.
            guard let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)),
                  let d = store.dependencies.first(where: { $0.from == a.id && $0.to == b.id }) else { check(false, "linkSide: no arrow"); done(0.1); return }
            if !arg(p, 3).isEmpty { store.setDependencySide(d.id, exit: true, side(arg(p, 3))) }
            if !arg(p, 4).isEmpty { store.setDependencySide(d.id, exit: false, side(arg(p, 4))) }
            done(0.4)

        case "expectLinkSides":
            // expectLinkSides|from|to|exit side|entry side|type : in memory, on disk and as drawn.
            guard let a = taskNamed(arg(p, 1)), let b = taskNamed(arg(p, 2)),
                  let d = store.dependencies.first(where: { $0.from == a.id && $0.to == b.id }) else { check(false, "expectLinkSides: no arrow"); done(0.1); return }
            var disk: Dependency?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.dependencies.first { $0.id == d.id } }
            let drawn = chart?.model.links.first { $0.id == d.id }
            let want = (side(arg(p, 3)), side(arg(p, 4)))
            var ok = d.exitSide == want.0 && d.entrySide == want.1
                && disk?.exitSide == want.0 && disk?.entrySide == want.1
                && drawn?.exitSide == want.0 && drawn?.entrySide == want.1
            if !arg(p, 5).isEmpty { ok = ok && d.type.rawValue == arg(p, 5) }
            var route = ""
            if let chart, let drawn, let pts = chart.linkPoints(drawn), let fa = chart.itemFrame(a.id), let fb = chart.itemFrame(b.id) {
                // The route must start and end on the chosen sides.
                let first = pts[0], last = pts[pts.count - 1]
                let pa = GanttChartView.point(of: fa, side: want.0), pb = GanttChartView.point(of: fb, side: want.1)
                ok = ok && hypot(first.x - pa.x, first.y - pa.y) < 0.5 && hypot(last.x - pb.x, last.y - pb.y) < 0.5
                route = pts.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " ")
            } else { ok = false }
            check(ok, "arrow \(arg(p, 1)) → \(arg(p, 2)) leaves its \(d.exitSide.word), arrives at its \(d.entrySide.word), \(d.type.rawValue) (on disk \(disk.map { "\($0.exitSide.word)/\($0.entrySide.word)" } ?? "missing")) route \(route)")
            done(0.1)

        case "openInspector":
            if let t = taskNamed(arg(p, 1)) { store.openInspector(t.id) }
            done(0.8)

        case "hideInspector":
            store.inspectorVisible = false
            done(0.6)

        case "expectKind":
            // expectKind|title|group|task|milestone (as shown) and whether it's drawn on a task's row
            let t = taskNamed(arg(p, 1))
            let k = t.map { store.kind(of: $0.id) }
            check(k?.rawValue == arg(p, 2), "\(arg(p, 1)) is a \(k?.rawValue ?? "missing") (expected \(arg(p, 2)))")
            done(0.1)

        case "expectShown":
            // expectShown|title|start|end|startTime|endTime : dates and times as shown (in the time zone being viewed)
            let t = taskNamed(arg(p, 1)).flatMap { store.shown($0.id) }
            let d = taskNamed(arg(p, 1)).flatMap { store.displayDates($0.id) }
            let got = "\(d?.start.iso ?? "-")…\(d?.end.iso ?? "-") \(t?.startTime ?? "")–\(t?.endTime ?? "")"
            let want = "\(day(arg(p, 2))?.iso ?? arg(p, 2))…\(day(arg(p, 3))?.iso ?? arg(p, 3)) \(arg(p, 4))–\(arg(p, 5))"
            check(got == want, "\(arg(p, 1)) shows \(got) in \(store.viewZoneID) (expected \(want))")
            done(0.1)

        case "timeZone":
            // timeZone|Asia/Tokyo or timeZone|system
            TimeZoneSettings.shared.overrideID = arg(p, 1) == "system" ? nil : arg(p, 1)
            done(0.8)

        case "setTimes":
            if let t = taskNamed(arg(p, 1)) {
                let err = store.setTimes(t.id, start: arg(p, 2), end: arg(p, 3))
                check(err == nil, "set times of \(arg(p, 1)) to \(arg(p, 2))–\(arg(p, 3)) \(err ?? "")")
            }
            done(0.4)

        case "setKind":
            if let t = taskNamed(arg(p, 1)), let k = ItemKind(rawValue: arg(p, 2)) {
                let err = store.setKind(t.id, k)
                check((err == nil) == (arg(p, 3) != "refused"), "\(arg(p, 1)) → \(k.title): \(err ?? "done")")
            }
            done(0.4)

        case "setParent":
            if let t = taskNamed(arg(p, 1)) {
                let err = store.setParent(t.id, arg(p, 2).isEmpty ? nil : taskNamed(arg(p, 2))?.id)
                check(err == nil, "\(arg(p, 1)) inside \(arg(p, 2).isEmpty ? "top level" : arg(p, 2)) \(err ?? "")")
            }
            done(0.4)

        case "deleteItem":
            if let t = taskNamed(arg(p, 1)) { store.deleteTask(t.id) }
            done(0.4)

        case "expectCount":
            check(store.tasks.count == Int(arg(p, 1)), "\(store.tasks.count) items (expected \(arg(p, 1)))")
            done(0.1)

        case "workspaceTab":
            // workspaceTab|folder name : switches tabs like a click on the tab.
            if let e = app?.workspaces.entries.first(where: { $0.name == arg(p, 1) }) { app?.workspaces.select(e.path) }
            done(1.2)

        case "moveWorkspaceFolder":
            // moveWorkspaceFolder|name|new name : renames the folder while the app is open, then does
            // what happens when you come back to the app.
            guard let ws = app?.workspaces, let e = ws.entries.first(where: { $0.name == arg(p, 1) }) else {
                check(false, "moveWorkspaceFolder: no tab \(arg(p, 1))"); done(0.1); return
            }
            let dest = e.url.deletingLastPathComponent().appendingPathComponent(arg(p, 2), isDirectory: true)
            do { try FileManager.default.moveItem(at: e.url, to: dest) } catch { check(false, "move: \(error.localizedDescription)") }
            ws.checkFolders()
            done(1.2)

        case "newWorkspaceFolder":
            // newWorkspaceFolder|name : what New Workspace… does with a folder chosen in its panel. The folder
            // (made next to the current workspace, with a file of someone else's in it) must itself become
            // the workspace, in a tab with its name, with nothing made inside it but the data file.
            guard let ws = app?.workspaces else { check(false, "newWorkspaceFolder: no workspaces"); done(0.1); return }
            let dir = store.workspaceURL.deletingLastPathComponent().appendingPathComponent(arg(p, 1), isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? "not DaySpindle's\n".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            let problem = ws.useAsWorkspace(dir)
            let name = arg(p, 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.store.persist()
                let inside = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
                let folders = inside.filter { n in
                    var d: ObjCBool = false
                    return FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path, isDirectory: &d) && d.boolValue
                }
                self.check(problem == nil && self.store.workspaceName == name && ws.entries.last?.name == name,
                           "New Workspace… uses “\(name)” itself: tab “\(self.store.workspaceName)” \(problem ?? "")")
                self.check(inside.contains(Persistence.fileName) && inside.contains("notes.txt") && folders.isEmpty,
                           "saved in the chosen folder itself, nothing made inside it: \(inside)")
                done(0.3)
            }

        case "expectSavedIn":
            // expectSavedIn|folder name : the data file is in that folder, and nothing was recreated elsewhere.
            let url = store.persistence.fileURL
            check(url.deletingLastPathComponent().lastPathComponent == arg(p, 1) && FileManager.default.fileExists(atPath: url.path),
                  "saving to \(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent) (expected \(arg(p, 1)))")
            done(0.1)

        case "expectFolderGone":
            let gone = !FileManager.default.fileExists(atPath: store.workspaceURL.deletingLastPathComponent().appendingPathComponent(arg(p, 1)).path)
            check(gone, "no folder \(arg(p, 1)) was recreated")
            done(0.1)

        case "expectLegacyData":
            // expectLegacyData|<folder>: File › Import Tasks from DaySpindle 2.0… finds the old data
            // file in this folder of ~/Library/Application Support.
            let folder = Persistence.legacyFileURL.deletingLastPathComponent().lastPathComponent
            check(Workspaces.legacyDataExists && folder == arg(p, 1), "DaySpindle 2.0 data found in \(folder) (expected \(arg(p, 1)))")
            done(0.1)

        case "expectWorkspace":
            check(app?.workspaces.activeEntry?.name == arg(p, 1) && store.workspaceName == arg(p, 1),
                  "workspace \(app?.workspaces.activeEntry?.name ?? "none") (expected \(arg(p, 1))), \(store.tasks.count) items")
            done(0.1)

        case "editTask":
            if let t = taskNamed(arg(p, 1)) { store.beginEdit(t.id) }
            done(0.8)

        case "type":
            typeText(arg(p, 1))
            done(0.3)

        case "key":
            pressKey(arg(p, 1))
            done(0.5)

        case "click":
            if let x = Double(arg(p, 1)), let y = Double(arg(p, 2)) {
                click(in: window, at: NSPoint(x: x, y: y))
            }
            done(0.6)

        case "clickPopover":
            if let pop = NSApp.windows.first(where: { $0.isVisible && $0 != window && $0.className.contains("Popover") }),
               let x = Double(arg(p, 1)), let y = Double(arg(p, 2)) {
                click(in: pop, at: NSPoint(x: x, y: y))
            } else { record("  (no popover open)") }
            done(0.6)

        case "showOnlyCategory":
            // Same as ⌘-click or the row menu's “Show Only …”.
            if let c = store.categories.first(where: { $0.name == arg(p, 1) }) { store.showOnlyCategory(c.id) }
            done(0.5)

        case "expectShownCategories":
            let expected = arg(p, 1).split(separator: ",").map(String.init)
            let actual = store.shownCategories.map(\.name)
            var disk: [UUID]?
            if case .loaded(let data) = store.persistence.load() { disk = data.hiddenCategories }
            let diskShown = store.categories.filter { !(disk ?? []).contains($0.id) }.map(\.name)
            check(actual == expected && diskShown == expected,
                  "checked categories = \(actual) (on disk \(diskShown); expected \(expected))")
            done(0.1)

        case "selectTag":
            store.selectTag(arg(p, 1), additive: arg(p, 2) == "add")
            done(0.5)

        case "clearFilters":
            store.clearFilters()
            done(0.5)

        case "select":
            store.selectedTaskID = taskNamed(arg(p, 1))?.id
            done(0.3)

        case "setWindow":
            if let s = day(arg(p, 1)), let e = day(arg(p, 2)) {
                store.setWindowStart(s)
                store.setWindowEnd(e)
            }
            done(0.6)

        case "setWindowStart":
            if let s = day(arg(p, 1)) { store.setWindowStart(s) }
            done(0.6)

        case "setWindowEnd":
            if let e = day(arg(p, 1)) { store.setWindowEnd(e) }
            done(0.6)

        case "today":
            store.goToToday()
            done(0.6)

        case "drag":
            drag(title: arg(p, 1), mode: arg(p, 2), days: Int(arg(p, 3)) ?? 0, snapshotName: arg(p, 4), done: done)

        case "sample":
            sample(title: arg(p, 1))
            done(0.1)

        case "expectRows":
            let expected = Set(arg(p, 1).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            let actual = Set(chart?.model.rows.map(\.title) ?? [])
            check(expected == actual, "visible rows = \(actual.sorted()) (expected \(expected.sorted()))")
            done(0.1)

        case "complete":
            // complete|title|on/off : what Mark as Completed (⇧⌘C) does with the item selected.
            guard let t = taskNamed(arg(p, 1)) else { check(false, "complete: no item \(arg(p, 1))"); done(0.1); return }
            store.selectedTaskID = t.id
            if (arg(p, 2) == "on") != t.isCompleted { app?.toggleCompleted(nil) }
            done(0.4)

        case "expectCompleted":
            // expectCompleted|title|yes/no : in memory, on disk and as drawn.
            guard let t = taskNamed(arg(p, 1)) else { check(false, "expectCompleted: no item \(arg(p, 1))"); done(0.1); return }
            var disk: Bool?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.tasks.first { $0.id == t.id }?.isCompleted }
            let drawn = chart?.model.rows.first { $0.id == t.id }?.completed ?? chart?.model.rows.flatMap(\.marks).first { $0.id == t.id }?.completed
            let want = arg(p, 1 + 1) == "yes"
            // Drawn (when it's in the list being shown) as completed or not.
            check(t.isCompleted == want && disk == want && (drawn == nil || drawn == want),
                  "\(arg(p, 1)) completed: \(t.isCompleted) (on disk \(disk.map(String.init) ?? "?"), drawn \(drawn.map(String.init) ?? "?"); expected \(want))")
            done(0.1)

        case "showArchive":
            // showArchive|on/off : clicks Archive or All Items in the sidebar.
            if arg(p, 1) == "on" { store.showArchive(true) } else { store.clearFilters() }
            done(0.4)

        case "expectArchiveCount":
            check(store.archiveCount == Int(arg(p, 1)), "Archive holds \(store.archiveCount) items (expected \(arg(p, 1)))")
            done(0.1)

        case "moveBy":
            // moveBy|title|±n : Move Up / Move Down (⌥⌘↑ / ⌥⌘↓).
            if let t = taskNamed(arg(p, 1)), let n = Int(arg(p, 2)) { store.moveTask(t.id, by: n) }
            done(0.3)

        case "expectOutline":
            // expectOutline|Parent;-Child;--Grandchild;Other : row order and indentation in the task list.
            let expected = arg(p, 1).split(separator: ";").map(String.init)
            let actual = (chart?.model.rows ?? []).map { String(repeating: "-", count: $0.depth) + $0.title }
            check(expected == actual, "task list outline = \(actual.joined(separator: "; ")) (expected \(expected.joined(separator: "; ")))")
            done(0.1)

        case "expectParent":
            // expectParent|child|parent (or "none"), in the app and on disk.
            let child = taskNamed(arg(p, 1))
            let want = arg(p, 2) == "none" ? nil : taskNamed(arg(p, 2))?.id
            var disk: TaskItem?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.tasks.first { $0.title == arg(p, 1) } }
            check(child != nil && child?.parentID == want && disk?.parentID == want,
                  "\(arg(p, 1)) is under \(arg(p, 2)) (in app and on disk)")
            done(0.1)

        case "clickChevron":
            clickChevron(title: arg(p, 1))
            done(0.6)

        case "expectAligned":
            expectAligned()
            done(0.1)

        case "clickLabeled":
            // Clicks a control found by its accessibility label, like a pointer would.
            let target: NSWindow
            switch arg(p, 2) {
            case "sheet": target = window.attachedSheet ?? window
            case "popover": target = popoverWindow ?? window
            case "settings": target = NSApp.windows.first { $0.title == "DaySpindle Settings" } ?? window
            default: target = window
            }
            if arg(p, 2) == "popover" && popoverWindow == nil, let last = lastClicked {
                // Another app took focus and the popover closed; open it again.
                record("  (popover was closed; clicking “\(last.name)” again)")
                if let c = controlFrame(last.name, in: last.window) {
                    mouse(.leftMouseDown, NSPoint(x: c.midX, y: c.midY), in: last.window)
                    mouse(.leftMouseUp, NSPoint(x: c.midX, y: c.midY), in: last.window)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.run(p, done: done) }
                lastClicked = nil
                return
            }
            if let c = controlFrame(arg(p, 1), in: target) {
                lastClicked = (arg(p, 1), target)
                mouse(.leftMouseDown, NSPoint(x: c.midX, y: c.midY), in: target)
                mouse(.leftMouseUp, NSPoint(x: c.midX, y: c.midY), in: target)
                // When another app is in front, a click on a text field may only bring the window
                // forward; put the typing focus where a click would.
                if let hit = target.contentView?.superview?.hitTest(NSPoint(x: c.midX, y: c.midY)),
                   let field = sequence(first: hit, next: { $0.superview }).first(where: { $0 is NSTextView || $0 is NSTextField }) {
                    let editor = (target.firstResponder as? NSTextView)
                    let focused = target.firstResponder === field || (editor != nil && (editor === field || editor?.delegate === field as AnyObject))
                    if !focused {
                        target.makeFirstResponder(field)
                        record("  (focused the field directly)")
                    }
                }
                record("  clicked “\(arg(p, 1))” at (\(Int(c.midX)), \(Int(target.frame.height - c.midY)))")
            } else {
                check(false, "no control labeled “\(arg(p, 1))”")
            }
            done(0.7)

        case "expectLabel":
            // expectLabel|text|present|absent : searches the window's accessibility tree.
            let found = controlFrame(arg(p, 1), in: window, anyRole: true) != nil
            let want = arg(p, 2) != "absent"
            check(found == want, "“\(arg(p, 1))” is \(found ? "shown" : "not shown") in the window")
            done(0.1)

        case "expectPreset":
            // expectPreset|1 Month : the window matches the preset and keeps its first day.
            let want = WindowPreset.allCases.first { $0.title == arg(p, 1) }
            let current = store.currentPreset
            check(want != nil && current == want,
                  "range \(store.window.start)…\(store.window.end) (\(store.window.dayCount) days) is preset \(current?.title ?? "none") (expected \(arg(p, 1)))")
            done(0.1)

        case "expectWindowStartAfter":
            if let d = day(arg(p, 1)) { check(store.window.start > d, "first visible day \(store.window.start) is after \(d)") }
            done(0.1)

        case "expectWindowStartBefore":
            if let d = day(arg(p, 1)) { check(store.window.start < d, "first visible day \(store.window.start) is before \(d)") }
            done(0.1)

        case "expectWindowStart":
            if let d = day(arg(p, 1)) { check(store.window.start == d, "first visible day \(store.window.start) (expected \(d))") }
            done(0.1)

        case "dragDivider":
            dragDivider(arg(p, 1), dx: CGFloat(Double(arg(p, 2)) ?? 0), done: done)

        case "expectPaneWidths":
            // expectPaneWidths|sidebar|tasks (measured from the laid-out views)
            let (sw, tw) = paneWidths()
            let wantS = CGFloat(Double(arg(p, 1)) ?? -1), wantT = CGFloat(Double(arg(p, 2)) ?? -1)
            check(abs(sw - wantS) <= 1 && abs(tw - wantT) <= 1,
                  "sidebar \(Int(sw)) pt, task list \(Int(tw)) pt (expected \(Int(wantS)), \(Int(wantT)))")
            done(0.1)

        case "scrollTimeline":
            if let chart {
                let clip = chart.scrollView.contentView
                let maxX = max(0, chart.documentView.frame.width - clip.bounds.width)
                let x = arg(p, 1) == "end" ? maxX : (arg(p, 1) == "start" ? 0 : min(maxX, CGFloat(Double(arg(p, 1)) ?? 0)))
                clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
                chart.scrollView.reflectScrolledClipView(clip)
                record("  scrolled the timeline to x = \(Int(x)) of \(Int(maxX))")
            }
            done(0.5)

        case "expectTaskListPinned":
            expectTaskListPinned()
            done(0.1)

        case "expectTodayColumn":
            expectTodayColumn()
            done(0.1)

        case "appearance":
            // Same path as View › Appearance and the Settings window.
            if let mode = AppearanceMode(rawValue: arg(p, 1)) { AppearanceSettings.shared.mode = mode }
            done(1.0)

        case "menu":
            // menu|View|Appearance|Dark : performs a real main-menu item by its titles.
            performMenu(Array(p.dropFirst()))
            done(1.0)

        case "expectMode":
            // expectMode|light|dark|system-follows
            let dark = window.effectiveAppearance.isDark
            switch arg(p, 1) {
            case "system-follows":
                let systemDark = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
                check(NSApp.appearance == nil && dark == systemDark,
                      "System mode: app appearance not pinned (\(NSApp.appearance?.name.rawValue ?? "nil")), window is \(dark ? "dark" : "light"), macOS is \(systemDark ? "Dark" : "Light")")
            default:
                check(dark == (arg(p, 1) == "dark"), "window appearance is \(dark ? "dark" : "light") (expected \(arg(p, 1)))")
            }
            done(0.1)

        case "expectPixels":
            // expectPixels|light|dark : sidebar, toolbar and chart backgrounds in the rendered window.
            if let rep = render(window), let frameView = window.contentView?.superview {
                let scale = CGFloat(rep.pixelsWide) / frameView.bounds.width
                let wantDark = arg(p, 1) == "dark"
                for (name, x, y) in [("sidebar", 100.0, 500.0), ("toolbar", window.frame.width / 2 + 60, 8.0),
                                     ("chart", window.frame.width - 120, window.frame.height - 60)] {
                    let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.rgb
                    let l = c?.luminance ?? 0.5
                    check(wantDark ? l < 0.06 : l > 0.8, "\(name) background renders \(wantDark ? "dark" : "light"): \(c?.hex ?? "?")")
                }
            }
            done(0.1)

        case "settings":
            app?.showSettings(nil)
            done(1.0)

        case "snapshotDuringNextDrag":
            pendingSnapshot = arg(p, 1)
            done(0.1)

        case "dragRow":
            // dragRow|title|rows : drags a task-list row up (negative) or down by whole rows.
            dragRow(title: arg(p, 1), rows: Double(arg(p, 2)) ?? 0, done: done)

        case "dragCategory":
            // dragCategory|name|rows : drags a sidebar category up or down.
            dragCategory(name: arg(p, 1), rows: Double(arg(p, 2)) ?? 0, done: done)

        case "categoryNote":
            // Same action as right-click › Add Note… / Edit Note… on a category.
            if let c = store.categories.first(where: { $0.name == arg(p, 1) }) { store.beginCategoryNote(c.id) }
            done(0.8)

        case "expectCategoryNote":
            let want = arg(p, 2) == "none" ? nil : arg(p, 2)
            let mem = store.categories.first { $0.name == arg(p, 1) }?.notes
            var disk: String??
            if case .loaded(let data) = store.persistence.load() { disk = data.content.categories.first { $0.name == arg(p, 1) }.map { $0.notes } }
            check(mem == want && disk == .some(want),
                  "\(arg(p, 1)) note = \(mem ?? "none") (on disk \((disk ?? nil) ?? "none"); expected \(want ?? "none"))")
            done(0.1)

        case "openCategory":
            if let c = store.categories.first(where: { $0.name == arg(p, 1) }) { store.beginEditCategory(c.id) }
            done(0.8)

        case "selectAll":
            // Straight to the focused field of the sheet (or window), whichever app is in front.
            let w = window.attachedSheet ?? window
            if w.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil) != true {
                record("  (nothing to select)")
            }
            done(0.2)

        case "expectTaskDetails":
            // expectTaskDetails|title|start time|end time|location|notes  (in the app and on disk)
            let mem = taskNamed(arg(p, 1))
            var disk: TaskItem?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.tasks.first { $0.title == arg(p, 1) } }
            let want = [arg(p, 2), arg(p, 3), arg(p, 4), arg(p, 5)]
            let describe = { (t: TaskItem?) in [t?.startTime ?? "", t?.endTime ?? "", t?.location ?? "", t?.notes ?? ""] }
            check(describe(mem) == want && describe(disk) == want,
                  "\(arg(p, 1)) times/location/notes = \(describe(mem)) (on disk \(describe(disk)); expected \(want))")
            done(0.1)

        case "expectRowDetail":
            let row = chart?.model.rows.first { $0.title == arg(p, 1) }
            check(row?.detail == arg(p, 2), "\(arg(p, 1)) shows “\(row?.detail ?? "?")” after its dates (expected “\(arg(p, 2))”)")
            done(0.1)

        case "expectToolTip":
            if let chart, let i = chart.model.rows.firstIndex(where: { $0.title == arg(p, 1) }) {
                let pt = NSPoint(x: 40, y: CGFloat(i) * GanttChartView.rowHeight - chart.scrollOffset.y + 20)
                let tip = chart.left.view(chart.left, stringForToolTip: 0, point: pt, userData: nil)
                check(tip.contains(arg(p, 2)), "hovering \(arg(p, 1)) shows: \(tip.replacingOccurrences(of: "\n", with: " / "))")
            } else { check(false, "expectToolTip: no row \(arg(p, 1))") }
            done(0.1)

        case "expectRowColor":
            let row = chart?.model.rows.first { $0.title == arg(p, 1) }
            var disk: TaskItem?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.tasks.first { $0.title == arg(p, 1) } }
            let want = arg(p, 2)
            let diskOK = want == "category" ? disk?.colorHex == nil : disk?.colorHex == want
            let expectedRow = want == "category"
                ? store.task(taskNamed(arg(p, 1))?.id ?? UUID()).flatMap { store.category($0.categoryID)?.colorHex }
                : want
            check(row?.colorHex == expectedRow && diskOK,
                  "\(arg(p, 1)) bar color \(row?.colorHex ?? "?") (expected \(want == "category" ? "its category's \(expectedRow ?? "?")" : want); saved \(disk?.colorHex ?? "none"))")
            done(0.1)

        case "headerMenu":
            // headerMenu|today|other , item title[, submenu item] : right-click the header and choose an item.
            headerMenu(onToday: arg(p, 1) == "today", path: Array(p.dropFirst(2)))
            done(0.6)

        case "expectTodayColor":
            check(store.todayColorHex == arg(p, 1) && UserDefaults.standard.string(forKey: TodayStyle.defaultsKey) == arg(p, 1),
                  "Today color is \(store.todayColorHex) (expected \(arg(p, 1)))")
            done(0.1)

        case "expectWeek":
            // expectWeek|yyyy-MM-dd|number : week number in the week bar for the current first weekday.
            if let d = day(arg(p, 1)), let n = Int(arg(p, 2)) {
                let got = Weeks.number(of: d, firstWeekday: store.firstWeekday)
                let ws = Weeks.start(of: d, firstWeekday: store.firstWeekday)
                check(got == n, "\(d) is in Week \(got), which starts \(DayFormat.weekdayLong[ws.weekday]) \(ws) (expected Week \(n); first day \(DayFormat.weekdayLong[store.firstWeekday]))")
            }
            done(0.1)

        case "expectMonthLabel":
            if let d = day(arg(p, 1)) {
                check(DayFormat.monthYear(d) == arg(p, 2), "month label for \(d) is “\(DayFormat.monthYear(d))” (expected “\(arg(p, 2))”)")
            }
            done(0.1)

        case "expectHeaderTint":
            expectHeaderTint()
            done(0.1)

        case "scrollTime":
            // scrollTime|points : a sideways scroll (trackpad) of this many points; positive = later.
            scrollTime(points: Double(arg(p, 1)) ?? 0)
            done(0.6)

        case "expectInstructionsAtBottom":
            if let v = ControlMarkers.view("Instructions", in: window) {
                let f = v.convert(v.bounds, to: nil)
                let sidebarWidth = paneWidths().0
                check(f.minY < 16 && f.minX < 20 && f.maxX <= sidebarWidth + 1,
                      "instructions sit at the bottom left: \(Int(f.minX)),\(Int(f.minY)) to \(Int(f.maxX)),\(Int(f.maxY)) (window \(Int(window.frame.width))×\(Int(window.frame.height)))")
            } else { check(false, "instructions not found") }
            done(0.1)

        case "snapshotSettings":
            if let w = NSApp.windows.first(where: { $0.title == "DaySpindle Settings" && $0.isVisible }) {
                snapshot(w, name: arg(p, 1))
            } else { record("  (settings window not open)") }
            done(0.2)

        case "closeSettings":
            NSApp.windows.first { $0.title == "DaySpindle Settings" }?.performClose(nil)
            done(0.4)

        case "moveOut":
            // Same action as the row menu's “Move Out of …”.
            if let t = taskNamed(arg(p, 1)) { store.moveOutOfParent(t.id) }
            done(0.5)

        case "expectNotCandidate":
            // expectNotCandidate|task|other : the editor's parent list for `task` doesn't offer `other`.
            if let t = taskNamed(arg(p, 1)) {
                let titles = store.parentCandidates(for: t.id).map(\.task.title)
                let banned = arg(p, 2).split(separator: ",").map(String.init)
                check(!titles.contains(arg(p, 1)) && banned.allSatisfy { !titles.contains($0) },
                      "parent choices for \(arg(p, 1)) exclude itself and \(banned): \(titles)")
            }
            done(0.1)

        case "expectDockIcon":
            let variant = app?.dockIconVariant ?? ""
            var center: RGB?
            if let img = NSApp.applicationIconImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                let px = rep.pixelsWide
                center = rep.colorAt(x: px * 17 / 100, y: px * 50 / 100)?.rgb
            }
            let l = center?.luminance ?? 0.5
            let want = arg(p, 1) == "system" ? (NSApp.effectiveAppearance.isDark ? "dark" : "light") : arg(p, 1)
            let ok = variant == want && (want == "dark" ? l < 0.1 : l > 0.7)
            check(ok, "Dock icon is the \(variant) variant (icon background \(center?.hex ?? "?"))")
            done(0.1)

        case "expectTask":
            // Checks both the in-memory store and the JSON file on disk.
            guard let s = day(arg(p, 2)), let e = day(arg(p, 3)) else { check(false, "expectTask args"); done(0.1); return }
            let mem = taskNamed(arg(p, 1))
            var disk: TaskItem?
            if case .loaded(let data) = store.persistence.load() { disk = data.content.tasks.first { $0.title == arg(p, 1) } }
            check(mem?.start == s && mem?.end == e,
                  "\(arg(p, 1)) in app: \(mem.map { "\($0.start)…\($0.end)" } ?? "missing") (expected \(s)…\(e))")
            check(disk?.start == s && disk?.end == e,
                  "\(arg(p, 1)) on disk: \(disk.map { "\($0.start)…\($0.end)" } ?? "missing") (expected \(s)…\(e))")
            done(0.1)

        case "expectWindow":
            guard let s = day(arg(p, 1)), let e = day(arg(p, 2)) else { check(false, "expectWindow args"); done(0.1); return }
            var diskWindow: DateWindow?
            if case .loaded(let data) = store.persistence.load() { diskWindow = data.window }
            check(store.window == DateWindow(start: s, end: e), "window in app \(store.window.start)…\(store.window.end) (expected \(s)…\(e))")
            check(diskWindow == DateWindow(start: s, end: e), "window on disk \(diskWindow.map { "\($0.start)…\($0.end)" } ?? "missing")")
            done(0.1)

        case "expectToday":
            if let d = day(arg(p, 1)) { check(store.today == d, "today is \(store.today) (expected \(d))") }
            done(0.1)

        case "expectSheet":
            let open = window.attachedSheet != nil
            check(open == (arg(p, 1) == "open"), "sheet is \(open ? "open" : "closed")")
            done(0.1)

        case "editCategory":
            // editCategory|old name|new name|#hex — same path as the category editor's Save.
            if let c = store.categories.first(where: { $0.name == arg(p, 1) }) {
                let err = store.saveCategoryDraft(CategoryDraft(categoryID: c.id, name: arg(p, 2), colorHex: arg(p, 3)))
                check(err == nil, "edited category \(arg(p, 1)) → \(arg(p, 2)) \(arg(p, 3)) \(err ?? "")")
            } else { check(false, "no category \(arg(p, 1))") }
            done(0.4)

        case "expectCategories":
            let expected = arg(p, 1).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let actual = store.categories.map { "\($0.name)=\($0.colorHex)" }
            check(Set(expected) == Set(actual), "categories = \(actual) (expected \(expected))")
            done(0.1)

        case "expectTags":
            let expected = arg(p, 1).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            check(Set(expected) == Set(store.tags), "tags = \(store.tags) (expected \(expected))")
            done(0.1)

        case "undo":
            // The same as Edit › Undo.
            record("  undo “\(store.undo.undoActionName)” (first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"))")
            app?.performUndo()
            done(0.5)

        case "focusTimeline":
            if let chart { window.makeFirstResponder(chart.timeline) }
            done(0.2)

        case "closePopovers":
            for w in NSApp.windows where w.isVisible && w != window && w.className.contains("Popover") { w.orderOut(nil) }
            done(0.3)

        case "dumpViews":
            if let frameView = window.contentView?.superview,
               let desc = frameView.perform(Selector(("_subtreeDescription")))?.takeUnretainedValue() as? String {
                var layers = ""
                func walk(_ l: CALayer, _ depth: Int) {
                    guard depth < 7 else { return }
                    layers += String(repeating: "  ", count: depth)
                        + "\(type(of: l)) frame=\(l.frame) hidden=\(l.isHidden) opacity=\(l.opacity) contents=\(l.contents != nil) bg=\(l.backgroundColor != nil) mask=\(l.mask != nil) subs=\(l.sublayers?.count ?? 0)\n"
                    for s in l.sublayers?.prefix(40) ?? [] { walk(s, depth + 1) }
                }
                if let root = window.contentView?.layer { walk(root, 0) }
                try? (desc + "\n\nLAYERS\n" + layers).write(to: outDir.appendingPathComponent("\(arg(p, 1)).txt"), atomically: true, encoding: .utf8)
                record("  saved \(arg(p, 1)).txt")
            }
            done(0.1)

        case "quit":
            // AppKit won't quit while a sheet is attached, so close any sheet first.
            store.activeSheet = nil
            record("Quitting")
            finish()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }

        default:
            record("  unknown command")
            done(0.1)
        }
    }

    // MARK: Snapshots

    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let windowImage: WindowImageFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()
    private var reportedMethod = false

    /// Captures exactly what the window server shows for this app's own window
    /// (SwiftUI layers included). Falls back to AppKit's cacheDisplay.
    private func render(_ w: NSWindow) -> NSBitmapImageRep? {
        guard let frameView = w.contentView?.superview else { return nil }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        CATransaction.flush()
        // includingWindow = 1<<3; boundsIgnoreFraming = 1<<0, bestResolution = 1<<3
        if let fn = Self.windowImage, let image = fn(.null, 1 << 3, UInt32(w.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(),
           image.width > 10 {
            if !reportedMethod { record("  (snapshots: window-server capture of the app's own window)"); reportedMethod = true }
            return NSBitmapImageRep(cgImage: image)
        }
        if !reportedMethod { record("  (snapshots: AppKit cacheDisplay fallback; SwiftUI layers may be missing)"); reportedMethod = true }
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep
    }

    private func snapshot(_ w: NSWindow, name: String) {
        guard let rep = render(w), let png = rep.representation(using: .png, properties: [:]) else {
            record("  snapshot failed"); return
        }
        let url = outDir.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        record("  saved \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
    }

    private func writeState(_ name: String) {
        let rows: [[String: Any]] = (chart?.model.rows ?? []).map { r in
            ["title": r.title, "start": r.start.iso, "end": r.end.iso, "color": r.colorHex,
             "tags": r.tags, "depth": r.depth, "hasSubtasks": r.hasChildren, "collapsed": r.collapsed,
             "kind": r.kind.rawValue, "marks": r.marks.map { "\($0.title) \($0.day.iso)" }]
        }
        let (sw, tw) = paneWidths()
        let regular = NSFont(name: Theme.regularFontName, size: 13)
        let bold = NSFont(name: Theme.boldFontName, size: 13)
        let state: [String: Any] = [
            "dataFile": store.persistence.fileURL.path,
            "bundlePath": Bundle.main.bundlePath,
            "today": store.today.iso,
            "window": ["start": store.window.start.iso, "end": store.window.end.iso, "days": store.window.dayCount],
            "filters": ["shownCategories": store.shownCategories.map(\.name),
                        "tags": Array(store.selectedTagKeys).sorted()],
            "visibleRows": rows,
            "preset": store.currentPreset?.title ?? "custom",
            "panes": ["sidebarWidth": sw, "taskListWidth": tw],
            "dockIcon": app?.dockIconVariant ?? "",
            "categories": store.categories.map { ["name": $0.name, "color": $0.colorHex] },
            "tags": store.tags,
            "taskCount": store.tasks.count,
            "appearance": ["setting": AppearanceSettings.shared.mode.rawValue,
                           "window": window.effectiveAppearance.name.rawValue,
                           "app": NSApp.effectiveAppearance.name.rawValue,
                           "systemStyle": UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light (key not set)"],
            "fonts": ["regular": regular?.fontName ?? "missing",
                      "bold": bold?.fontName ?? "missing",
                      "boldHasBoldTrait": bold.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false,
                      "chartTitleFont": Theme.nsFont(12, bold: true).fontName],
            "chart": ["dayWidth": chart?.dayWidth ?? 0, "scrollX": chart?.scrollOffset.x ?? 0],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outDir.appendingPathComponent("\(name).json"))
            record("  saved \(name).json")
        }
    }

    // MARK: Synthesized input

    private func mouse(_ type: NSEvent.EventType, _ p: NSPoint, in w: NSWindow, clicks: Int = 1) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                         pressure: type == .leftMouseUp ? 0 : 1) else { return }
        w.sendEvent(e)
    }

    /// Clicks at a point given in top-left-origin window coordinates (points).
    private func click(in w: NSWindow, at topLeft: NSPoint) {
        let p = NSPoint(x: topLeft.x, y: w.frame.height - topLeft.y)
        mouse(.leftMouseDown, p, in: w)
        mouse(.leftMouseUp, p, in: w)
    }

    /// The window that would receive typing: an open sheet, else the key window, else the main window.
    private var inputWindow: NSWindow { window.attachedSheet ?? NSApp.keyWindow ?? window }

    /// Delivers a key event like AppKit does for the key window: key equivalents
    /// (e.g. Return for the default button) first, then the first responder.
    private func deliverKey(_ e: NSEvent, to w: NSWindow) {
        if e.type == .keyDown, w.performKeyEquivalent(with: e) { return }
        w.sendEvent(e)
    }

    private func typeText(_ text: String) {
        let w = inputWindow
        record("  typing into \(w == window ? "main window" : "sheet"), first responder \(w.firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        for ch in text {
            let s = String(ch)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: w.windowNumber, context: nil, characters: s,
                                            charactersIgnoringModifiers: s, isARepeat: false, keyCode: 0) {
                    w.sendEvent(e)
                }
            }
        }
    }

    private func pressKey(_ name: String) {
        let w = inputWindow
        let table: [String: (UInt16, String)] = [
            "return": (36, "\r"), "escape": (53, "\u{1b}"), "delete": (51, "\u{7f}"),
            "down": (125, String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))),
            "left": (123, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))),
            "right": (124, String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))),
            "up": (126, String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))),
        ]
        guard let (code, chars) = table[name] else { record("  unknown key"); return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                deliverKey(e, to: w)
            }
        }
    }

    /// Draws an arrow the way a person would: moves the pointer over the item (its handles
    /// appear), presses the handle at its start or end, drags onto the other item and lets go.
    /// "start"/"end" (the arrow's ends) or a side's name.
    private func side(_ s: String) -> LinkSide {
        switch s.lowercased() {
        case "start": return .left
        case "end": return .right
        default: return LinkSide(rawValue: s.lowercased()) ?? .left
        }
    }

    private func dragLink(from: String, fromSide: LinkSide, to: String, toSide: LinkSide, snapshotName: String,
                          done: @escaping (TimeInterval) -> Void) {
        guard let chart, let a = taskNamed(from), let b = taskNamed(to),
              let aRow = chart.model.anchorRow[a.id], let ai = chart.model.rows.firstIndex(where: { $0.id == aRow }) else {
            check(false, "dragLink: \(from) or \(to) not on screen"); done(0.1); return
        }
        let row = chart.model.rows[ai]
        let over: NSPoint
        if let mark = row.marks.first(where: { $0.id == a.id }) {
            over = chart.markCenter(index: ai, mark: mark)
        } else if row.kind == .milestone {
            over = chart.milestoneCenter(index: ai, row: row)
        } else {
            // A point on the bar away from its milestone diamonds.
            let r = chart.fullBarRect(index: ai, row: row)
            let marks = row.marks.map { chart.markCenter(index: ai, mark: $0).x }
            let xs = stride(from: r.minX + 10, through: r.maxX - 10, by: 3)
            let x = xs.first { x in marks.allSatisfy { abs($0 - x) > 16 } } ?? r.midX
            over = NSPoint(x: x, y: r.midY)
        }
        if let e = NSEvent.mouseEvent(with: .mouseMoved, location: chart.windowPoint(fromDocument: over), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            chart.timeline.mouseMoved(with: e)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let h = chart.hoverItem, h.itemID == a.id,
                  let handle = chart.handles(for: h).first(where: { $0.side == fromSide }),
                  let target = chart.anchor(b.id, side: toSide) else {
                self.check(false, "dragLink: no handle on \(from) (hover \(chart.hoverItem.map { self.store.task($0.itemID)?.title ?? "?" } ?? "none"), pointer at \(Int(over.x)),\(Int(over.y)) row \(ai))")
                done(0.1); return
            }
            self.record("  handles shown on \(from): \(chart.handles(for: h).count)")
            self.mouse(.leftMouseDown, chart.windowPoint(fromDocument: handle.center), in: self.window)
            // Aim just inside the target, next to the chosen side.
            let goal = NSPoint(x: target.x - toSide.dx * 5, y: target.y - toSide.dy * 5)
            let steps = 8
            for k in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(k)) {
                    let t = CGFloat(k) / CGFloat(steps)
                    let p = NSPoint(x: handle.center.x + (goal.x - handle.center.x) * t, y: handle.center.y + (goal.y - handle.center.y) * t)
                    self.mouse(.leftMouseDragged, chart.windowPoint(fromDocument: p), in: self.window)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(steps) + 0.2) {
                let target = chart.linkDraft?.target
                self.record("  drawing arrow: target \(target.map { "\(self.store.task($0.id)?.title ?? "?") at its \($0.side.word)" } ?? "none")")
                if !snapshotName.isEmpty { self.snapshot(self.window, name: snapshotName) }
                self.mouse(.leftMouseUp, chart.windowPoint(fromDocument: goal), in: self.window)
                done(0.6)
            }
        }
    }

    /// Drags a bar with synthesized mouse events through the real timeline view.
    /// mode: move | start | end. Optionally snapshots mid-drag to capture the date preview.
    private func drag(title: String, mode: String, days: Int, snapshotName: String, retried: Bool = false,
                      done: @escaping (TimeInterval) -> Void) {
        guard let chart, let i = chart.model.rows.firstIndex(where: { $0.title == title }) else {
            check(false, "drag: no visible row \(title)"); done(0.1); return
        }
        let row = chart.model.rows[i]
        guard let bar = chart.barRect(index: i, start: row.start, end: row.end) else {
            check(false, "drag: bar for \(title) not in window"); done(0.1); return
        }
        chart.documentView.scrollToVisible(bar.rect.insetBy(dx: -chart.dayWidth * CGFloat(abs(days) + 1), dy: 0))
        let y = bar.rect.midY
        let startX: CGFloat
        switch mode {
        case "start": startX = bar.rect.minX + 2
        case "end": startX = bar.rect.maxX - 2
        default: startX = bar.rect.midX
        }
        let totalDX = CGFloat(days) * chart.dayWidth
        let toWindow = { (x: CGFloat) in chart.windowPoint(fromDocument: NSPoint(x: x, y: y)) }
        let steps = 8
        let downPoint = toWindow(startX)
        let under = window.contentView?.superview?.hitTest(downPoint)
        record("  mouse down at document x \(Int(startX)) → \(under.map { String(describing: type(of: $0)) } ?? "none"), timeline hit \(chart.timeline.hit(at: NSPoint(x: startX, y: y)))")
        mouse(.leftMouseDown, downPoint, in: window)
        for k in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(k)) {
                self.mouse(.leftMouseDragged, toWindow(startX + totalDX * CGFloat(k) / CGFloat(steps)), in: self.window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(steps) + 0.15) {
            if let d = chart.drag {
                self.record("  preview during drag: \(d.start)…\(d.end) (\(DayFormat.dayCount(d.end - d.start + 1)))")
            } else {
                self.record("  no drag session in progress\(retried ? "" : "; retrying once")")
                self.mouse(.leftMouseUp, toWindow(startX + totalDX), in: self.window)
                if !retried {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.drag(title: title, mode: mode, days: days, snapshotName: snapshotName, retried: true, done: done)
                    }
                    return
                }
            }
            if !snapshotName.isEmpty { self.snapshot(self.window, name: snapshotName) }
            self.mouse(.leftMouseUp, toWindow(startX + totalDX), in: self.window)
            done(0.6)
        }
    }

    /// Samples rendered pixels: the bar inside the Today column, the bar on another day,
    /// the Today column background, and the task's category dot in the task list.
    /// The dot is drawn with the category color through the same pipeline, so it is the
    /// reference (raw hex values shift under the display's color management).
    private func sample(title: String) {
        guard let chart, let i = chart.model.rows.firstIndex(where: { $0.title == title }) else {
            check(false, "sample: no row \(title)"); return
        }
        let row = chart.model.rows[i]
        guard let bar = chart.barRect(index: i, start: row.start, end: row.end), let rep = render(window),
              let frameView = window.contentView?.superview else { check(false, "sample: no bar"); return }
        let w = chart.model.window, dw = chart.dayWidth, today = chart.model.today

        func pixel(atWindow wp: NSPoint) -> RGB? {
            let fp = frameView.convert(wp, from: nil)
            let scale = CGFloat(rep.pixelsWide) / frameView.bounds.width
            let yTop = frameView.isFlipped ? fp.y : frameView.bounds.height - fp.y
            return rep.colorAt(x: Int(fp.x * scale), y: Int(yTop * scale))?.rgb
        }
        func timeline(_ p: NSPoint) -> RGB? { pixel(atWindow: chart.windowPoint(fromDocument: p)) }
        func same(_ a: RGB?, _ b: RGB?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02
        }

        // Category dot in the task list (center of the 9 pt dot).
        let dotRect = GanttChartView.dotRect(depth: row.depth, rowTop: CGFloat(i) * GanttChartView.rowHeight - chart.scrollOffset.y)
        let dot = pixel(atWindow: chart.left.convert(NSPoint(x: dotRect.midX, y: dotRect.midY), to: nil))
        record("  \(title): category \(row.colorHex), rendered category dot \(dot?.hex ?? "?")")

        let sampleY = bar.rect.maxY - 2.5
        if w.contains(today) && row.start <= today && today <= row.end {
            let x = (CGFloat(today - w.start) + 0.5) * dw
            let c = timeline(NSPoint(x: x, y: sampleY))
            let bg = timeline(NSPoint(x: x, y: CGFloat(i) * GanttChartView.rowHeight + 2))
            check(same(c, dot), "\(title): bar pixel inside the Today column \(c?.hex ?? "?") matches its category color \(dot?.hex ?? "?")")
            check(!same(c, bg), "\(title): Today column background \(bg?.hex ?? "?") is distinct from the bar")
        }
        if let od = (row.start...row.end).first(where: { $0 != today && w.contains($0) }) {
            let x = (CGFloat(od - w.start) + 0.5) * dw
            let c = timeline(NSPoint(x: x, y: sampleY))
            check(same(c, dot), "\(title): bar pixel on \(od) (outside Today) \(c?.hex ?? "?") matches its category color")
        }
    }

    // MARK: Task list, panes, and accessibility helpers

    private var popoverWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 != window && $0.className.contains("Popover") }
    }

    private func rendered(_ rep: NSBitmapImageRep, atWindow wp: NSPoint) -> RGB? {
        guard let frameView = window.contentView?.superview else { return nil }
        let fp = frameView.convert(wp, from: nil)
        let scale = CGFloat(rep.pixelsWide) / frameView.bounds.width
        let yTop = frameView.isFlipped ? fp.y : frameView.bounds.height - fp.y
        return rep.colorAt(x: Int(fp.x * scale), y: Int(yTop * scale))?.rgb
    }

    private func same(_ a: RGB?, _ b: RGB?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02
    }

    private func saturation(_ c: RGB?) -> Double {
        guard let c else { return 0 }
        return max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
    }

    /// Clicks the disclosure chevron of a row with a synthesized mouse click.
    private func clickChevron(title: String) {
        guard let chart, let i = chart.model.rows.firstIndex(where: { $0.title == title }),
              let r = chart.left.chevronRect(row: i) else {
            check(false, "clickChevron: \(title) has no chevron"); return
        }
        let p = chart.left.convert(NSPoint(x: r.minX + 11, y: r.minY + 13.5), to: nil)
        mouse(.leftMouseDown, p, in: window)
        mouse(.leftMouseUp, p, in: window)
        record("  clicked the chevron of \(title)")
    }

    /// Every task row lines up with its bar: same vertical center in the window, and the
    /// rendered bar at the height of the row's category dot has that category's color.
    /// Below the last row, the timeline shows no bars.
    private func expectAligned() {
        guard let chart, let rep = render(window) else { check(false, "expectAligned: no chart"); return }
        let rh = GanttChartView.rowHeight, oy = chart.scrollOffset.y
        let visible = chart.visibleDocumentRect
        var checked = 0, colorChecked = 0, geometryOff: [String] = [], colorOff: [String] = []
        for (i, row) in chart.model.rows.enumerated() {
            let top = CGFloat(i) * rh - oy
            guard top >= 0, top + rh <= chart.left.bounds.height else { continue }
            guard let bar = chart.barRect(index: i, start: row.start, end: row.end) else { continue }
            let rowCenter = chart.left.convert(NSPoint(x: 0, y: top + rh / 2), to: nil).y
            let barCenter = chart.windowPoint(fromDocument: NSPoint(x: bar.rect.midX, y: bar.rect.midY)).y
            if abs(rowCenter - barCenter) > 0.5 { geometryOff.append(row.title) }
            checked += 1
            // Only task bars are in the row's exact color (group bars are a shade darker by design).
            guard row.kind == .task else { continue }
            let dotR = GanttChartView.dotRect(depth: row.depth, rowTop: top)
            let dotP = chart.left.convert(NSPoint(x: dotR.midX, y: dotR.midY), to: nil)
            let x = min(max(bar.rect.midX, visible.minX + 4), visible.maxX - 4)
            guard bar.rect.minX + 2 < x, x < bar.rect.maxX - 2 else { continue }
            let barP = chart.windowPoint(fromDocument: NSPoint(x: x, y: bar.rect.minY + 13.5 - (rh - GanttChartView.barHeight) / 2 + 0))
            let barAtDotHeight = NSPoint(x: barP.x, y: dotP.y)
            if !same(rendered(rep, atWindow: dotP), rendered(rep, atWindow: barAtDotHeight)) { colorOff.append(row.title) }
            colorChecked += 1
        }
        check(checked > 0 && geometryOff.isEmpty && colorOff.isEmpty,
              "\(checked) task rows line up with their bars; \(colorChecked) bars in view also match their row's color (offset: \(geometryOff), color mismatch: \(colorOff))")
        let emptyTop = CGFloat(chart.model.rows.count) * rh - oy
        if emptyTop + rh / 2 < chart.left.bounds.height {
            var maxSat = 0.0
            var x = visible.minX + 3
            // The red line at the current time runs down the whole Today column: not a bar.
            let nowX = chart.model.nowMinute.map { chart.milestoneX(day: chart.model.today, minute: $0) }
            while x < visible.maxX - 3 {
                if let nowX, abs(x - nowX) < 4 { x += 5; continue }
                let wp = chart.windowPoint(fromDocument: NSPoint(x: x, y: CGFloat(chart.model.rows.count) * rh + rh / 2))
                maxSat = max(maxSat, saturation(rendered(rep, atWindow: wp)))
                x += 5
            }
            check(maxSat < 0.25, "no bars drawn below the last task row (max saturation \(String(format: "%.2f", maxSat)))")
        }
    }

    /// Measured widths: sidebar (from the chart's position) and task list.
    private func paneWidths() -> (CGFloat, CGFloat) {
        guard let chart else { return (0, 0) }
        let chartMinX = chart.convert(chart.bounds, to: nil).minX
        return (chartMinX - 1, chart.left.frame.width)
    }

    /// Drags a pane divider with synthesized mouse events: "sidebar" or "tasks".
    private func dragDivider(_ which: String, dx: CGFloat, done: @escaping (TimeInterval) -> Void) {
        guard let chart else { check(false, "dragDivider: no chart"); done(0.1); return }
        let before = paneWidths()
        let y = chart.bounds.height / 2
        let start: NSPoint
        if which == "sidebar" {
            start = chart.convert(NSPoint(x: -0.5, y: y), to: nil)
        } else {
            start = chart.convert(NSPoint(x: chart.taskListWidth - 3, y: y), to: nil)
        }
        let hit = window.contentView?.superview?.hitTest(start)
        record("  \(which) divider at window x \(Int(start.x)); view under the pointer: \(hit.map { String(describing: type(of: $0)) } ?? "none")")
        mouse(.leftMouseDown, start, in: window)
        let steps = 8
        for k in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(k)) {
                self.mouse(.leftMouseDragged, NSPoint(x: start.x + dx * CGFloat(k) / CGFloat(steps), y: start.y), in: self.window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(steps) + 0.2) {
            self.mouse(.leftMouseUp, NSPoint(x: start.x + dx, y: start.y), in: self.window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let after = self.paneWidths()
                self.record("  widths before: sidebar \(Int(before.0)), task list \(Int(before.1)); after: sidebar \(Int(after.0)), task list \(Int(after.1))")
                done(0.2)
            }
        }
    }

    /// After scrolling the timeline sideways, the task list is still in place and drawn.
    private func expectTaskListPinned() {
        guard let chart, let rep = render(window), let row = chart.model.rows.first else { check(false, "expectTaskListPinned"); return }
        let chartX = chart.convert(chart.bounds, to: nil).minX
        let leftX = chart.left.convert(chart.left.bounds, to: nil).minX
        let dotR = GanttChartView.dotRect(depth: row.depth, rowTop: -chart.scrollOffset.y)
        let dot = rendered(rep, atWindow: chart.left.convert(NSPoint(x: dotR.midX, y: dotR.midY), to: nil))
        check(chart.scrollOffset.x > 0 && abs(leftX - chartX) < 0.5 && saturation(dot) > 0.3,
              "timeline scrolled to x = \(Int(chart.scrollOffset.x)); task list still at the left edge (x \(Int(leftX - chartX))) showing \(row.title) (dot \(dot?.hex ?? "?"))")
    }

    /// The Today column is tinted in the rendered timeline; the day before is not.
    private func expectTodayColumn() {
        guard let chart, let rep = render(window) else { check(false, "expectTodayColumn"); return }
        let m = chart.model, dw = chart.dayWidth
        guard m.window.contains(m.today) else { check(false, "today \(m.today) is outside the visible range"); return }
        let rh = GanttChartView.rowHeight
        let emptyY = CGFloat(m.rows.count) * rh + 12
        let y = emptyY < chart.visibleDocumentRect.maxY - 4 ? emptyY : 3
        func at(_ d: Day) -> RGB? {
            rendered(rep, atWindow: chart.windowPoint(fromDocument: NSPoint(x: (CGFloat(d - m.window.start) + 0.5) * dw, y: y)))
        }
        let today = at(m.today)
        let other = m.window.contains(m.today - 1) ? m.today - 1 : m.today + 1
        let neighbor = at(other)
        check(tintMatches(today, background: neighbor) && !same(today, neighbor),
              "Today column \(m.today) is highlighted (\(today?.hex ?? "?")); \(other) is not (\(neighbor?.hex ?? "?"))")
    }

    /// A named control's frame in window coordinates, from its marker view (SwiftUI doesn't
    /// expose its accessibility tree to the app itself).
    private func controlFrame(_ name: String, in w: NSWindow, anyRole: Bool = false) -> NSRect? {
        guard let v = ControlMarkers.view(name, in: w) else { return nil }
        return v.convert(v.bounds, to: nil)
    }

    /// Drags a task-list row with synthesized mouse events.
    private func dragRow(title: String, rows: Double, done: @escaping (TimeInterval) -> Void) {
        guard let chart, let i = chart.model.rows.firstIndex(where: { $0.title == title }) else {
            check(false, "dragRow: no row \(title)"); done(0.1); return
        }
        let rh = GanttChartView.rowHeight
        let y0 = CGFloat(i) * rh - chart.scrollOffset.y + rh / 2
        let x = chart.left.bounds.width - 40
        let start = chart.left.convert(NSPoint(x: x, y: y0), to: nil)
        let dy = CGFloat(rows) * rh
        mouse(.leftMouseDown, start, in: window)
        let steps = 10
        for k in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(k)) {
                // Window coordinates grow upward; the list grows downward.
                self.mouse(.leftMouseDragged, NSPoint(x: start.x, y: start.y - dy * CGFloat(k) / CGFloat(steps)), in: self.window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(steps) + 0.15) {
            if let r = chart.reorder, let c = r.current {
                let before = r.slots[c].beforeID.flatMap { id in chart.model.rows.first { $0.id == id }?.title } ?? "the end of its group"
                self.record("  dragging \(title): insertion line before \(before) (\(r.slots.count) allowed places)")
            } else {
                self.record("  dragging \(title): no reorder in progress")
            }
            if !self.pendingSnapshot.isEmpty { self.snapshot(self.window, name: self.pendingSnapshot); self.pendingSnapshot = "" }
            self.mouse(.leftMouseUp, NSPoint(x: start.x, y: start.y - dy), in: self.window)
            done(0.6)
        }
    }

    /// Drags a sidebar category row with synthesized mouse events.
    private func dragCategory(name: String, rows: Double, done: @escaping (TimeInterval) -> Void) {
        guard let v = ControlMarkers.view("Category \(name)", in: window) else {
            check(false, "dragCategory: no category \(name)"); done(0.1); return
        }
        let f = v.convert(v.bounds, to: nil)
        let start = NSPoint(x: f.midX, y: f.midY)
        let dy = CGFloat(rows) * SidebarView.rowPitch
        mouse(.leftMouseDown, start, in: window)
        let steps = 10
        for k in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(k)) {
                self.mouse(.leftMouseDragged, NSPoint(x: start.x, y: start.y - dy * CGFloat(k) / CGFloat(steps)), in: self.window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(steps) + 0.2) {
            if !self.pendingSnapshot.isEmpty { self.snapshot(self.window, name: self.pendingSnapshot); self.pendingSnapshot = "" }
            self.mouse(.leftMouseUp, NSPoint(x: start.x, y: start.y - dy), in: self.window)
            self.record("  dragged category \(name) by \(rows) rows")
            done(0.7)
        }
    }

    /// Right-clicks the header (on today's column or another day) and performs a menu item.
    private func headerMenu(onToday: Bool, path: [String]) {
        guard let chart else { check(false, "headerMenu: no chart"); return }
        let m = chart.model
        let dayIndex = onToday ? m.today - m.window.start : (m.today - m.window.start == 0 ? 1 : 0)
        let x = (CGFloat(dayIndex) + 0.5) * chart.dayWidth - chart.scrollOffset.x
        let p = chart.header.convert(NSPoint(x: x, y: 12), to: nil)
        guard let e = NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let menu = chart.header.menu(for: e) else { check(false, "headerMenu: no menu"); return }
        let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
        record("  header menu (\(onToday ? "on today's column" : "another day")): \(titles.joined(separator: " | "))")
        var current: NSMenu? = menu
        for (n, title) in path.enumerated() {
            guard let mm = current, let idx = mm.items.firstIndex(where: { $0.title == title }) else {
                check(false, "header menu item \(path.joined(separator: " › ")) not found"); return
            }
            if n == path.count - 1 { mm.performActionForItem(at: idx); record("  chose \(path.joined(separator: " › "))") }
            else { current = mm.items[idx].submenu }
        }
    }

    /// The Today tint appears in the date rows of the header, never in the month or week bars.
    private func expectHeaderTint() {
        guard let chart, let rep = render(window) else { check(false, "expectHeaderTint"); return }
        let m = chart.model
        guard m.window.contains(m.today) else { check(false, "today not in view"); return }
        let x = (CGFloat(m.today - m.window.start) + 0.5) * chart.dayWidth - chart.scrollOffset.x
        let xOther = x + chart.dayWidth * (m.today < m.window.end ? 1 : -1)
        func at(_ px: CGFloat, _ py: CGFloat) -> RGB? { rendered(rep, atWindow: chart.header.convert(NSPoint(x: px, y: py), to: nil)) }
        let monthBar = at(x, 3), weekBar = at(x, GanttChartView.monthRowHeight + 2)
        let dateRows = at(x + chart.dayWidth / 2 - 3, GanttChartView.dayRowsTop + 2)
        let monthOther = at(xOther, 3), dateOther = at(xOther + chart.dayWidth / 2 - 3, GanttChartView.dayRowsTop + 2)
        check(same(monthBar, monthOther) && same(weekBar, monthOther) && tintMatches(dateRows, background: dateOther),
              "Today tint: month bar \(monthBar?.hex ?? "?") and week bar \(weekBar?.hex ?? "?") untinted (like \(monthOther?.hex ?? "?")); date rows tinted \(dateRows?.hex ?? "?") next to \(dateOther?.hex ?? "?")")
    }

    /// The Today tint shifts the background by the same amount in the rendered window as the
    /// chosen tint does on paper. (Comparing the shift, not absolute values, because the window
    /// capture's color management lifts dark colors.)
    private func tintMatches(_ tinted: RGB?, background: RGB?) -> Bool {
        guard let t = tinted, let b = background else { return false }
        let dark = window.effectiveAppearance.isDark
        let fill = TodayStyle.expectedFill(dark: dark)
        let canvas = RGB(hex: dark ? "#1E1E20" : "#FFFFFF")!
        let want = (fill.r - canvas.r, fill.g - canvas.g, fill.b - canvas.b)
        let got = (t.r - b.r, t.g - b.g, t.b - b.b)
        return abs(got.0 - want.0) < 0.06 && abs(got.1 - want.1) < 0.06 && abs(got.2 - want.2) < 0.06
    }

    /// Sends a sideways scroll (like a trackpad swipe) to the timeline.
    private func scrollTime(points: Double) {
        guard let chart, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                          wheel1: 0, wheel2: Int32(-points), wheel3: 0),
              let e = NSEvent(cgEvent: cg) else { check(false, "scrollTime: could not make a scroll event"); return }
        let before = store.window
        let x0 = chart.scrollOffset.x
        // Deliver in slices, like a real swipe.
        let slices = 8
        for _ in 0..<slices {
            if let cg2 = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0,
                                 wheel2: Int32(-points / Double(slices)), wheel3: 0), let e2 = NSEvent(cgEvent: cg2) {
                chart.header.scrollWheel(with: e2)
            }
        }
        _ = e
        record("  scrolled sideways \(Int(points)) pt: range \(before.start)…\(before.end) → \(store.window.start)…\(store.window.end), offset \(Int(x0)) → \(Int(chart.scrollOffset.x))")
    }

    private func performMenu(_ path: [String]) {
        var menu = NSApp.mainMenu
        for (n, title) in path.enumerated() {
            guard let m = menu, let index = m.items.firstIndex(where: { $0.title == title }) else {
                check(false, "menu item \(path.joined(separator: " › ")) not found"); return
            }
            if n == path.count - 1 {
                m.performActionForItem(at: index)
                record("  chose \(path.joined(separator: " › "))")
            } else {
                menu = m.items[index].submenu
            }
        }
    }
}
