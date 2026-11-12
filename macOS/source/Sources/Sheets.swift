import AppKit
import SwiftUI

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(11)).foregroundStyle(Theme.secondaryText)
            content()
        }
    }
}

private struct FieldBackground: ViewModifier {
    var focused: Bool
    var invalid = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(invalid ? Theme.destructive : (focused ? Theme.accent.opacity(0.7) : Theme.controlBorder),
                              lineWidth: focused || invalid ? 1.5 : 1))
    }
}

extension View {
    func fieldBackground(focused: Bool = false, invalid: Bool = false) -> some View {
        modifier(FieldBackground(focused: focused, invalid: invalid))
    }
}

/// A hex color entry ("#2F6FEB", also "2f6feb" or "#2F6") with a live swatch and a color well.
/// Writes `hex` only when the text is a valid color; `invalid` reports text that isn't.
struct HexColorField: View {
    @Binding var hex: String
    @Binding var invalid: Bool
    var placeholder = "#2F6FEB"
    /// Empty text is allowed and means "no color of its own".
    var allowEmpty = false
    var marker: String
    @ViewState private var text: String
    @FocusState private var focused: Bool

    init(hex: Binding<String>, invalid: Binding<Bool>, placeholder: String = "#2F6FEB", allowEmpty: Bool = false, marker: String) {
        _hex = hex
        _invalid = invalid
        self.placeholder = placeholder
        self.allowEmpty = allowEmpty
        self.marker = marker
        _text = ViewState(wrappedValue: hex.wrappedValue)
    }

    private var shown: String { RGB.normalizedHex(text) ?? (hex.isEmpty ? placeholder : hex) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color(hex: shown))
                    .frame(width: 14, height: 14)
                    .opacity(text.isEmpty && allowEmpty ? 0.35 : 1)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.font(13))
                    .focused($focused)
                    .frame(width: 86)
                    .onChange(of: text) { _, new in
                        if let h = RGB.normalizedHex(new) {
                            if h != hex { hex = h }
                            invalid = false
                        } else if new.trimmingCharacters(in: .whitespaces).isEmpty && allowEmpty {
                            if !hex.isEmpty { hex = "" }
                            invalid = false
                        } else {
                            invalid = true
                        }
                    }
                    .onSubmit { if let h = RGB.normalizedHex(text) { text = h } }
                    .controlMarker(marker)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .fieldBackground(focused: focused, invalid: invalid)
            ColorPicker("", selection: Binding(get: { Color(hex: shown) },
                                               set: { if let rgb = NSColor($0).rgb { hex = rgb.hex; text = rgb.hex } }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Pick a color")
        }
        // Keep the text in step when the color changes elsewhere (a swatch, the color well).
        .onChange(of: hex) { _, new in
            if RGB.normalizedHex(text) != new && !(new.isEmpty && text.isEmpty) { text = new; invalid = false }
        }
    }
}

/// Chooses the group or task an item belongs under. Lists every group and task except this
/// item and what's inside it, indented in outline order.
struct ParentPickerButton: View {
    @ObservedObject var store: Store
    let taskID: UUID?
    @Binding var parentID: UUID?
    @ViewState private var showing = false

    var body: some View {
        let parent = parentID.flatMap { store.task($0) }
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                if let parent {
                    Circle().fill(Color(hex: store.colorHex(for: parent))).frame(width: 8, height: 8)
                    Text(parent.title).font(Theme.titleFont(13)).lineLimit(1)
                } else {
                    Text("None (top level)").font(Theme.font(13)).foregroundStyle(Theme.secondaryText)
                }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityLabel("Inside")
        .controlMarker("Inside")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ParentList(store: store, candidates: store.parentCandidates(for: taskID), selected: parentID) { id in
                parentID = id
                showing = false
            }
        }
    }
}

private struct ParentList: View {
    @ObservedObject var store: Store
    let candidates: [(task: TaskItem, depth: Int)]
    let selected: UUID?
    let pick: (UUID?) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                row(selected == nil, name: "None (top level)") {
                    Text("None (top level)").font(Theme.font(13)).foregroundStyle(Theme.secondaryText)
                } action: { pick(nil) }
                if !candidates.isEmpty {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 3)
                }
                ForEach(candidates.indices, id: \.self) { i in
                    let c = candidates[i]
                    row(selected == c.task.id, name: c.task.title) {
                        HStack(spacing: 6) {
                            KindIcon(kind: store.kind(of: c.task.id), colorHex: store.colorHex(for: c.task), size: 9)
                            Text(c.task.title).font(Theme.titleFont(13)).lineLimit(1)
                            if let d = store.displayDates(c.task.id) {
                                Text(DayFormat.range(d.start, d.end, referenceYear: store.today.year))
                                    .font(Theme.font(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            }
                        }
                        .padding(.leading, CGFloat(min(c.depth, 8)) * 14)
                    } action: { pick(c.task.id) }
                }
            }
            .padding(8)
        }
        .frame(width: 320)
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.canvas)
    }

    private func row<Label: View>(_ isSelected: Bool, name: String, @ViewBuilder label: () -> Label,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .regular)).foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PillButtonStyle(kind: .plain, height: 26))
        .accessibilityLabel(name)
        .controlMarker(name)
    }
}

