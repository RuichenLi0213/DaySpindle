import AppKit
import SwiftUI

/// The workspaces open as tabs. A workspace is a folder you choose (on this Mac, in iCloud
/// Drive, on a USB stick…); everything in it is saved in that folder, in
/// `dayspindle-data.json`. Copy or move the folder to another computer and open it there.
@MainActor
final class Workspaces: ObservableObject {
    struct Entry: Codable, Equatable, Identifiable {
        var path: String
        /// Finds the folder again after it was moved or renamed on this Mac.
        var bookmark: Data?
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
        var name: String { url.lastPathComponent }
        var exists: Bool {
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
        }
    }

    static let tabsKey = "WorkspaceTabs"
    static let activeKey = "ActiveWorkspace"

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var activePath: String?
    private var stores: [String: Store] = [:]
    /// False for a self-check run, which must never change the saved tabs.
    private let remembersTabs: Bool

    var active: Store? { activePath.flatMap { stores[$0] } }
    var activeEntry: Entry? { entries.first { $0.path == activePath } }
    var allStores: [Store] { Array(stores.values) }

    init() {
        let d = UserDefaults.standard
        if let test = d.string(forKey: "DaySpindleTestWorkspace") {
            // Self-check: only these folders, nothing remembered.
            remembersTabs = false
            for path in test.split(separator: "|").map(String.init) {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                entries.append(Entry(path: url.standardizedFileURL.path, bookmark: try? url.bookmarkData()))
            }
            select(entries.first?.path)
            return
        }
        remembersTabs = true
        if let raw = d.data(forKey: Self.tabsKey), let saved = try? JSONDecoder().decode([Entry].self, from: raw) {
            entries = saved.map(Self.relocated).map { e in
                var e = e
                if e.bookmark == nil && e.exists { e.bookmark = try? e.url.bookmarkData() }
                return e
            }
        }
        // First start: a "Workspace" or "Example Workspace" folder next to DaySpindle.app (for example,
        // the one that comes with DaySpindle) opens by itself. Only once: a closed tab stays closed.
        if entries.isEmpty && !d.bool(forKey: Self.nearbyCheckedKey), let found = Self.nearbyWorkspace() {
            entries.append(Entry(path: found.path, bookmark: try? found.bookmarkData()))
        }
        d.set(true, forKey: Self.nearbyCheckedKey)
        if let open = d.string(forKey: "DaySpindleOpenWorkspace") {
            add(URL(fileURLWithPath: open, isDirectory: true), create: true)
        } else {
            let saved = d.string(forKey: Self.activeKey)
            select(entries.contains { $0.path == saved } ? saved : entries.first?.path)
        }
        save()
    }

    static let nearbyCheckedKey = "NearbyWorkspaceChecked"
    static let nearbyNames = ["Workspace", "Example Workspace"]

    /// A workspace folder named "Workspace" or "Example Workspace" next to DaySpindle.app, or next to
    /// one of the three folders above it. Not when macOS runs the app from a temporary copy (App
    /// Translocation, for apps just downloaded): then the folder can't be seen from there.
    private static func nearbyWorkspace() -> URL? {
        let app = Bundle.main.bundleURL.standardizedFileURL
        guard !app.path.contains("/AppTranslocation/") else { return nil }
        var dir = app.deletingLastPathComponent()
        for _ in 0..<4 {
            for name in nearbyNames {
                let candidate = dir.appendingPathComponent(name, isDirectory: true)
                if Persistence.hasData(in: candidate) { return candidate.standardizedFileURL }
            }
            let up = dir.deletingLastPathComponent()
            if up.path == dir.path { break }
            dir = up
        }
        return nil
    }

