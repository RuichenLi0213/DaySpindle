import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: Store

    /// ⌘ held during the click being handled.
    private var additive: Bool { (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.command) }

    // Dragging a category to a new place.
    @ViewState private var draggingCategory: UUID?
    @ViewState private var dragOffset: CGFloat = 0
    @ViewState private var lastDragEnd = Date.distantPast
    /// Height of a category row plus the spacing between rows.
    static let rowPitch: CGFloat = 31

    private func dragTarget(from: Int) -> Int {
        let n = store.categories.count
        return min(max(from + Int((dragOffset / Self.rowPitch).rounded()), 0), max(n - 1, 0))
    }

    /// How far a row shifts while another category is dragged past it.
    private func shift(for index: Int, id: UUID) -> CGFloat {
        guard let d = draggingCategory, let from = store.categories.firstIndex(where: { $0.id == d }) else { return 0 }
        if id == d { return dragOffset }
        let to = dragTarget(from: from)
        if from < to, index > from, index <= to { return -Self.rowPitch }
        if to < from, index >= to, index < from { return Self.rowPitch }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Band behind the window's traffic-light buttons.
            Color.clear.frame(height: 52).background(WindowDragArea())

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarRow(selected: !store.filtersActive && !store.showingArchive, action: { store.clearFilters() }) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 18)
                    } title: {
                        Text("All Items").controlMarker("All Tasks")
                    } trailing: {
                        count(store.mainCount)
                    }
                    // Completed items, out of the main list. Unmark one to return it to its place.
                    SidebarRow(selected: store.showingArchive, action: { store.showArchive(true) }) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 18)
                    } title: {
                        Text("Archive").controlMarker("Archive")
                    } trailing: {
                        count(store.archiveCount)
                    }
                    .help("Completed items. Select one and unmark it to return it to its place.")

                    sectionHeader("Categories") {
                        Button { store.beginNewCategory() } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .regular))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                        .help("New Category")
                    }

                    // Like calendars in Calendar: each category has a checkbox in its color.
                    // Click turns it on or off (any combination); ⌘-click shows only that one.
                    // Drag a category up or down to reorder.
                    ForEach(Array(store.categories.enumerated()), id: \.element.id) { index, c in
                        let shown = store.isCategoryShown(c.id)
                        let dragging = draggingCategory == c.id
                        SidebarRow(selected: false, action: {
                            // A drag that ends over the row isn't a click.
                            guard draggingCategory == nil, Date().timeIntervalSince(lastDragEnd) > 0.3 else { return }
                            if additive { store.showOnlyCategory(c.id) } else { store.toggleCategory(c.id) }
                        }, onEdit: { store.beginEditCategory(c.id) }) {
                            CategoryCheckbox(colorHex: c.colorHex, checked: shown).frame(width: 18)
                        } title: {
                            HStack(spacing: 5) {
                                Text(c.name).lineLimit(1)
                                    .foregroundStyle(shown ? Theme.text : Theme.secondaryText)
                                if c.notes != nil {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(Theme.tertiaryText)
                                        .controlMarker("Note icon \(c.name)")
                                }
                            }
                        } trailing: {
                            count(store.taskCount(category: c.id))
                        }
                        .controlMarker("Category \(c.name)")
                        .help(c.notes ?? "")
                        .accessibilityLabel("\(c.name), \(shown ? "shown" : "hidden")")
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(dragging ? Theme.sidebarSelection : Color.clear))
                        .shadow(color: .black.opacity(dragging ? 0.18 : 0), radius: 4, y: 1)
                        .offset(y: shift(for: index, id: c.id))
                        .zIndex(dragging ? 1 : 0)
                        .animation(dragging ? nil : .easeOut(duration: 0.15), value: shift(for: index, id: c.id))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .onChanged { v in
                                    if draggingCategory == nil { draggingCategory = c.id }
                                    if draggingCategory == c.id { dragOffset = v.translation.height }
                                }
                                .onEnded { _ in
                                    if draggingCategory == c.id, let from = store.categories.firstIndex(where: { $0.id == c.id }) {
                                        store.moveCategory(c.id, to: dragTarget(from: from))
                                    }
                                    draggingCategory = nil
                                    dragOffset = 0
                                    lastDragEnd = Date()
                                })
                        .contextMenu {
                            Button("Show Only “\(c.name)”") { store.showOnlyCategory(c.id) }
                            Button("Show All Categories") { store.showAllCategories() }
                                .disabled(store.hiddenCategoryIDs.isEmpty)
                            Divider()
                            Button(c.notes == nil ? "Add Note…" : "Edit Note…") { store.beginCategoryNote(c.id) }
                            Button("Edit Category…") { store.beginEditCategory(c.id) }
                            Button("Delete Category…") { store.requestDeleteCategory(c.id) }
                        }
                    }

                    sectionHeader("Tags") { EmptyView() }

                    if store.tags.isEmpty {
                        Text("Add #tags to a task and they’ll appear here.")
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }

                    ForEach(store.tags, id: \.self) { tag in
                        let selected = store.selectedTagKeys.contains(tag.lowercased())
                        SidebarRow(selected: selected, action: { store.selectTag(tag, additive: additive) },
                                   onEdit: { store.beginRenameTag(tag) }) {
                            Text("#").font(Theme.font(14)).foregroundStyle(Theme.secondaryText).frame(width: 18)
                        } title: {
                            Text(tag).lineLimit(1)
                        } trailing: {
                            count(store.taskCount(tag: tag))
                        }
                        .contextMenu {
                            Button("Rename Tag…") { store.beginRenameTag(tag) }
                            Button("Delete Tag…") { store.requestDeleteTag(tag) }
                        }
                    }

                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            if store.filtersActive {
                Rectangle().fill(Theme.divider).frame(height: 1)
                Button {
                    store.clearFilters()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 12, weight: .regular))
                        Text("Clear Filters")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .padding(10)
            }

            // The time zone, then all the how-to notes, at the bottom left.
            Rectangle().fill(Theme.divider).frame(height: 1)
            TimeZoneButton()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            Rectangle().fill(Theme.divider).frame(height: 1)
            InstructionsView(exampleWorkspace: store.workspaceName == InstructionsView.exampleName)
        }
        .background(Theme.sidebar)
    }

    private func count(_ n: Int) -> some View {
        Text("\(n)").font(Theme.font(12)).foregroundStyle(Theme.tertiaryText)
    }

    private func sectionHeader<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(11))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            accessory()
        }
        .frame(height: 22)
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

