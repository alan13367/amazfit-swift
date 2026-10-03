import SwiftUI
import HelioCore

/// Colors are tuned for the app's dark surfaces. Categorical and ordinal sets were checked for
/// lightness, color-vision-deficiency separation, and contrast against `card`.
enum Palette {
    static let background = Color(hex: 0x0D0E11)
    static let card = Color(hex: 0x17181C)
    static let raised = Color(hex: 0x1F2126)
    static let hairline = Color.white.opacity(0.08)
    static let grid = Color.white.opacity(0.07)
    static let muted = Color(hex: 0x8A8B92)

    static let heart = Color(hex: 0xFF5A6E)
    static let sleep = Color(hex: 0x8C7CF6)
    static let activity = Color(hex: 0x3DD68C)
    static let stress = Color(hex: 0xF5B544)
    static let workout = Color(hex: 0xFF8A3D)
    static let load = Color(hex: 0x4FB3FF)
    static let accent = Color(hex: 0x5EE0C1)

    static func stage(_ kind: SleepStage.Kind) -> Color {
        switch kind {
        case .awake: Color(hex: 0xE0663E)
        case .rem: Color(hex: 0x289FBC)
        case .light: Color(hex: 0x5B70E6)
        case .deep: Color(hex: 0xC45AB4)
        }
    }
    /// "Light" (below the first zone) is neutral; the five training zones are one red hue, darker to brighter.
    static let zones: [Color] = [Color(hex: 0x4A4D55), Color(hex: 0x7E3B4E), Color(hex: 0xA54556),
                                 Color(hex: 0xCC525D), Color(hex: 0xEC6A64), Color(hex: 0xFFA08C)]
    static func zone(_ index: Int) -> Color { zones[max(0, min(index, zones.count - 1))] }
    static func stress(_ level: StressLevel) -> Color {
        [Color(hex: 0x735628), Color(hex: 0xA6772A), Color(hex: 0xD69A30), Color(hex: 0xFFC861)][level.rawValue]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum Format {
    static func int(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
    }
    static func decimal(_ value: Double?, digits: Int = 1) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(digits))) } ?? "—"
    }
    static func duration(minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes >= 0, minutes < 1_000_000 else { return "—" }
        let rounded = Int(minutes.rounded())
        if rounded < 60 { return "\(rounded)m" }
        return rounded % 60 == 0 ? "\(rounded / 60)h" : "\(rounded / 60)h \(rounded % 60)m"
    }
    static func duration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(meters < 10_000 ? 2 : 1)))
    }
    /// Pace from seconds per meter, as minutes per kilometer.
    static func pace(_ secondsPerMeter: Double?) -> String {
        guard let secondsPerMeter, secondsPerMeter > 0, secondsPerMeter < 60 else { return "—" }
        let total = Int((secondsPerMeter * 1000).rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }
    static func time(_ date: Date?, _ zone: TimeZone) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    /// Cloud day strings are calendar dates; format them without shifting through the Mac's time zone.
    static func day(_ string: String, _ style: Date.FormatStyle) -> String {
        guard let date = parser.date(from: string) else { return string }
        var style = style
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return date.formatted(style)
    }
    static func longDay(_ string: String) -> String { day(string, .dateTime.weekday(.wide).month(.wide).day()) }
    static func shortDay(_ string: String) -> String { day(string, .dateTime.month(.abbreviated).day()) }
    static func weekday(_ string: String) -> String { day(string, .dateTime.weekday(.abbreviated)) }
    static func dayNumber(_ string: String) -> String { day(string, .dateTime.day()) }
    static func relativeDay(_ string: String) -> String {
        let today = parser.string(from: Date().addingTimeInterval(Double(TimeZone.current.secondsFromGMT())))
        if string == today { return "Today" }
        if let date = parser.date(from: string), parser.string(from: date.addingTimeInterval(86400)) == today { return "Yesterday" }
        return longDay(string)
    }
}

// MARK: - Surfaces

struct Card<Content: View, Accessory: View>: View {
    var title: String?
    var symbol: String?
    var tint: Color = Palette.accent
    var subtitle: String?
    var padding: CGFloat = 20
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                HStack(alignment: .center, spacing: 10) {
                    if let symbol { IconBadge(symbol: symbol, tint: tint, size: 26) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String? = nil, symbol: String? = nil, tint: Color = Palette.accent, subtitle: String? = nil,
         padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, tint: tint, subtitle: subtitle, padding: padding, accessory: { EmptyView() }, content: content)
    }
}

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct Ring: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: [tint.opacity(0.65), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, min(progress, 1)))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle().trim(from: 0, to: min(progress - 1, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
        }
        .padding(lineWidth / 2)
    }
}

/// A headline number with its unit, the primary figure on a tile.
struct Figure: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 30
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(value == "—" ? .secondary : .primary)
            if !unit.isEmpty && value != "—" {
                Text(unit).font(.system(size: max(11, size * 0.42), weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var detail: String?
    var symbol: String?
    var tint: Color = Palette.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint) }
                Eyebrow(text: title).lineLimit(1).minimumScaleFactor(0.8)
            }
            Figure(value: value, unit: unit, size: 26)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline))
    }
}

/// A compact label and value for use inside cards.
struct MiniStat: View {
    let title: String
    let value: String
    var unit: String = ""
    var tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Figure(value: value, unit: unit, size: 19)
        }
    }
}

struct LegendItem: View {
    let title: String
    let color: Color
    var value: String?
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let value { Text(value).font(.caption.weight(.medium)).monospacedDigit() }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var height: CGFloat = 140
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

struct Banner: View {
    let title: String
    let message: String
    var symbol = "info.circle"
    var tint: Color = Palette.accent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 15, weight: .semibold)).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }
}

/// A horizontal bar split into proportional segments with 2pt gaps.
struct ProportionBar: View {
    let parts: [(value: Double, color: Color)]
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { proxy in
            let visible = parts.filter { $0.value > 0 }
            let total = visible.reduce(0) { $0 + $1.value }
            let gaps = CGFloat(max(0, visible.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: height / 3, style: .continuous).fill(part.color)
                        .frame(width: total > 0 ? max(2, (proxy.size.width - gaps) * part.value / total) : 0)
                }
            }
        }
        .frame(height: height)
    }
}

struct Tooltip: View {
    let title: String
    let value: String
    var tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 6, height: 6) }
                Text(value).font(.caption.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// An adaptive grid used for tile rows.
struct TileGrid<Content: View>: View {
    var minimum: CGFloat = 170
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 14)], spacing: 14) { content }
    }
}
