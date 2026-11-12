import AppKit
import SwiftUI

// MARK: - Small pieces

/// The marker for an item's kind, in its color: dot (task), diamond (milestone), square (group).
struct KindIcon: View {
    let kind: ItemKind
    let colorHex: String
    var size: CGFloat = 10

    var body: some View {
        let color = Color(hex: colorHex)
        Group {
            switch kind {
            case .task: Circle().fill(color).frame(width: size, height: size)
            case .milestone:
                Rectangle().fill(color).frame(width: size * 0.74, height: size * 0.74).rotationEffect(.degrees(45))
            case .group: RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: size, height: size)
            }
        }
        .frame(width: size + 2, height: size + 2)
    }
}

/// A text field that saves when you press Return or leave it (or when the details pane
/// switches to another item), so each edit is one Undo step.
struct CommitField: View {
    let placeholder: String
    let value: String
    var font: Font = Theme.font(13)
    var height: CGFloat = 28
    var alignment: TextAlignment = .leading
    var focusOnAppear = false
    var invalid = false
    let marker: String
    let commit: (String) -> Void
    @ViewState private var text: String
    @FocusState private var focused: Bool

    init(_ placeholder: String, value: String, font: Font = Theme.font(13), height: CGFloat = 28,
         alignment: TextAlignment = .leading, focusOnAppear: Bool = false, invalid: Bool = false,
         marker: String, commit: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.value = value
        self.font = font
        self.height = height
        self.alignment = alignment
        self.focusOnAppear = focusOnAppear
        self.invalid = invalid
        self.marker = marker
        self.commit = commit
        _text = ViewState(wrappedValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .padding(.horizontal, alignment == .center ? 4 : 9)
            .frame(height: height)
            .fieldBackground(focused: focused, invalid: invalid)
            .onSubmit(send)
            .onChange(of: focused) { old, new in if old && !new { send() } }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .onAppear {
                if focusOnAppear { DispatchQueue.main.async { focused = true } }
            }
            .onDisappear(perform: send)
            .controlMarker(marker)
    }

    private func send() {
        if text != value { commit(text) }
    }
}

/// Multi-line notes that save when you leave the field.
struct CommitTextEditor: View {
    let value: String
    let marker: String
    let commit: (String) -> Void
    @ViewState private var text: String
    @FocusState private var focused: Bool

    init(value: String, marker: String, commit: @escaping (String) -> Void) {
        self.value = value
        self.marker = marker
        self.commit = commit
        _text = ViewState(wrappedValue: value)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.font(13))
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(minHeight: 90)
            .fieldBackground(focused: focused)
            .onChange(of: focused) { old, new in if old && !new { send() } }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .onDisappear(perform: send)
            .controlMarker(marker)
    }

    private func send() {
        if text.trimmingCharacters(in: .whitespacesAndNewlines) != value.trimmingCharacters(in: .whitespacesAndNewlines) {
            commit(text)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(10.5))
            .tracking(0.6)
            .foregroundStyle(Theme.tertiaryText)
    }
}

// MARK: - The details pane