    /// Follows a folder that was moved or renamed (on this Mac) through its bookmark.
    private static func relocated(_ e: Entry) -> Entry {
        guard !e.exists, let data = e.bookmark else { return e }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return e }
        var moved = Entry(path: url.standardizedFileURL.path, bookmark: e.bookmark)
        if stale { moved.bookmark = try? url.bookmarkData() }
        appLog.notice("Workspace moved: \(e.path, privacy: .public) → \(moved.path, privacy: .public)")
        return moved
    }

    private func save() {
        guard remembersTabs else { return }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.tabsKey) }
        UserDefaults.standard.set(activePath, forKey: Self.activeKey)
    }

    /// The workspace with this name, when two open folders have the same name: "Work — Projects".
    func title(for e: Entry) -> String {
        let same = entries.filter { $0.name == e.name }
        guard same.count > 1 else { return e.name }
        return "\(e.name) — \(e.url.deletingLastPathComponent().lastPathComponent)"
    }

    func select(_ path: String?) {
        guard let path, let e = entries.first(where: { $0.path == path }) else {
            activePath = nil
            save()
            return
        }
        if stores[path] == nil && e.exists {
            stores[path] = Store(directory: e.url)
        }
        activePath = path
        active?.refreshToday()
        active?.reloadIfChangedOnDisk()
        save()
    }

    /// Follows workspace folders that were moved or renamed while the app was open, and shows a
    /// missing folder as missing (instead of saving into nowhere). Called when the app becomes active.
    func checkFolders() {
        var changed = false
        for i in entries.indices where !entries[i].exists {
            let old = entries[i].path
            let moved = Self.relocated(entries[i])
            stores[old]?.stop()
            stores[old] = nil
            if moved.path != old && !entries.contains(where: { $0.path == moved.path }) {
                entries[i] = moved
                if activePath == old { activePath = nil; select(moved.path) }
            } else if activePath == old {
                objectWillChange.send()
            }
            changed = true
        }
        if changed { save() }
    }

    func selectNeighbor(_ offset: Int) {
        guard let i = entries.firstIndex(where: { $0.path == activePath }), !entries.isEmpty else { return }
        select(entries[(i + offset + entries.count) % entries.count].path)
    }

    /// Opens a folder as a tab (or switches to it when it's open already).
    @discardableResult
    func add(_ url: URL, create: Bool = false) -> Bool {
        let folder = url.standardizedFileURL
        if create { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &dir), dir.boolValue else { return false }
        if entries.contains(where: { $0.path == folder.path }) {
            select(folder.path)
            return true
        }
        entries.append(Entry(path: folder.path, bookmark: try? folder.bookmarkData()))
        select(folder.path)
        return true
    }

    /// Closes a tab. The folder and everything in it stay where they are.
    func close(_ path: String) {
        guard let i = entries.firstIndex(where: { $0.path == path }) else { return }
        if let store = stores[path] {
            store.persist()
            store.stop()
        }
        stores[path] = nil
        entries.remove(at: i)
        if activePath == path {
            select(entries.isEmpty ? nil : entries[min(i, entries.count - 1)].path)
        }
        save()
    }

    func move(_ path: String, by offset: Int) {
        guard let i = entries.firstIndex(where: { $0.path == path }) else { return }
        let j = i + offset
        guard entries.indices.contains(j) else { return }
        entries.swapAt(i, j)
        save()
    }

    func persistAll() { for s in stores.values { s.persist() } }

    // MARK: Panels

    /// A panel for choosing the folder itself to use as a workspace (no folder is made inside it).
    private func folderPanel(title: String, message: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// File › New Workspace…: the chosen folder itself becomes the workspace, and its tab is named after it.
    func newWorkspace() {
        guard let url = folderPanel(title: "New Workspace",
                                    message: "Choose the folder to use as the workspace, on this Mac or in iCloud Drive (New Folder makes one). Everything in the workspace is saved in this folder, and its tab takes the folder's name.",
                                    prompt: "Use as Workspace") else { return }
        if let problem = useAsWorkspace(url) { alert("Couldn't use the folder", problem) }
    }

    /// Opens this folder itself as a workspace (starting an empty one when it has no DaySpindle data
    /// yet), in a tab named after it. Returns what went wrong, if anything.
    @discardableResult
    func useAsWorkspace(_ url: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return error.localizedDescription
        }
        return add(url) ? nil : "“\(url.lastPathComponent)” isn't a folder."
    }

    /// File › Open Workspace…: opens a workspace folder, for example one copied from another computer.
    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Open Workspace"
        panel.message = "Choose a workspace folder (it holds dayspindle-data.json)."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !Persistence.hasData(in: url) {
            let a = NSAlert()
            a.messageText = "“\(url.lastPathComponent)” isn't a DaySpindle workspace yet"
            a.informativeText = "Start a new, empty workspace in this folder?"
            a.addButton(withTitle: "Start Workspace")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        add(url)
    }

    static var legacyDataExists: Bool { FileManager.default.fileExists(atPath: Persistence.legacyFileURL.path) }

    /// File › Import Tasks from DaySpindle 2.0…: copies the old app's data into the chosen folder,
    /// which becomes the workspace. The old file stays where it was.
    func importLegacy() {
        guard Self.legacyDataExists else {
            alert("Nothing to import", "There are no tasks from DaySpindle 2.0 on this Mac.")
            return
        }
        guard let url = folderPanel(title: "Import Tasks from DaySpindle 2.0",
                                    message: "Choose the folder to use as the workspace for your tasks (New Folder makes one). Its tab takes the folder's name.",
                                    prompt: "Import Here") else { return }
        if Persistence.hasData(in: url) {
            alert("That folder is already a workspace", "Choose another folder for the imported tasks.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Persistence.legacyFileURL, to: url.appendingPathComponent(Persistence.fileName))
            add(url)
        } catch {
            alert("Couldn't import", error.localizedDescription)
        }
    }

    /// Finds a workspace folder that was moved elsewhere.
    func locate(_ path: String) {
        let panel = NSOpenPanel()
        panel.title = "Locate Workspace"
        panel.message = "Where is the folder “\(URL(fileURLWithPath: path).lastPathComponent)” now?"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url,
              let i = entries.firstIndex(where: { $0.path == path }) else { return }
        let folder = url.standardizedFileURL
        if entries.contains(where: { $0.path == folder.path }) {
            close(path)
            select(folder.path)
            return
        }
        entries[i] = Entry(path: folder.path, bookmark: try? folder.bookmarkData())
        stores[path] = nil
        select(folder.path)
    }

    func reveal(_ path: String) {
        let e = Entry(path: path, bookmark: nil)
        let file = e.url.appendingPathComponent(Persistence.fileName)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(e.url)
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: - Tab bar

/// The workspace tabs, under the toolbar. Click a tab to switch; × closes it (the folder is kept).
struct WorkspaceTabBar: View {
    /// The row's height. The details pane's header has the same height, so the lines under both meet.
    static let height: CGFloat = 34

    @ObservedObject var workspaces: Workspaces
    @ViewState private var showingAdd = false

    var body: some View {
        HStack(spacing: 6) {
            // A plain row, not a scroll view: under the window's title bar a scroll view would push its
            // content down out of sight. With many tabs, their names shorten.
            HStack(spacing: 4) {
                ForEach(workspaces.entries) { e in
                    WorkspaceTab(workspaces: workspaces, entry: e, selected: e.path == workspaces.activePath)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            Button {
                showingAdd.toggle()
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .regular)).frame(width: 18, height: 18)
            }
            .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
            .help("New or open a workspace")
            .accessibilityLabel("Add Workspace")
            .controlMarker("Add Workspace")
            .popover(isPresented: $showingAdd, arrowEdge: .bottom) {
                WorkspaceAddMenu(workspaces: workspaces) { showingAdd = false }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        // The tabs are the top of the window: their empty space moves the window.
        .background(WindowDragArea())
        .background(Theme.filterBar)
    }
}

struct WorkspaceAddMenu: View {
    @ObservedObject var workspaces: Workspaces
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            item("New Workspace…", "folder.badge.plus", "Use a folder for a new set of tasks") { workspaces.newWorkspace() }
            item("Open Workspace…", "folder", "Open a workspace folder, e.g. one copied from another computer") { workspaces.openWorkspace() }
            if Workspaces.legacyDataExists {
                item("Import Tasks from DaySpindle 2.0…", "square.and.arrow.down", "Copy the tasks of the previous version into a folder you choose") {
                    workspaces.importLegacy()
                }
            }
        }
        .padding(8)
        .frame(width: 270)
        .background(Theme.canvas)
    }

    private func item(_ title: String, _ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button {
            done()
            DispatchQueue.main.async(execute: action)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 26))
        .help(help)
    }
}

struct WorkspaceTab: View {
    @ObservedObject var workspaces: Workspaces
    let entry: Workspaces.Entry
    let selected: Bool
    @ViewState private var hovering = false

    var body: some View {
        let missing = !entry.exists
        HStack(spacing: 6) {
            Image(systemName: missing ? "exclamationmark.triangle" : (selected ? "folder.fill" : "folder"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(missing ? Theme.destructive : (selected ? Theme.accent : Theme.secondaryText))
            Text(workspaces.title(for: entry))
                .font(Theme.font(12))
                .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
            Button {
                workspaces.close(entry.path)
            } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .regular)).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .opacity(hovering || selected ? 1 : 0)
            .help("Close this tab (the folder is kept)")
            .accessibilityLabel("Close \(entry.name)")
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Theme.segmentSelected : (hovering ? Theme.controlHover : Color.clear))
            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1, y: 0.5))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(selected ? Theme.controlBorder : .clear, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { workspaces.select(entry.path) }
        .onHover { hovering = $0 }
        .help(entry.path)
        .controlMarker("Workspace tab \(entry.name)")
        .contextMenu {
            Button("Show in Finder") { workspaces.reveal(entry.path) }
            if missing { Button("Locate Folder…") { workspaces.locate(entry.path) } }
            Divider()
            Button("Move Tab Left") { workspaces.move(entry.path, by: -1) }
            Button("Move Tab Right") { workspaces.move(entry.path, by: 1) }
            Divider()
            Button("Close Tab") { workspaces.close(entry.path) }
        }
    }
}

