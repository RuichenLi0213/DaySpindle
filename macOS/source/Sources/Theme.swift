import AppKit
import SwiftUI

/// Fonts and colors. Every color has a light and a dark value and resolves against the
/// appearance of the view it is drawn in, so the whole app follows the Appearance setting.
enum Theme {
    static let regularFontName = "Helvetica"
    static let boldFontName = "Helvetica-Bold"

    static func font(_ size: CGFloat) -> Font { .custom(regularFontName, fixedSize: size) }
    /// Bold is reserved for task titles (and the tags shown inline after them).
    static func titleFont(_ size: CGFloat) -> Font { .custom(boldFontName, fixedSize: size) }

    static func nsFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? boldFontName : regularFontName, size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    enum NS {
        // Surfaces
        static let canvas = NSColor.dynamic("#FFFFFF", "#1E1E20")
        static let sidebar = NSColor.dynamic("#F6F6F7", "#262628")
        static let divider = NSColor.dynamic("#E1E1E4", "#3A3A3D")
        static let controlFill = NSColor.dynamic("#F3F3F5", "#2E2E31")
        static let controlHover = NSColor.dynamic("#EAEAED", "#38383B")
        static let controlPressed = NSColor.dynamic("#E0E0E4", "#424246")
        static let controlBorder = NSColor.dynamic("#D9D9DE", "#47474B")
        static let segmentSelected = NSColor.dynamic("#FFFFFF", "#5B5B60")
        static let sidebarSelection = NSColor.dynamic("#E3E3E8", "#3A3A3E")
        static let sidebarHover = NSColor.dynamic("#000000", "#FFFFFF", alphaLight: 0.035, alphaDark: 0.05)
        static let fieldFill = NSColor.dynamic("#FFFFFF", "#19191B")
        static let filterBar = NSColor.dynamic("#FBFBFC", "#232325")
        static let filterChip = NSColor.dynamic("#ECECF0", "#38383B")
        static let errorFill = NSColor.dynamic("#FFF4F4", "#3A2121")

        // Text
        static let text = NSColor.dynamic("#1D1D1F", "#F2F2F5")
        static let secondaryText = NSColor.dynamic("#6E6E73", "#A3A3AA")
        static let tertiaryText = NSColor.dynamic("#A1A1A6", "#6F6F76")
        /// Tags shown after task titles (bold gray).
        static let tagText = NSColor.dynamic("#8A8A90", "#8E8E96")
        static let headerText = NSColor.dynamic("#3A3A3C", "#D6D6DB")

        // Accents
        static let accent = NSColor.dynamic("#2F6FEB", "#4C8DFF")
        /// The Today spindle's color (header label and circle); see `TodayStyle`.
        static var todayAccent: NSColor { TodayStyle.accent }
        /// The tint of today's column; see `TodayStyle`.
        static var todayFill: NSColor { TodayStyle.fill }
        static let destructive = NSColor.dynamic("#D93036", "#FF5A55")

        // Chart
        static let gridLine = NSColor.dynamic("#ECECEF", "#2D2D30")
        static let rowLine = NSColor.dynamic("#F1F1F3", "#29292C")
        static let monthLine = NSColor.dynamic("#D6D6DB", "#4A4A4E")
        static let weekend = NSColor.dynamic("#FAFAFB", "#222224")
        static let selection = NSColor.dynamic("#2F6FEB", "#4C8DFF", alphaLight: 0.08, alphaDark: 0.2)
        static let hover = NSColor.dynamic("#000000", "#FFFFFF", alphaLight: 0.025, alphaDark: 0.035)
        static let chipFill = NSColor.dynamic("#F0F0F3", "#303033")
        static let chevron = NSColor.dynamic("#8A8A90", "#8E8E96")
        static let bubbleFill = NSColor.dynamic("#1D1D1F", "#ECECF1", alphaLight: 0.9, alphaDark: 0.96)
        static let bubbleText = NSColor.dynamic("#FFFFFF", "#1D1D1F")
        /// Dependency arrows without a color of their own.
        static let linkLine = NSColor.dynamic("#6E6E78", "#A0A0AA")
        /// Dark text on light-colored bars, in either appearance.
        static let barDarkText = NSColor(hex: "#1D1D1F")
    }

