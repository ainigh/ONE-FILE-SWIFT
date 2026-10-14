import AppKit
import MPMCore
import SwiftUI

// The design's tokens (base.css): dark first, light verified. Colours follow the system appearance.

enum Theme {
    private static func dyn(_ dark: String, _ light: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    static let bg = dyn("#121214", "#F7F7F8")
    static let surface = dyn("#1B1B1F", "#FFFFFF")
    static let surface2 = dyn("#222228", "#F7F7F9")
    static let line = dyn("#2C2C32", "#E3E3E8")
    static let line2 = dyn("#3A3A42", "#D0D0D8")
    static let ink = dyn("#ECECF1", "#16161A")
    static let ink2 = dyn("#9A9AA6", "#6E6E7A")
    static let ink3 = dyn("#6A6A76", "#8A8A94")
    static let doing = dyn("#5B8DEF", "#2F6BE0")
    static let next = dyn("#8A7DF0", "#6A5CE8")
    static let done = dyn("#4FB37E", "#2E9B62")
    static let blocked = dyn("#C98A3B", "#B4762B")
    static let stop = dyn("#E0655B", "#D14E44")
    static let rest = dyn("#4FAFC9", "#2F97B5")
    static let chrome = dyn("#0C0C0E", "#ECECEF")
    static let onfill = NSColor.white

    static func nsColor(_ t: Tone) -> NSColor {
        switch t {
        case .doing: return doing
        case .next: return next
        case .done: return done
        case .blocked: return blocked
        case .stop: return stop
        case .rest: return rest
        case .ink2: return ink2
        case .ink3: return ink3
        }
    }
    static func color(_ t: Tone) -> Color { Color(nsColor: nsColor(t)) }

    static func status(_ s: DisplayStatus) -> Color {
        switch s {
        case .doing: return color(.doing)
        case .next: return color(.next)
        case .done: return color(.done)
        case .blocked: return color(.blocked)
        case .crossed: return Color(nsColor: ink2)
        case .open: return Color(nsColor: ink2)
        case .new: return Color(nsColor: ink3)
        }
    }

    // Type: the system face, with monospaced digits where numbers move.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static let body = Font.system(size: 13)
    static let fine = Font.system(size: 11)
    static let label = Font.system(size: 10.5, weight: .semibold)
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    static let bg = Color(nsColor: Theme.bg)
    static let surface = Color(nsColor: Theme.surface)
    static let surface2 = Color(nsColor: Theme.surface2)
    static let line = Color(nsColor: Theme.line)
    static let line2 = Color(nsColor: Theme.line2)
    static let ink = Color(nsColor: Theme.ink)
    static let ink2 = Color(nsColor: Theme.ink2)
    static let ink3 = Color(nsColor: Theme.ink3)
    static let doing = Color(nsColor: Theme.doing)
    static let next = Color(nsColor: Theme.next)
    static let done = Color(nsColor: Theme.done)
    static let blocked = Color(nsColor: Theme.blocked)
    static let stop = Color(nsColor: Theme.stop)
    static let rest = Color(nsColor: Theme.rest)
    static let chrome = Color(nsColor: Theme.chrome)
}

// MARK: - Controls the screens share

/// The app's button: primary (filled), plain (outlined), or a link.
struct MPMButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, danger, small, smallPrimary }
    var kind: Kind = .plain
    var big = false

    func makeBody(configuration: Configuration) -> some View {
        let filled = kind == .primary || kind == .smallPrimary || kind == .danger
        let small = kind == .small || kind == .smallPrimary
        let fill: Color = kind == .danger ? .stop : filled ? .doing : .surface
        configuration.label
            .font(.system(size: big ? 15 : small ? 12 : 13, weight: .semibold))
            .foregroundStyle(filled ? Color.white : .ink)
            .padding(.horizontal, big ? 22 : small ? 10 : 14)
            .padding(.vertical, big ? 10 : small ? 4 : 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(filled ? Color.clear : Color.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

struct LinkishStyle: ButtonStyle {
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: big ? 14 : 12.5))
            .foregroundStyle(Color.ink2)
            .underline(configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A segmented control in the design's clothes.
struct Seg<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T
    var badge: T? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { it in
                Button {
                    selection = it.0
                } label: {
                    HStack(spacing: 4) {
                        Text(it.1)
                        if badge == it.0 { Circle().fill(Color.stop).frame(width: 7, height: 7).overlay(Circle().stroke(Color.surface, lineWidth: 2)) }
                    }
                    .font(.system(size: 12, weight: selection == it.0 ? .semibold : .regular))
                    .foregroundStyle(selection == it.0 ? Color.ink : Color.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selection == it.0 ? Color.ink.opacity(0.09) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }
}

/// A small uppercase label, as the design's `.label`.
struct Label2: View {
    var text: String
    var color: Color = .ink3
    init(_ text: String, color: Color = .ink3) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(color)
    }
}

/// A card surface.
struct Card<Content: View>: View {
    var tone: Color? = nil
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
            .overlay(alignment: .leading) {
                if let t = tone { RoundedRectangle(cornerRadius: 2).fill(t).frame(width: 3).padding(.vertical, 10).padding(.leading, 0) }
            }
    }
}

/// The ring (DESIGN): a track and an arc that empties as the clock runs.
struct Ring: View {
    var fraction: Double          // 0 full … 1 empty
    var color: Color
    var lineWidth: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(Color.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, 1 - fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: fraction)
        }
    }
}
