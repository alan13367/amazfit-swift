import SwiftUI
import Charts
import HelioCore

struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06), lineWidth: 1))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.callout).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(color) }
            Text(value).font(.system(size: value == "Not available" ? 18 : 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(value == "Not available" ? "Not returned by this endpoint" : unit).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SmallStat: View {
    let title: String
    let value: String
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value + (unit.isEmpty ? "" : " " + unit)).font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
        }
    }
}

struct Notice: View {
    let title: String
    let message: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct NoData: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) { Image(systemName: "chart.xyaxis.line"); Text(text) }
            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
    }
}

struct TimelineChart: View {
    let points: [MetricPoint]
    let color: Color
    let range: ClosedRange<Double>?
    let zone: TimeZone
    @State private var selected: Date?
    private var nearest: MetricPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Value", point.value), series: .value("Segment", point.segment))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let point = nearest {
                RuleMark(x: .value("Time", point.date)).foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(point.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) · \(integer(point.value))")
                            .font(.caption.monospacedDigit()).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                PointMark(x: .value("Time", point.date), y: .value("Value", point.value)).foregroundStyle(color)
            }
        }
        .chartYScale(domain: range ?? automaticRange)
        .chartXAxis { timeAxis(zone: zone) }
        .chartXSelection(value: $selected)
        .accessibilityLabel("Timeline with \(points.count) readings. Use the pointer to inspect values.")
    }
    private var automaticRange: ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 100
        return max(0, low - 10)...(high + 10)
    }
}

@AxisContentBuilder func timeAxis(zone: TimeZone) -> some AxisContent {
    AxisMarks(values: .stride(by: .hour, count: 4)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
            }
        }
    }
}

struct JSONText: View {
    let value: JSONValue
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(value.prettyPrinted).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 80, maxHeight: 300)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("JSON cloud response")
    }
}

func integer(_ value: Double?) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "Not available"
}
func duration(_ minutes: Double?) -> String {
    guard let minutes, minutes.isFinite, minutes >= 0, minutes < 1_000_000 else { return "Not available" }
    let rounded = Int(minutes.rounded())
    return "\(rounded / 60)h \(rounded % 60)m"
}