    // SwiftUI equivalents (resolved against the view's appearance).
    static let canvas = Color(nsColor: NS.canvas)
    static let sidebar = Color(nsColor: NS.sidebar)
    static let divider = Color(nsColor: NS.divider)
    static let controlFill = Color(nsColor: NS.controlFill)
    static let controlHover = Color(nsColor: NS.controlHover)
    static let controlPressed = Color(nsColor: NS.controlPressed)
    static let controlBorder = Color(nsColor: NS.controlBorder)
    static let segmentSelected = Color(nsColor: NS.segmentSelected)
    static let sidebarSelection = Color(nsColor: NS.sidebarSelection)
    static let sidebarHover = Color(nsColor: NS.sidebarHover)
    static let fieldFill = Color(nsColor: NS.fieldFill)
    static let filterBar = Color(nsColor: NS.filterBar)
    static let filterChip = Color(nsColor: NS.filterChip)
    static let errorFill = Color(nsColor: NS.errorFill)
    static let text = Color(nsColor: NS.text)
    static let secondaryText = Color(nsColor: NS.secondaryText)
    static let tertiaryText = Color(nsColor: NS.tertiaryText)
    static let accent = Color(nsColor: NS.accent)
    static var todayAccent: Color { Color(nsColor: NS.todayAccent) }
    static var todayFill: Color { Color(nsColor: NS.todayFill) }
    static let destructive = Color(nsColor: NS.destructive)
}

/// The color of the Today spindle: the "Today" label, the date circle and the column tint.
/// Chosen by right-clicking the Today header; saved in the app's preferences.
enum TodayStyle {
    static let defaultHex = "#E5484D"
    static let defaultsKey = "TodayColor"
    static let choices: [(name: String, hex: String)] = [
        ("Red", "#E5484D"), ("Orange", "#F2811D"), ("Yellow", "#F5C518"), ("Green", "#30A46C"),
        ("Teal", "#0E9FC2"), ("Blue", "#2F6FEB"), ("Indigo", "#5B5BD6"), ("Purple", "#8E4EC6"),
        ("Pink", "#D6409F"), ("Gray", "#8B8D98"),
    ]

