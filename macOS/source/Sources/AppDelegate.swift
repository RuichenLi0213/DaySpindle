import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private(set) var window: NSWindow!
    private(set) var workspaces: Workspaces!
    /// The selected workspace (nil when none is open).
    var store: Store! { workspaces?.active }
    private var settingsWindow: NSWindow?
    private var verifier: VerifyRunner?
    private var appearanceObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    /// "light" or "dark": which icon the Dock currently shows.
    private(set) var dockIconVariant = ""

    func applicationWillFinishLaunching(_ notification: Notification) {
        // System (follow macOS), Light or Dark, from the user's setting.
        AppearanceSettings.shared.apply()
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspaces = Workspaces()
        createWindow()
        // Light or dark Dock icon to match the app's current appearance.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateDockIcon() } }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TimeZoneSettings.shared.systemChanged() }
        })
        NSApp.activate()
        appLog.notice("DaySpindle launched from \(Bundle.main.bundlePath, privacy: .public), workspace \(self.workspaces.activePath ?? "none", privacy: .public)")

        if let script = UserDefaults.standard.string(forKey: "DaySpindleVerifyScript") {
            verifier = VerifyRunner(scriptPath: script, app: self)
            verifier?.start()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // A workspace folder may have been moved, or changed by another computer (through iCloud Drive, say).
        workspaces?.checkFolders()
        workspaces?.active?.reloadIfChangedOnDisk()
    }

    func updateDockIcon() {
        let dark = NSApp.effectiveAppearance.isDark
        let variant = dark ? "dark" : "light"
        guard variant != dockIconVariant else { return }
        let name = dark ? "AppIcon-Dark" : "AppIcon"
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
            dockIconVariant = variant
        }
    }

    private func createWindow() {
        let hosting = NSHostingView(rootView: RootView(workspaces: workspaces))
        hosting.sizingOptions = [.minSize]

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "DaySpindle"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
        // No window toolbar: the workspace tabs are the top row of the window, under a plain
        // transparent title bar (a toolbar's glass would cover them), with the traffic lights beside them.
        w.backgroundColor = Theme.NS.canvas
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.contentMinSize = NSSize(width: 960, height: 560)
        w.center()
        w.setFrameAutosaveName("DaySpindleMainWindow")
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    // MARK: Undo

    /// The text field being edited in the front window, if any: Undo then undoes typing.
    private var editingText: NSTextView? {
        (NSApp.keyWindow?.firstResponder as? NSTextView).flatMap { $0.isEditable ? $0 : nil }
    }

    /// Edit › Undo: the last change in the selected workspace (each workspace has its own
    /// history), or typing while a text field is being edited.
    @objc func undoChange(_ sender: Any?) {
        if let tv = editingText { tv.undoManager?.undo(); return }
        store?.undo.undo()
    }

    @objc func redoChange(_ sender: Any?) {
        if let tv = editingText { tv.undoManager?.redo(); return }
        store?.undo.redo()
    }

    func performUndo() { undoChange(nil) }
    func performRedo() { redoChange(nil) }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "DaySpindle Settings"
            w.isReleasedWhenClosed = false
            w.backgroundColor = Theme.NS.canvas
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !window.isVisible || window.isMiniaturized { showWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        workspaces?.persistAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DaySpindle", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DaySpindle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DaySpindle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, "DaySpindle"))

        let file = NSMenu(title: "File")
        file.addItem(item("New Task", #selector(newTask(_:)), "n"))
        file.addItem(item("New Subtask", #selector(newSubtask(_:)), "n", [.command, .option]))
        file.addItem(item("New Milestone", #selector(newMilestone(_:)), "m", [.command, .shift]))
        file.addItem(item("New Group", #selector(newGroup(_:)), "g", [.command, .shift]))
        file.addItem(item("New Category…", #selector(newCategory(_:)), "n", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Show Details", #selector(editTask(_:)), "e"))
        file.addItem(item("Mark as Completed", #selector(toggleCompleted(_:)), "c", [.command, .shift]))
        file.addItem(item("Delete…", #selector(deleteTask(_:))))
        file.addItem(.separator())
        file.addItem(item("Move Up", #selector(moveTaskUp(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.command, .option]))
        file.addItem(item("Move Down", #selector(moveTaskDown(_:)), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), [.command, .option]))
        file.addItem(.separator())
        file.addItem(item("New Workspace…", #selector(newWorkspace(_:)), "n", [.command, .control]))
        file.addItem(item("Open Workspace…", #selector(openWorkspace(_:)), "o"))
        file.addItem(item("Import Tasks from DaySpindle 2.0…", #selector(importLegacy(_:))))
        file.addItem(item("Show Workspace in Finder", #selector(revealDataFile(_:))))
        file.addItem(item("Close Workspace Tab", #selector(closeWorkspace(_:)), "w", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(file, "File"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(undoChange(_:)), "z"))
        edit.addItem(item("Redo", #selector(redoChange(_:)), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, "Edit"))

        let view = NSMenu(title: "View")
        view.addItem(item("Show Details", #selector(toggleInspector(_:)), "i", [.command, .option]))
        view.addItem(.separator())
        view.addItem(item("All Items", #selector(showAllTasks(_:)), "1"))
        view.addItem(item("Clear Filters", #selector(clearFilters(_:)), "k"))
        view.addItem(.separator())
        view.addItem(item("Expand All Groups", #selector(expandAll(_:))))
        view.addItem(item("Collapse All Groups", #selector(collapseAll(_:))))
        view.addItem(.separator())
        view.addItem(item("Today", #selector(goToToday(_:)), "t"))
        let prev = item("Previous Period", #selector(previousPeriod(_:)), String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), [.command, .option])
        view.addItem(prev)
        let next = item("Next Period", #selector(nextPeriod(_:)), String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), [.command, .option])
        view.addItem(next)
        view.addItem(.separator())
        let weekMenu = NSMenu(title: "First Day of Week")
        for d in [0, 1, 6] {
            let i = item(DayFormat.weekdayLong[d], #selector(setFirstWeekday(_:)))
            i.tag = d
            weekMenu.addItem(i)
        }
        view.addItem(submenu(weekMenu, "First Day of Week"))
        view.addItem(item("Today Color…", #selector(chooseTodayColor(_:))))
        view.addItem(item("Time Zone…", #selector(showSettings(_:))))
        view.addItem(.separator())
        let appearance = NSMenu(title: "Appearance")
        for mode in AppearanceMode.allCases {
            let i = item(mode.title, #selector(setAppearance(_:)))
            i.representedObject = mode.rawValue
            appearance.addItem(i)
        }
        view.addItem(submenu(appearance, "Appearance"))
        main.addItem(submenu(view, "View"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Show Next Workspace", #selector(nextWorkspace(_:)), "}", [.command]))
        windowMenu.addItem(item("Show Previous Workspace", #selector(previousWorkspace(_:)), "{", [.command]))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("DaySpindle", #selector(showMainWindow(_:)), "0"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenu(windowMenu, "Window"))
        NSApp.windowsMenu = windowMenu

        let help = NSMenu(title: "Help")
        help.addItem(item("Add Example Tasks", #selector(addExampleTasks(_:))))
        main.addItem(submenu(help, "Help"))
        NSApp.helpMenu = help

        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        i.target = self
        return i
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        i.submenu = menu
        return i
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newWorkspace(_:)), #selector(openWorkspace(_:)), #selector(showMainWindow(_:)),
             #selector(showSettings(_:)):
            return true
        case #selector(importLegacy(_:)):
            return Workspaces.legacyDataExists
        case #selector(setAppearance(_:)):
            menuItem.state = (menuItem.representedObject as? String) == AppearanceSettings.shared.mode.rawValue ? .on : .off
            return true
        case #selector(nextWorkspace(_:)), #selector(previousWorkspace(_:)):
            return (workspaces?.entries.count ?? 0) > 1
        case #selector(closeWorkspace(_:)), #selector(revealDataFile(_:)):
            return workspaces?.activeEntry != nil
        default:
            break
        }
        if menuItem.action == #selector(undoChange(_:)) || menuItem.action == #selector(redoChange(_:)) {
            let undo = menuItem.action == #selector(undoChange(_:))
            let um = editingText?.undoManager ?? store?.undo
            let can = (undo ? um?.canUndo : um?.canRedo) ?? false
            let name = (undo ? um?.undoActionName : um?.redoActionName) ?? ""
            menuItem.title = (undo ? "Undo" : "Redo") + (can && !name.isEmpty ? " \(name)" : "")
            return can && (store?.activeSheet == nil || editingText != nil)
        }
        guard let store else { return false }
        let noSheet = store.activeSheet == nil
        switch menuItem.action {
        case #selector(toggleInspector(_:)):
            menuItem.title = store.inspectorVisible ? "Hide Details" : "Show Details"
            return true
        case #selector(editTask(_:)), #selector(deleteTask(_:)):
            return noSheet && store.selectedTaskID != nil
        case #selector(toggleCompleted(_:)):
            let done = store.selectedTaskID.flatMap { store.task($0) }?.isCompleted ?? false
            let mark = store.selectedTaskID.map { store.isMark($0) } ?? false
            menuItem.title = done ? (mark ? "Mark as Not Completed" : "Return from Archive") : "Mark as Completed"
            return noSheet && store.selectedTaskID != nil
        case #selector(newSubtask(_:)):
            return noSheet && store.selectedTaskID.map { store.kind(of: $0) != .milestone } == true
        case #selector(clearFilters(_:)):
            return noSheet && store.filtersActive
        case #selector(expandAll(_:)):
            return !store.collapsedIDs.isEmpty
        case #selector(collapseAll(_:)):
            return store.tasks.contains { store.hasSubtasks($0.id) }
        case #selector(setFirstWeekday(_:)):
            menuItem.state = menuItem.tag == store.firstWeekday ? .on : .off
            return true
        case #selector(moveTaskUp(_:)):
            return noSheet && store.selectedTaskID.map { store.canMoveTask($0, by: -1) } == true
        case #selector(moveTaskDown(_:)):
            return noSheet && store.selectedTaskID.map { store.canMoveTask($0, by: 1) } == true
        default:
            return noSheet
        }
    }

    @objc func newTask(_ sender: Any?) { showWindow(); store?.newItem(.task) }
    @objc func newSubtask(_ sender: Any?) { if let id = store?.selectedTaskID { showWindow(); store.newItem(.task, parentID: id) } }
    /// A milestone of the selected task (or inside the selected group), otherwise on its own.
    @objc func newMilestone(_ sender: Any?) {
        guard let store else { return }
        showWindow()
        let parent = store.selectedTaskID.flatMap { store.kind(of: $0) == .milestone ? nil : $0 }
        store.newItem(.milestone, parentID: parent)
    }
    @objc func newGroup(_ sender: Any?) { showWindow(); store?.newItem(.group) }
    @objc func newCategory(_ sender: Any?) { showWindow(); store?.beginNewCategory() }
    @objc func editTask(_ sender: Any?) { if let id = store?.selectedTaskID { store.openInspector(id) } }
    @objc func deleteTask(_ sender: Any?) { if let id = store?.selectedTaskID { store.requestDelete(id) } }
    @objc func toggleInspector(_ sender: Any?) { store?.inspectorVisible.toggle() }
    @objc func showAllTasks(_ sender: Any?) { store?.clearFilters() }
    @objc func clearFilters(_ sender: Any?) { store?.clearFilters() }
    @objc func expandAll(_ sender: Any?) { store?.expandAll() }
    @objc func collapseAll(_ sender: Any?) { store?.collapseAll() }
    @objc func goToToday(_ sender: Any?) { store?.goToToday() }
    @objc func previousPeriod(_ sender: Any?) { store?.shiftWindow(by: -1) }
    @objc func nextPeriod(_ sender: Any?) { store?.shiftWindow(by: 1) }
    @objc func showMainWindow(_ sender: Any?) { showWindow() }

    @objc func newWorkspace(_ sender: Any?) { showWindow(); workspaces.newWorkspace() }
    @objc func openWorkspace(_ sender: Any?) { showWindow(); workspaces.openWorkspace() }
    @objc func importLegacy(_ sender: Any?) { showWindow(); workspaces.importLegacy() }
    @objc func closeWorkspace(_ sender: Any?) { if let p = workspaces.activePath { workspaces.close(p) } }
    @objc func nextWorkspace(_ sender: Any?) { workspaces.selectNeighbor(1) }
    @objc func previousWorkspace(_ sender: Any?) { workspaces.selectNeighbor(-1) }

    @objc func setFirstWeekday(_ sender: NSMenuItem) { store?.setFirstWeekday(sender.tag) }
    @objc func addExampleTasks(_ sender: Any?) { showWindow(); store?.addExampleTasks() }
    @objc func chooseTodayColor(_ sender: Any?) { showWindow(); store?.beginTodayColor() }
    @objc func toggleCompleted(_ sender: Any?) { if let id = store?.selectedTaskID { store.toggleCompleted(id) } }
    @objc func moveTaskUp(_ sender: Any?) { if let id = store?.selectedTaskID { store.moveTask(id, by: -1) } }
    @objc func moveTaskDown(_ sender: Any?) { if let id = store?.selectedTaskID { store.moveTask(id, by: 1) } }

    @objc func setAppearance(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) {
            AppearanceSettings.shared.mode = mode
        }
    }

    @objc func revealDataFile(_ sender: Any?) {
        if let p = workspaces.activePath { workspaces.reveal(p) }
    }
}

/// DaySpindle › Settings… : the appearance and the time zone.
struct SettingsView: View {
    @ObservedObject var settings = AppearanceSettings.shared
    @ObservedObject var zones = TimeZoneSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(Theme.font(13)).foregroundStyle(Theme.text)
            HStack(spacing: 0) {
                ForEach(AppearanceMode.allCases) { mode in
                    SegmentButton(title: mode.title, accessibility: mode.title, help: help(mode),
                                  selected: settings.mode == mode) { settings.mode = mode }
                        .frame(minWidth: 110)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 0.5))
            Text(caption)
                .font(Theme.font(11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 6)

            Text("Time Zone").font(Theme.font(13)).foregroundStyle(Theme.text)
            TimeZoneButton()
                .frame(width: 260)
            Text("Times are shown in this time zone, as in Apple Calendar: a task at 10:00 in Tokyo shows at 02:00 in Berlin. Items without a time keep their dates everywhere. Unless you choose one, it's your Mac's time zone and follows you when you travel.")
                .font(Theme.font(11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .background(Theme.canvas)
    }

    private func help(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "Follow the macOS appearance"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }

    private var caption: String {
        switch settings.mode {
        case .system: return "DaySpindle follows macOS (System Settings › Appearance) and switches when it does."
        case .light: return "DaySpindle always uses its light look."
        case .dark: return "DaySpindle always uses its dark look."
        }
    }
}