// MARK: - Category editor

struct CategoryEditorSheet: View {
    @ObservedObject var store: Store
    @ViewState private var draft: CategoryDraft
    @ViewState private var error: String?
    @FocusState private var nameFocused: Bool

    init(store: Store, draft: CategoryDraft) {
        self.store = store
        _draft = ViewState(wrappedValue: draft)
    }

    private var isNew: Bool { draft.categoryID == nil }

    @ViewState private var hexInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Category" : "Edit Category").font(Theme.font(17))

            LabeledField("Name") {
                TextField("e.g. Work", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(Theme.font(14))
                    .focused($nameFocused)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .fieldBackground(focused: nameFocused)
            }

            LabeledField("Color") {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                        ForEach(Palette.colors, id: \.hex) { entry in
                            let selected = entry.hex.uppercased() == draft.colorHex.uppercased()
                            Button {
                                draft.colorHex = entry.hex
                            } label: {
                                Circle().fill(Color(hex: entry.hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: selected ? 2 : 0))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? Color(hex: entry.hex) : .clear, lineWidth: 2))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(entry.name)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Hex").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                        HexColorField(hex: $draft.colorHex, invalid: $hexInvalid, marker: "Category hex")
                    }
                    if hexInvalid {
                        Text("Type a hex color such as #2F6FEB.").font(Theme.font(11)).foregroundStyle(Theme.destructive)
                    }
                }
            }

            LabeledField("Note") {
                TextEditor(text: $draft.notes)
                    .font(Theme.font(13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                    .frame(height: 64)
                    .fieldBackground()
                    .controlMarker("Category editor note")
            }

            LabeledField("Preview") {
                let rgb = RGB(hex: draft.colorHex) ?? .black
                Text(draft.name.isEmpty ? "Sample task" : "\(draft.name) task")
                    .font(Theme.titleFont(12))
                    .foregroundStyle(rgb.prefersLightText ? Color.white : Color(nsColor: Theme.NS.barDarkText))
                    .padding(.horizontal, 10)
                    .frame(width: 220, height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: draft.colorHex)))
            }

            if let error {
                Text(error).font(Theme.font(12)).foregroundStyle(Theme.destructive)
            }

            HStack(spacing: 8) {
                if let id = draft.categoryID, store.categories.count > 1 {
                    Button("Delete Category…") { store.requestDeleteCategory(id) }
                        .buttonStyle(PillButtonStyle(kind: .destructive))
                }
                Spacer()
                Button("Cancel") { store.activeSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Category" : "Save") { error = store.saveCategoryDraft(draft) }
                    .buttonStyle(PillButtonStyle(kind: .prominent))
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || hexInvalid)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { nameFocused = true }
    }
}

// MARK: - Tag editor

struct TagEditorSheet: View {
    @ObservedObject var store: Store
    @ViewState private var draft: TagDraft
    @ViewState private var error: String?
    @FocusState private var focused: Bool