    private(set) static var hex: String = {
        RGB.normalizedHex(UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? defaultHex
    }()
    private(set) static var accent = makeAccent(hex)
    private(set) static var fill = makeFill(hex)

    static func set(_ newHex: String) {
        guard let h = RGB.normalizedHex(newHex) else { return }
        hex = h
        accent = makeAccent(h)
        fill = makeFill(h)
        UserDefaults.standard.set(h, forKey: defaultsKey)
    }

    private static func makeAccent(_ h: String) -> NSColor {
        if h == defaultHex { return .dynamic("#E5484D", "#FF5A5F") }
        let c = RGB(hex: h) ?? .black
        return .dynamic(h, c.mixed(with: .white, amount: 0.12).hex)
    }

    private static func makeFill(_ h: String) -> NSColor {
        if h == defaultHex { return .dynamic("#FFEFEC", "#3B2624") }
        let c = RGB(hex: h) ?? .black
        return .dynamic(c.mixed(with: .white, amount: 0.89).hex,
                        c.mixed(with: RGB(hex: "#1E1E20")!, amount: 0.80).hex)
    }

    /// The tint expected in the rendered timeline (for the self-check).
    static func expectedFill(dark: Bool) -> RGB {
        if hex == defaultHex { return RGB(hex: dark ? "#3B2624" : "#FFEFEC")! }
        let c = RGB(hex: hex) ?? .black
        return dark ? c.mixed(with: RGB(hex: "#1E1E20")!, amount: 0.80) : c.mixed(with: .white, amount: 0.89)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// A color with separate light and dark values.
    static func dynamic(_ light: String, _ dark: String, alphaLight: CGFloat = 1, alphaDark: CGFloat = 1) -> NSColor {
        let l = NSColor(hex: light).withAlphaComponent(alphaLight)
        let d = NSColor(hex: dark).withAlphaComponent(alphaDark)
        return NSColor(name: nil) { $0.isDark ? d : l }
    }
}

// MARK: - Appearance setting

/// System (follow macOS), or always Light / always Dark. Saved in the app's preferences.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Toolbar icon: a computer for System, a sun for Light, a moon for Dark.
    var symbol: String {
        switch self {
        case .system: return "desktopcomputer"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// The toolbar button cycles System → Light → Dark → System.
    var next: AppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    static let defaultsKey = "Appearance"

    @Published var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
            apply()
        }
    }

    private init() {
        mode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .system
    }

    /// Applies the mode to the whole app; with System, the app follows macOS.
    func apply() {
        NSApp.appearance = mode.nsAppearance
        appLog.notice("Appearance \(self.mode.rawValue, privacy: .public)")
    }
}

extension Color {
    init(hex: String) {
        let c = RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let c = RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    convenience init(rgb c: RGB) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    var rgb: RGB? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}

/// Small cache so drawing code doesn't re-parse hex strings on every frame.
enum ColorCache {
    private static var cache: [String: NSColor] = [:]
    static func color(_ hex: String) -> NSColor {
        if let c = cache[hex] { return c }
        let c = NSColor(hex: hex)
        cache[hex] = c
        return c
    }
}

// MARK: - Reusable SwiftUI controls

/// A light, rounded toolbar/sheet button in the style of macOS Calendar.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case normal, prominent, destructive, destructiveProminent, plain }
    var kind: Kind = .normal
    var height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind, height: height)
    }

    private struct PillButton: View {
        let configuration: ButtonStyle.Configuration
        let kind: Kind
        let height: CGFloat
        @ViewState private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.font(13))
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .plain ? 6 : 11)
                .frame(minHeight: height)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(kind == .normal ? Theme.controlBorder : .clear, lineWidth: 0.5))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .prominent, .destructiveProminent: return .white
            case .destructive: return Theme.destructive
            default: return Theme.text
            }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .prominent:
                return pressed ? Color(hex: "#2459C4") : (hovering ? Color(hex: "#2A63D6") : Theme.accent)
            case .destructiveProminent:
                return pressed ? Color(hex: "#B5262B") : (hovering ? Color(hex: "#C42B31") : Theme.destructive)
            case .plain:
                return pressed ? Theme.controlPressed : (hovering ? Theme.controlHover : .clear)
            case .normal, .destructive:
                return pressed ? Theme.controlPressed : (hovering ? Theme.controlHover : Theme.controlFill)
            }
        }
    }
}

/// A simple left-to-right wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            width = max(width, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Lets the user drag the window by the toolbar and the sidebar's top band,
/// since the content view extends under the transparent title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if action == "Minimize" { window?.performMiniaturize(nil) } else if action != "None" { window?.performZoom(nil) }
            } else {
                window?.performDrag(with: event)
            }
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// View-local state, equivalent to SwiftUI's `@State`.
///
/// In the macOS 27 SDK `@State` is a compiler macro whose plugin ships only with
/// full Xcode; this wrapper (built on `@StateObject`) also compiles with just the
/// Command Line Tools.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> { $box.value }
}

// MARK: - Control markers for the self-check

/// Lets the scripted self-check find a control's on-screen frame by name, so it can
/// click it with a synthesized pointer event. A plain, invisible NSView placed behind the
/// control; it draws nothing and takes no clicks.
@MainActor
enum ControlMarkers {
    private final class Box { weak var view: NSView? ; init(_ v: NSView) { view = v } }
    private static var boxes: [String: [Box]] = [:]

    static func register(_ name: String, _ view: NSView) {
        boxes[name, default: []].removeAll { $0.view == nil || $0.view === view }
        boxes[name, default: []].append(Box(view))
    }

    /// The visible marker with this name in `window`, if any.
    static func view(_ name: String, in window: NSWindow) -> NSView? {
        boxes[name]?.compactMap(\.view).first { v in
            v.window === window && !v.isHiddenOrHasHiddenAncestor && v.bounds.width > 0 && v.bounds.height > 0
        }
    }
}

final class MarkerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct MarkerRepresentable: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> MarkerView {
        let v = MarkerView()
        ControlMarkers.register(name, v)
        return v
    }
    func updateNSView(_ v: MarkerView, context: Context) { ControlMarkers.register(name, v) }
}

extension View {
    /// Names this control for the self-check (see `ControlMarkers`).
    func controlMarker(_ name: String) -> some View { background(MarkerRepresentable(name: name)) }
}