// MARK: - No workspace

/// Shown when no workspace is open, or when the selected workspace's folder is missing.
struct NoWorkspaceView: View {
    @ObservedObject var workspaces: Workspaces

    var body: some View {
        VStack(spacing: 0) {
            if workspaces.entries.isEmpty {
                Color.clear.frame(height: 52).background(WindowDragArea())
            } else {
                WorkspaceTabBar(workspaces: workspaces)
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            Spacer()
            VStack(spacing: 14) {
                if let e = workspaces.activeEntry, !e.exists {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.secondaryText)
                    Text("Can't find the workspace folder").font(Theme.titleFont(17))
                    Text(e.path).font(Theme.font(12)).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                    Text("It may have been moved, renamed or deleted, or it's on a drive that isn't connected.")
                        .font(Theme.font(12)).foregroundStyle(Theme.tertiaryText)
                    HStack(spacing: 8) {
                        Button("Locate Folder…") { workspaces.locate(e.path) }.buttonStyle(PillButtonStyle(kind: .prominent))
                        Button("Close Tab") { workspaces.close(e.path) }.buttonStyle(PillButtonStyle())
                    }
                } else {
                    Image(systemName: "folder.badge.plus").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent)
                    Text("Welcome to DaySpindle 2.1").font(Theme.titleFont(19))
                    Text("Your groups, tasks and milestones live in a workspace: a folder you choose, on this Mac or in iCloud Drive. Move or copy the folder to another computer and open it there to carry on.")
                        .font(Theme.font(13)).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("New Workspace…") { workspaces.newWorkspace() }.buttonStyle(PillButtonStyle(kind: .prominent))
                        Button("Open Workspace…") { workspaces.openWorkspace() }.buttonStyle(PillButtonStyle())
                    }
                    if Workspaces.legacyDataExists {
                        Button("Import My Tasks from DaySpindle 2.0…") { workspaces.importLegacy() }
                            .buttonStyle(PillButtonStyle(kind: .plain))
                    }
                }
            }
            .padding(30)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .font(Theme.font(13))
        .foregroundStyle(Theme.text)
    }
}