/// One selectable sidebar row. Shows an edit button on hover when `onEdit` is set.
struct SidebarRow<Icon: View, Title: View, Trailing: View>: View {
    let selected: Bool
    let action: () -> Void
    var onEdit: (() -> Void)?
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing
    @ViewState private var hovering = false

    init(selected: Bool, action: @escaping () -> Void, onEdit: (() -> Void)? = nil,
         @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder title: @escaping () -> Title,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.selected = selected
        self.action = action
        self.onEdit = onEdit
        self.icon = icon
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            // A real button, so the first click works even when the window isn't active.
            Button(action: action) {
                HStack(spacing: 8) {
                    icon()
                    title()
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 4)
                    if !(hovering && onEdit != nil) { trailing() }
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hovering, let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                .help("Edit")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Theme.sidebarSelection : (hovering ? Theme.sidebarHover : .clear)))
        .onHover { hovering = $0 }
    }
}

/// A rounded checkbox in a category's color, like the calendar checkboxes in Calendar.
struct CategoryCheckbox: View {
    let colorHex: String
    let checked: Bool

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(checked ? color : Color.clear)
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(color, lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(RGB(hex: colorHex)?.prefersLightText == false ? Color(nsColor: Theme.NS.barDarkText) : .white)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// The operating instructions, pinned to the bottom of the sidebar and folded under "Tips" (click
/// to unfold; the choice is remembered). In the Example Workspace, a note above them says how to
/// remove it.
struct InstructionsView: View {
    var exampleWorkspace = false
    @AppStorage("TipsExpanded") private var expanded = false

    static let exampleName = "Example Workspace"
    static let exampleNote = "Done with the examples? Close this tab (× on the tab), then delete the “Example Workspace” folder in Finder. File › New Workspace… starts your own."
    static let lines = [
        "Mark an item as completed (⇧⌘C or in its details) to move it to the Archive in the sidebar. Unmark it there to return it to its place.",
        "Check a category to show it; ⌘-click shows only it.",
        "Click a tag to filter; ⌘-click adds more tags.",
        "Drag categories or rows to reorder them. A subtask stays inside its group.",
        "Drag a bar to move it; drag its ends to change dates. Dragging a group moves everything in it.",
        "Point at a bar, then drag one of the round handles on its four sides onto another item to draw an arrow.",
        "Double-click an item or arrow to see and edit it on the right.",
        "Right-click the Today header for its color and the first day of the week.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if exampleWorkspace {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "info.circle").font(.system(size: 10, weight: .regular))
                    Text(Self.exampleNote).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 3)
                .controlMarker("Example workspace note")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Tips").font(Theme.font(11))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help(expanded ? "Fold the tips" : "Show tips on using DaySpindle")
            .controlMarker("Tips")
            if expanded {
                ForEach(Self.lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•")
                        Text(line).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(Theme.font(10.5))
        .foregroundStyle(Theme.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .controlMarker("Instructions")
    }
}