/// The details pane on the right: everything about the selected group, task, milestone or
/// arrow, editable in place.
struct InspectorView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Details").font(Theme.titleFont(13))
                Spacer()
                Button {
                    store.inspectorVisible = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .regular)).frame(width: 18, height: 18)
                }
                .buttonStyle(PillButtonStyle(kind: .plain, height: 22))
                .help("Hide the details (⌥⌘I)")
                .accessibilityLabel("Hide Details")
            }
            .padding(.horizontal, 14)
            .frame(height: WorkspaceTabBar.height) // its line meets the one under the workspace tabs
            .background(WindowDragArea())
            Rectangle().fill(Theme.divider).frame(height: 1)
            ScrollView(.vertical) {
                Group {
                    if let linkID = store.selectedLinkID, let link = store.dependency(linkID) {
                        LinkInspector(store: store, link: link).id(linkID)
                    } else if let id = store.selectedTaskID, store.task(id) != nil {
                        ItemInspector(store: store, id: id).id(id)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nothing selected").font(Theme.titleFont(13)).foregroundStyle(Theme.secondaryText)
                            Text("Double-click a group, task or milestone (or an arrow) to see and edit its details here.")
                                .font(Theme.font(12)).foregroundStyle(Theme.tertiaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.canvas)
        .controlMarker("Details pane")
    }
}

// MARK: Item

struct ItemInspector: View {
    @ObservedObject var store: Store
    let id: UUID
    @ViewState private var error: String?
    @ViewState private var hexInvalid = false
    @ViewState private var tagInput = ""

    var body: some View {
        if let t = store.shown(id) {
            content(t, kind: store.kind(of: id))
        }
    }

    @ViewBuilder
    private func content(_ t: TaskItem, kind: ItemKind) -> some View {
        let isMark = store.isMark(id)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                KindIcon(kind: kind, colorHex: store.colorHex(for: t), size: 11)
                SectionTitle(text: isMark ? "Milestone of a task" : kind.title)
                Spacer()
            }

            CommitField("Title", value: t.title, font: Theme.titleFont(15), height: 32,
                        focusOnAppear: store.titleFocusID == id, marker: "Title") { text in
                error = store.setTitle(id, text)
            }
            .onAppear { if store.titleFocusID == id { store.titleFocusID = nil } }

            CompletedButton(done: t.isCompleted, onBar: isMark) { store.setCompleted(id, !t.isCompleted) }

            LabeledField("Type") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        ForEach(ItemKind.allCases) { k in
                            SegmentButton(title: k.title, accessibility: "Type \(k.title)", help: typeHelp(k),
                                          selected: kind == k) { error = store.setKind(id, k) }
                                .frame(maxWidth: .infinity)
                                .disabled(store.hasSubtasks(id) && k != .group)
                        }
                    }
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 0.5))
                    if store.hasSubtasks(id) {
                        caption("It has subtasks, so it's a group. Its dates come from what's inside it.")
                    }
                }
            }

            dateSection(t, kind: kind)

            LabeledField(isMark ? "Task" : "Inside") {
                ParentPickerButton(store: store, taskID: id, parentID: Binding(
                    get: { store.task(id)?.parentID },
                    set: { error = store.setParent(id, $0) }))
            }

            LabeledField("Category") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(store.categories) { c in categoryChip(c, selected: t.categoryID == c.id) }
                }
            }

            colorSection(t)

            LabeledField("Location") {
                CommitField("Optional, e.g. Room 204", value: t.location ?? "", marker: "Location") { store.setLocation(id, $0) }
            }

            tagSection(t)

            if kind == .task { milestoneSection() }
            if kind == .group { contentsSection() }

            dependencySection()

            LabeledField("Notes") {
                CommitTextEditor(value: t.notes ?? "", marker: "Notes") { store.setNotes(id, $0) }
            }

            if let error {
                Text(error).font(Theme.font(12)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Delete \(kind.title)…") { store.requestDelete(id) }
                    .buttonStyle(PillButtonStyle(kind: .destructive))
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func typeHelp(_ k: ItemKind) -> String {
        switch k {
        case .task: return "A bar from its start to its end"
        case .milestone: return "A key moment on one day, such as a review or a deadline"
        case .group: return "Holds tasks and milestones; spans from the first to the last of them"
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.font(11)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Dates

    @ViewBuilder
    private func dateSection(_ t: TaskItem, kind: ItemKind) -> some View {
        let zone = store.viewTimeZone
        switch kind {
        case .group:
            LabeledField("Dates") {
                VStack(alignment: .leading, spacing: 4) {
                    if let d = store.displayDates(id) {
                        Text("\(DayFormat.range(d.start, d.end, referenceYear: store.today.year)) · \(DayFormat.dayCount(d.end - d.start + 1))")
                            .font(Theme.font(13))
                        caption("From the first to the last item inside it. Drag the group's bar to move everything in it.")
                    } else {
                        Text("Empty group").font(Theme.font(13)).foregroundStyle(Theme.secondaryText)
                        caption("Add subtasks or milestones; the group then spans them.")
                    }
                }
            }
        case .milestone:
            LabeledField("Date") {
                HStack(spacing: 6) {
                    DayPickerButton(day: t.start, today: store.today, firstWeekday: store.firstWeekday, compact: true,
                                    accessibilityName: "Milestone date") { d in error = store.setDates(id, start: d, end: d) }
                    timeField(t.startTime ?? "", placeholder: "Time", marker: "Milestone time") { text in
                        error = store.setTimes(id, start: text, end: "")
                    }
                }
            }
            timeZoneCaption(t, zone: zone)
        case .task:
            HStack(alignment: .top, spacing: 14) {
                LabeledField("Starts") {
                    HStack(spacing: 6) {
                        DayPickerButton(day: t.start, today: store.today, firstWeekday: store.firstWeekday, compact: true,
                                        accessibilityName: "Start date") { d in
                            let end = store.shown(id)?.end ?? d
                            error = store.setDates(id, start: d, end: max(end, d))
                        }
                        timeField(t.startTime ?? "", placeholder: TimeOfDay.defaultStart, marker: "Start time") { text in
                            error = store.setTimes(id, start: text, end: store.shown(id)?.endTime ?? "")
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                LabeledField("Ends") {
                    HStack(spacing: 6) {
                        DayPickerButton(day: t.end, minDay: t.start, today: store.today, firstWeekday: store.firstWeekday,
                                        compact: true, accessibilityName: "End date") { d in
                            error = store.setDates(id, start: store.shown(id)?.start ?? d, end: d)
                        }
                        timeField(t.endTime ?? "", placeholder: TimeOfDay.defaultEnd, marker: "End time") { text in
                            error = store.setTimes(id, start: store.shown(id)?.startTime ?? "", end: text)
                        }
                    }
                }
                LabeledField("Duration") {
                    Text(DayFormat.dayCount(t.dayCount)).font(Theme.font(13)).foregroundStyle(Theme.secondaryText).frame(height: 28)
                }
            }
            timeZoneCaption(t, zone: zone)
        }
    }

    private func timeField(_ value: String, placeholder: String, marker: String, commit: @escaping (String) -> Void) -> some View {
        CommitField(placeholder, value: value, alignment: .center, marker: marker, commit: commit)
            .frame(width: 62)
            .help("A time of day, e.g. 9:30, 14:00 or 5pm. Leave it empty for the whole day.")
    }

    /// Which time zone the times are in, and where they were entered when that's elsewhere.
    @ViewBuilder
    private func timeZoneCaption(_ t: TaskItem, zone: TimeZone) -> some View {
        if let stored = store.task(id), stored.isTimed {
            VStack(alignment: .leading, spacing: 2) {
                caption("Times in \(Zones.label(zone)).")
                if let entered = Zones.zone(stored.timeZone), entered.identifier != zone.identifier {
                    let when = stored.storedKind == .milestone
                        ? "\(DayFormat.medium(stored.start)) \(stored.startTime ?? "")"
                        : "\(DayFormat.short(stored.start)) \(stored.startTime ?? TimeOfDay.defaultStart) – \(DayFormat.short(stored.end)) \(stored.endTime ?? TimeOfDay.defaultEnd)"
                    caption("Entered in \(Zones.label(entered)): \(when).")
                }
            }
        } else {
            caption("No time set: the same dates in every time zone.")
        }
    }

    // MARK: Category, color, tags

    private func categoryChip(_ c: Category, selected: Bool) -> some View {
        Button {
            store.setCategory(id, c.id)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: c.colorHex)).frame(width: 9, height: 9)
                Text(c.name).font(Theme.font(13)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Color(hex: c.colorHex).opacity(0.13) : Theme.controlFill))
            .overlay(Capsule().strokeBorder(selected ? Color(hex: c.colorHex) : Theme.controlBorder, lineWidth: selected ? 1.5 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .controlMarker("Category chip \(c.name)")
    }

    private func colorSection(_ t: TaskItem) -> some View {
        let categoryHex = store.category(t.categoryID)?.colorHex ?? "#8B8D98"
        return LabeledField("Color") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        store.setColor(id, nil)
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: categoryHex)).frame(width: 9, height: 9)
                            Text("Category").font(Theme.font(13)).foregroundStyle(Theme.text)
                                .lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(t.colorHex == nil ? Color(hex: categoryHex).opacity(0.13) : Theme.controlFill))
                        .overlay(Capsule().strokeBorder(t.colorHex == nil ? Color(hex: categoryHex) : Theme.controlBorder,
                                                        lineWidth: t.colorHex == nil ? 1.5 : 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("or").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                    HexColorField(hex: Binding(get: { store.task(id)?.colorHex ?? "" },
                                               set: { store.setColor(id, $0.isEmpty ? nil : $0) }),
                                  invalid: $hexInvalid, placeholder: categoryHex, allowEmpty: true, marker: "Item hex")
                }
                if hexInvalid {
                    Text("Type a hex color such as #2F6FEB.").font(Theme.font(11)).foregroundStyle(Theme.destructive)
                }
            }
        }
    }

    private func tagSection(_ t: TaskItem) -> some View {
        LabeledField("Tags") {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(t.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)").font(Theme.font(12))
                            Button {
                                store.setTags(id, t.tags.filter { $0 != tag })
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .regular))
                                    .frame(width: 12, height: 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.leading, 8).padding(.trailing, 5)
                        .frame(height: 22)
                        .background(Capsule().fill(Theme.filterChip))
                    }
                    TextField(t.tags.isEmpty ? "Add tags" : "Add tag", text: $tagInput)
                        .textFieldStyle(.plain)
                        .font(Theme.font(13))
                        .frame(width: 120, height: 22)
                        .onSubmit { commitTags(t) }
                        .onChange(of: tagInput) { _, new in
                            if new.contains(where: { $0 == "," || $0 == " " || $0 == ";" }) { commitTags(t) }
                        }
                        .controlMarker("Tag input")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBackground()

                let suggestions = store.tags.filter { s in !t.tags.contains { $0.lowercased() == s.lowercased() } }
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(suggestions, id: \.self) { s in
                            Button("#\(s)") { store.setTags(id, t.tags + [s]) }
                                .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                                .font(Theme.font(12))
                        }
                    }
                }
            }
        }
    }

    private func commitTags(_ t: TaskItem) {
        let added = Tags.parse(tagInput)
        tagInput = ""
        guard !added.isEmpty else { return }
        store.setTags(id, (store.task(id)?.tags ?? t.tags) + added)
    }

    // MARK: Milestones and contents

    private func milestoneSection() -> some View {
        LabeledField("Milestones") {
            VStack(alignment: .leading, spacing: 3) {
                let marks = store.marks(of: id)
                if marks.isEmpty {
                    caption("Key moments of this task, such as a mid-term review or the deadline. They're drawn as diamonds on its bar.")
                }
                ForEach(marks) { m in
                    itemRow(m, kind: .milestone)
                }
                Button {
                    store.newItem(.milestone, parentID: id)
                } label: {
                    Label("Add Milestone", systemImage: "plus").font(Theme.font(12))
                }
                .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                .controlMarker("Add Milestone")
            }
        }
    }

    private func contentsSection() -> some View {
        LabeledField("Inside this group") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(store.children(of: id)) { c in
                    itemRow(c.displayed(in: store.viewTimeZone), kind: store.kind(of: c.id))
                }
                HStack(spacing: 4) {
                    Button {
                        store.newItem(.task, parentID: id)
                    } label: {
                        Label("Add Subtask", systemImage: "plus").font(Theme.font(12))
                    }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                    .controlMarker("Add Subtask")
                    Button {
                        store.newItem(.milestone, parentID: id)
                    } label: {
                        Label("Add Milestone", systemImage: "plus").font(Theme.font(12))
                    }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                }
            }
        }
    }

    /// A row that shows another item; click it to show that item here.
    private func itemRow(_ item: TaskItem, kind: ItemKind) -> some View {
        Button {
            store.openInspector(item.id)
        } label: {
            HStack(spacing: 7) {
                KindIcon(kind: kind, colorHex: store.colorHex(for: item), size: 9)
                Text(item.title).font(Theme.titleFont(12)).lineLimit(1)
                Spacer(minLength: 4)
                Text(dateText(item, kind: kind)).font(Theme.font(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 26))
        .help("Show “\(item.title)”")
    }

    private func dateText(_ item: TaskItem, kind: ItemKind) -> String {
        switch kind {
        case .milestone: return DayFormat.short(item.start) + (item.startTime.map { " \($0)" } ?? "")
        case .group:
            guard let d = store.displayDates(item.id) else { return "Empty" }
            return DayFormat.range(d.start, d.end, referenceYear: store.today.year)
        case .task: return DayFormat.range(item.start, item.end, referenceYear: store.today.year)
        }
    }

    // MARK: Dependencies

    private func dependencySection() -> some View {
        let before = store.predecessors(of: id), after = store.successors(of: id)
        return LabeledField("Arrows") {
            VStack(alignment: .leading, spacing: 6) {
                if before.isEmpty && after.isEmpty {
                    caption("None yet. On the timeline, point at this item, then drag one of the small round handles on its four sides onto another item.")
                }
                ForEach(before) { d in DependencyRow(store: store, link: d, otherID: d.from, incoming: true) }
                ForEach(after) { d in DependencyRow(store: store, link: d, otherID: d.to, incoming: false) }
                AddDependencyButton(store: store, itemID: id)
            }
        }
    }
}

/// "Mark as Completed" / "Completed" in the details pane.
struct CompletedButton: View {
    let done: Bool
    /// A milestone on a task's bar: it stays on the bar (with a check) instead of moving to the Archive.
    var onBar = false
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggle) {
                HStack(spacing: 7) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(done ? Color(hex: "#30A46C") : Theme.secondaryText)
                    Text(done ? (onBar ? "Completed" : "Completed · in the Archive") : "Mark as Completed").font(Theme.font(13))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PillButtonStyle(height: 28))
            .help(done ? (onBar ? "Click to mark it as not completed (⇧⌘C)" : "Click to return it from the Archive (⇧⌘C)")
                       : (onBar ? "Mark it as passed: its diamond gets a check (⇧⌘C)" : "Mark it as finished, whenever it was done: it moves to the Archive (⇧⌘C)"))
            .controlMarker(done ? "Completed" : "Mark as Completed")
            if done && !onBar {
                Text("Click it again to return it from the Archive to its place in the list.")
                    .font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One arrow to or from the item shown in the details pane, with its settings.
struct DependencyRow: View {
    @ObservedObject var store: Store
    let link: Dependency
    let otherID: UUID
    let incoming: Bool

    var body: some View {
        let other = store.task(otherID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: incoming ? "arrow.right.to.line" : "arrow.right.from.line")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
                    .help(incoming ? "Comes after this item" : "This item comes after it")
                Text(incoming ? "After" : "Before").font(Theme.font(11)).foregroundStyle(Theme.secondaryText)
                Button {
                    store.openInspector(otherID)
                } label: {
                    HStack(spacing: 5) {
                        if let other { KindIcon(kind: store.kind(of: otherID), colorHex: store.colorHex(for: other), size: 8) }
                        Text(other?.title ?? "?").font(Theme.titleFont(12)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Show this item")
                Spacer(minLength: 2)
                Button {
                    store.openLink(link.id)
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .regular)).frame(width: 16, height: 16)
                }
                .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                .help("Arrow settings")
                Button {
                    store.deleteDependency(link.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .regular)).frame(width: 16, height: 16)
                }
                .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                .help("Delete this arrow")
                .accessibilityLabel("Delete arrow")
            }
            HStack(spacing: 6) {
                LinkTypeMenu(store: store, link: link)
                LinkWidthMenu(store: store, link: link)
                LinkColorWell(store: store, link: link)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(store.selectedLinkID == link.id ? Theme.accent : Theme.controlBorder, lineWidth: 0.5))
    }
}

struct LinkTypeMenu: View {
    @ObservedObject var store: Store
    let link: Dependency
    var body: some View {
        Menu {
            ForEach(DependencyType.allCases) { t in
                Button { store.setDependencyType(link.id, t) } label: {
                    if t == link.type { Label(t.title, systemImage: "checkmark") } else { Text(t.title) }
                }
            }
        } label: {
            Text(link.type.title).font(Theme.font(12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Which ends the arrow joins")
        .controlMarker("Arrow type")
    }
}

/// Four buttons choosing the side of an item an arrow leaves from (exit) or arrives at.
struct LinkSidePicker: View {
    @ObservedObject var store: Store
    let link: Dependency
    let exit: Bool

    var body: some View {
        let current = exit ? link.exitSide : link.entrySide
        let name = store.task(exit ? link.from : link.to)?.title ?? "?"
        VStack(alignment: .leading, spacing: 4) {
            Text(exit ? "Leaves “\(name)” from its" : "Arrives at “\(name)” on its")
                .font(Theme.font(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            HStack(spacing: 4) {
                ForEach(LinkSide.allCases) { side in
                    Button {
                        store.setDependencySide(link.id, exit: exit, side)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: side.symbol).font(.system(size: 9, weight: .semibold))
                            Text(side.title).font(Theme.font(11)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(kind: side == current ? .prominent : .normal, height: 24))
                    .help(side.isVertical ? "The middle of its \(side.word) edge" : "Its \(side.word) (\(side.title.lowercased()) side)")
                    .controlMarker("\(exit ? "Exit" : "Entry") side \(side.rawValue)")
                }
            }
        }
    }
}

struct LinkWidthMenu: View {
    @ObservedObject var store: Store
    let link: Dependency
    var body: some View {
        Menu {
            ForEach(Dependency.widths, id: \.self) { w in
                Button { store.setDependencyWidth(link.id, w == Dependency.defaultWidth ? nil : w) } label: {
                    let title = Self.text(w) + (w == Dependency.defaultWidth ? " (default)" : "")
                    if w == link.lineWidth { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Text(Self.text(link.lineWidth)).font(Theme.font(12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Line thickness")
        .controlMarker("Arrow thickness")
    }

    /// 1.25 → "1.25 pt", 2.0 → "2 pt".
    static func text(_ w: Double) -> String {
        var s = String(format: "%.2f", w)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + " pt"
    }
}

struct LinkColorWell: View {
    @ObservedObject var store: Store
    let link: Dependency
    static let defaultHex = "#6E6E78"
    var body: some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: Binding(get: { Color(hex: link.colorHex ?? Self.defaultHex) },
                                               set: { store.setDependencyColor(link.id, NSColor($0).rgb?.hex) }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Line color")
            if link.colorHex != nil {
                Button("Default") { store.setDependencyColor(link.id, nil) }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 20))
                    .font(Theme.font(11))
            }
        }
    }
}

/// Adds an arrow from or to the item shown, chosen from a list.
struct AddDependencyButton: View {
    @ObservedObject var store: Store
    let itemID: UUID
    @ViewState private var showing = false
    @ViewState private var outgoing = true
    @ViewState private var type: DependencyType = .finishToStart

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("Add Arrow", systemImage: "plus").font(Theme.font(12))
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
        .controlMarker("Add Arrow")
        .popover(isPresented: $showing, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    SegmentButton(title: "This → other", accessibility: "From this item", help: "The other item comes after this one",
                                  selected: outgoing) { outgoing = true }
                    SegmentButton(title: "Other → this", accessibility: "To this item", help: "This item comes after the other one",
                                  selected: !outgoing) { outgoing = false }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.controlFill))
                Menu {
                    ForEach(DependencyType.allCases) { t in Button(t.title) { type = t } }
                } label: {
                    Text(type.title).font(Theme.font(12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Rectangle().fill(Theme.divider).frame(height: 1)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        let candidates = store.content.outline().filter { c in
                            outgoing ? store.linkProblem(from: itemID, to: c.task.id) == nil
                                     : store.linkProblem(from: c.task.id, to: itemID) == nil
                        }
                        if candidates.isEmpty {
                            Text("No other items can be joined to this one.").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(candidates.indices, id: \.self) { i in
                            let c = candidates[i]
                            Button {
                                if outgoing { store.addDependency(from: itemID, to: c.task.id, type: type, select: false) }
                                else { store.addDependency(from: c.task.id, to: itemID, type: type, select: false) }
                                showing = false
                            } label: {
                                HStack(spacing: 6) {
                                    KindIcon(kind: store.kind(of: c.task.id), colorHex: store.colorHex(for: c.task), size: 8)
                                    Text(c.task.title).font(Theme.titleFont(12)).lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .padding(.leading, CGFloat(min(c.depth, 8)) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                            .controlMarker("Link target \(c.task.title)")
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            .padding(10)
            .frame(width: 300)
            .background(Theme.canvas)
        }
    }
}

// MARK: Arrow

/// The settings of one dependency arrow.
struct LinkInspector: View {
    @ObservedObject var store: Store
    let link: Dependency
    @ViewState private var hexInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .regular)).foregroundStyle(Theme.secondaryText)
                SectionTitle(text: "Arrow")
                Spacer()
            }
            LabeledField("From") { endpoint(link.from) }
            LabeledField("To") { endpoint(link.to) }

            LabeledField("Connects") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(DependencyType.allCases) { t in
                        Button {
                            store.setDependencyType(link.id, t)
                        } label: {
                            HStack {
                                Text(t.title)
                                Spacer()
                                if t == link.type {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .regular)).foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PillButtonStyle(kind: .plain, height: 24))
                        .controlMarker("Connect \(t.rawValue)")
                    }
                    Text(typeExplanation).font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LabeledField("Sides") {
                VStack(alignment: .leading, spacing: 8) {
                    LinkSidePicker(store: store, link: link, exit: true)
                    LinkSidePicker(store: store, link: link, exit: false)
                    Text("Left is an item’s start and right its end. Top and bottom join the middle of its upper or lower edge.")
                        .font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LabeledField("Thickness") {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { link.lineWidth },
                                          set: { store.setDependencyWidth(link.id, ($0 * 4).rounded() / 4) }),
                           in: 0.25...6)
                    Text(LinkWidthMenu.text(link.lineWidth)).font(Theme.font(12)).frame(width: 48, alignment: .trailing)
                }
                .controlMarker("Thickness slider")
            }

            LabeledField("Color") {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 5), count: 8), alignment: .leading, spacing: 5) {
                        ForEach([LinkColorWell.defaultHex] + Palette.colors.map(\.hex), id: \.self) { hex in
                            let selected = (link.colorHex ?? LinkColorWell.defaultHex).uppercased() == hex.uppercased()
                            Button {
                                store.setDependencyColor(link.id, hex == LinkColorWell.defaultHex ? nil : hex)
                            } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(selected ? Color(hex: hex) : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(hex == LinkColorWell.defaultHex ? "Default gray" : hex)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Hex").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                        HexColorField(hex: Binding(get: { store.dependency(link.id)?.colorHex ?? "" },
                                                   set: { store.setDependencyColor(link.id, $0.isEmpty ? nil : $0) }),
                                      invalid: $hexInvalid, placeholder: LinkColorWell.defaultHex, allowEmpty: true, marker: "Arrow hex")
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Reverse") { store.reverseDependency(link.id) }
                    .buttonStyle(PillButtonStyle())
                    .help("Swap which item comes first")
                Spacer()
                Button("Delete Arrow") { store.deleteDependency(link.id) }
                    .buttonStyle(PillButtonStyle(kind: .destructive))
            }
            .padding(.top, 4)
        }
    }

    private var typeExplanation: String {
        let a = store.task(link.from)?.title ?? "the first item", b = store.task(link.to)?.title ?? "the second item"
        switch link.type {
        case .finishToStart: return "“\(b)” starts after “\(a)” finishes."
        case .startToStart: return "“\(b)” starts when “\(a)” starts."
        case .finishToFinish: return "“\(b)” finishes when “\(a)” finishes."
        case .startToFinish: return "“\(b)” finishes when “\(a)” starts."
        }
    }

    private func endpoint(_ id: UUID) -> some View {
        Button {
            store.openInspector(id)
        } label: {
            HStack(spacing: 6) {
                if let t = store.task(id) { KindIcon(kind: store.kind(of: id), colorHex: store.colorHex(for: t), size: 9) }
                Text(store.task(id)?.title ?? "?").font(Theme.titleFont(13)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .regular)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(height: 28))
    }
}

// MARK: - Time zone

/// Chooses the time zone times are shown in: the Mac's own (it follows you when you travel)
/// or a fixed one.
struct TimeZonePickerList: View {
    @ObservedObject var settings = TimeZoneSettings.shared
    var onPick: () -> Void = {}
    @ViewState private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [String] {
        let q = query.lowercased().replacingOccurrences(of: " ", with: "_")
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !q.isEmpty else { return all }
        return all.filter { $0.lowercased().contains(q) || Zones.offsetText(TimeZone(identifier: $0)!).lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show times in").font(Theme.font(11)).foregroundStyle(Theme.tertiaryText)
            TextField("Search, e.g. Tokyo or Berlin", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.font(13))
                .focused($searchFocused)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .fieldBackground(focused: searchFocused)
                .controlMarker("Time zone search")
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.isEmpty {
                        row(title: "Mac's time zone", detail: "\(Zones.label(settings.system)), follows you when you travel",
                            selected: settings.overrideID == nil, marker: "Time zone System") { settings.overrideID = nil }
                        Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 3)
                    }
                    ForEach(matches, id: \.self) { id in
                        let tz = TimeZone(identifier: id)!
                        row(title: id.replacingOccurrences(of: "_", with: " "), detail: Zones.offsetText(tz),
                            selected: settings.overrideID == id, marker: "Time zone \(id)") { settings.overrideID = id }
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(10)
        .frame(width: 330)
        .background(Theme.canvas)
    }

    private func row(title: String, detail: String, selected: Bool, marker: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPick()
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.font(13)).lineLimit(1)
                    Text(detail).font(Theme.font(10.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .regular)).foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 34))
        .controlMarker(marker)
    }
}

/// The time zone, shown at the bottom of the sidebar; click it to choose another.
struct TimeZoneButton: View {
    @ObservedObject var settings = TimeZoneSettings.shared
    @ViewState private var showing = false

    var body: some View {
        let tz = settings.current
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "globe").font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Zones.city(tz)).font(Theme.font(12)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\(Zones.offsetText(tz)) · \(settings.overrideID == nil ? "Mac's time zone" : "chosen time zone")")
                        .font(Theme.font(10.5)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 34))
        .help("Time zone for times and for “today”. Timed items keep their moment in time, like Apple Calendar.")
        .accessibilityLabel("Time Zone")
        .controlMarker("Time Zone")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            TimeZonePickerList { showing = false }
        }
    }
}