    init(store: Store, draft: TagDraft) {
        self.store = store
        _draft = ViewState(wrappedValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Tag").font(Theme.font(17))
            LabeledField("Name") {
                HStack(spacing: 2) {
                    Text("#").font(Theme.font(14)).foregroundStyle(Theme.secondaryText)
                    TextField("tag", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(Theme.font(14))
                        .focused($focused)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .fieldBackground(focused: focused)
            }
            Text("Used by \(DayFormat.taskCount(store.taskCount(tag: draft.original))). Renaming to an existing tag merges them.")
                .font(Theme.font(12))
                .foregroundStyle(Theme.secondaryText)
            if let error {
                Text(error).font(Theme.font(12)).foregroundStyle(Theme.destructive)
            }
            HStack(spacing: 8) {
                Button("Delete Tag…") { store.requestDeleteTag(draft.original) }
                    .buttonStyle(PillButtonStyle(kind: .destructive))
                Spacer()
                Button("Cancel") { store.activeSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { error = store.saveTagDraft(draft) }
                    .buttonStyle(PillButtonStyle(kind: .prominent))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}

// MARK: - Category note

/// Right-click a category › Add Note… / Edit Note…
struct CategoryNoteSheet: View {
    @ObservedObject var store: Store
    let categoryID: UUID
    private let hadNote: Bool
    @ViewState private var text: String
    @FocusState private var focused: Bool

    init(store: Store, categoryID: UUID, text: String) {
        self.store = store
        self.categoryID = categoryID
        hadNote = !text.isEmpty
        _text = ViewState(wrappedValue: text)
    }

    var body: some View {
        let c = store.category(categoryID)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: c?.colorHex ?? "#8B8D98")).frame(width: 10, height: 10)
                Text("Note for “\(c?.name ?? "")”").font(Theme.font(17))
            }
            TextEditor(text: $text)
                .font(Theme.font(13))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .frame(height: 150)
                .fieldBackground(focused: focused)
                .controlMarker("Category note")
            Text("Shown when you hover over the category in the sidebar. Return starts a new line; ⌘Return saves.")
                .font(Theme.font(11))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if hadNote {
                    Button("Remove Note") { store.saveCategoryNote(categoryID, "") }
                        .buttonStyle(PillButtonStyle(kind: .destructive))
                }
                Spacer()
                Button("Cancel") { store.activeSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { store.saveCategoryNote(categoryID, text) }
                    .buttonStyle(PillButtonStyle(kind: .prominent))
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlMarker("Save note")
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { focused = true }
    }
}

// MARK: - Today color

/// Right-click the Today header › Custom Color…: any color by hex value.
struct TodayColorSheet: View {
    @ObservedObject var store: Store
    @ViewState private var hex: String
    @ViewState private var hexInvalid = false

    init(store: Store, hex: String) {
        self.store = store
        _hex = ViewState(wrappedValue: hex)
    }

    var body: some View {
        let accent = Color(hex: hex)
        let rgb = RGB(hex: hex) ?? .black
        VStack(alignment: .leading, spacing: 16) {
            Text("Today Color").font(Theme.font(17))
            LabeledField("Color") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(TodayStyle.choices, id: \.hex) { c in
                            let selected = c.hex == hex
                            Button { hex = c.hex } label: {
                                Circle().fill(Color(hex: c.hex)).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: selected ? 2 : 0))
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(selected ? Color(hex: c.hex) : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(c.name)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Hex").font(Theme.font(12)).foregroundStyle(Theme.secondaryText)
                        HexColorField(hex: $hex, invalid: $hexInvalid, placeholder: TodayStyle.defaultHex, marker: "Today hex")
                    }
                }
            }
            LabeledField("Preview") {
                VStack(spacing: 3) {
                    Text(DayFormat.weekdayShort[store.today.weekday]).font(Theme.font(10)).foregroundStyle(accent)
                    Text("\(store.today.dayOfMonth)").font(Theme.font(13))
                        .foregroundStyle(rgb.prefersLightText ? Color.white : Color(nsColor: Theme.NS.barDarkText))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(accent))
                }
                .frame(width: 48, height: 64)
                .background(Color(hex: rgb.mixed(with: .white, amount: 0.89).hex).opacity(0.9))
            }
            HStack(spacing: 8) {
                Button("Use Red") { hex = TodayStyle.defaultHex }
                    .buttonStyle(PillButtonStyle())
                Spacer()
                Button("Cancel") { store.activeSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.setTodayColor(hex)
                    store.activeSheet = nil
                }
                .buttonStyle(PillButtonStyle(kind: .prominent))
                .keyboardShortcut(.defaultAction)
                .disabled(hexInvalid)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}

extension DayFormat {
    static func taskCount(_ n: Int) -> String { n == 1 ? "1 task" : "\(n) tasks" }
}

// MARK: - Confirmation

struct ConfirmSheet: View {
    @ObservedObject var store: Store
    let confirmation: Confirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleText.font(Theme.font(15)).fixedSize(horizontal: false, vertical: true)
            Text(confirmation.message)
                .font(Theme.font(12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                if confirmation.confirmTitle.isEmpty {
                    Button("OK") { store.activeSheet = nil }
                        .buttonStyle(PillButtonStyle(kind: .prominent))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { store.activeSheet = nil }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(confirmation.confirmTitle) {
                        store.activeSheet = nil
                        confirmation.action()
                    }
                    .buttonStyle(PillButtonStyle(kind: .destructiveProminent))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 380)
    }

    /// The title with any task title in bold.
    private var titleText: Text {
        guard let e = confirmation.emphasis, let r = confirmation.title.range(of: e) else {
            return Text(confirmation.title)
        }
        return Text(String(confirmation.title[..<r.lowerBound]))
            + Text(e).font(Theme.titleFont(15))
            + Text(String(confirmation.title[r.upperBound...]))
    }
}
