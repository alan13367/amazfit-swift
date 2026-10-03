import SwiftUI
import Charts
import HelioCore

// MARK: - Axes

@AxisContentBuilder func hourAxis(zone: TimeZone, every hours: Int = 3) -> some AxisContent {
    AxisMarks(values: .stride(by: .hour, count: hours, calendar: calendar(zone))) { value in
        AxisGridLine().foregroundStyle(Palette.grid)
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }
}

@AxisContentBuilder func valueAxis(_ suffix: String = "") -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(Palette.grid)
        AxisValueLabel {
            if let number = value.as(Double.self) {
                Text(number.formatted(.number.precision(.fractionLength(0))) + suffix).font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }
}

func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

func nearest(_ points: [MetricPoint], to date: Date?, within seconds: TimeInterval = 600) -> MetricPoint? {
    guard let date, !points.isEmpty else { return nil }
    var low = 0, high = points.count - 1
    while low < high {
        let mid = (low + high) / 2
        if points[mid].date < date { low = mid + 1 } else { high = mid }
    }
    let candidates = [points[max(0, low - 1)], points[low]]
    guard let best = candidates.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
          abs(best.date.timeIntervalSince(date)) <= seconds else { return nil }
    return best
}

// MARK: - Heart rate

struct Highlight: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let symbol: String
    let tint: Color
    var compact = false
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// What a hover layer shows for the point under the pointer.
struct HoverReadout: Equatable {
    let date: Date
    let value: Double
    let title: String
    let text: String
    let tint: Color
}

/// Hover handling that lives outside the chart's marks. Pointer movement only updates this layer,
/// so dense charts are never rebuilt while the pointer moves across them.
struct ChartHoverLayer: View {
    let proxy: ChartProxy
    var showsPoint = true
    let resolve: (Date) -> HoverReadout?
    @State private var readout: HoverReadout?

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let location) = phase, plot.contains(location),
                                  let date: Date = proxy.value(atX: location.x - plot.minX) else {
                                if readout != nil { readout = nil }
                                return
                            }
                            let next = resolve(date)
                            if next != readout { readout = next }
                        }
                    if let readout, let x = proxy.position(forX: readout.date) {
                        let px = plot.minX + x
                        Rectangle().fill(Color.white.opacity(0.28)).frame(width: 1, height: plot.height)
                            .position(x: px, y: plot.midY)
                        if showsPoint, let y = proxy.position(forY: readout.value) {
                            Circle().fill(readout.tint).overlay(Circle().strokeBorder(Palette.card, lineWidth: 2))
                                .frame(width: 11, height: 11).position(x: px, y: plot.minY + y)
                        }
                        Tooltip(title: readout.title, value: readout.text, tint: readout.tint).fixedSize()
                            .position(x: min(max(px, plot.minX + 70), plot.maxX - 70), y: plot.minY + 20)
                    }
                }
                .allowsHitTesting(true)
            }
        }
    }
}

/// A full device day of minute heart rate with sleep and workouts shaded behind it.
struct HeartRateDayChart: View {
    let points: [MetricPoint]
    let range: ClosedRange<Date>
    let zone: TimeZone
    var highlights: [Highlight] = []
    var resting: Double?
    var peak: (bpm: Double, date: Date?)?

    var body: some View {
        let domain = domain()
        let interpolation: InterpolationMethod = points.count > 240 ? .linear : .monotone
        let fill = LinearGradient(colors: [Palette.heart.opacity(0.32), Palette.heart.opacity(0.0)], startPoint: .top, endPoint: .bottom)
        Chart {
            ForEach(highlights) { item in
                RectangleMark(xStart: .value("Start", max(item.start, range.lowerBound)), xEnd: .value("End", min(item.end, range.upperBound)))
                    .foregroundStyle(item.tint.opacity(0.13))
                    .annotation(position: .overlay, alignment: .topLeading) {
                        // Workouts are often back to back, so they carry only their icon; the legend and hover name them.
                        Label(item.title, systemImage: item.symbol).labelStyle(item.compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(item.tint)
                            .padding(.leading, 6).padding(.top, 5).lineLimit(1).fixedSize()
                    }
            }
            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("BPM", point.value),
                         series: .value("Segment", point.segment))
                    .foregroundStyle(fill)
                    .interpolationMethod(interpolation)
                LineMark(x: .value("Time", point.date), y: .value("BPM", point.value), series: .value("Segment", point.segment))
                    .foregroundStyle(Palette.heart)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(interpolation)
            }
            if let resting {
                RuleMark(y: .value("Resting", resting))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("Resting \(Format.int(resting))").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
            }
            if let peak, let date = peak.date, range.contains(date) {
                PointMark(x: .value("Time", date), y: .value("BPM", peak.bpm))
                    .symbolSize(60).foregroundStyle(Palette.heart)
                    .annotation(position: .trailing, spacing: 5) {
                        Text("Max \(Format.int(peak.bpm))").font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary)
                    }
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: domain)
        .chartXAxis { hourAxis(zone: zone) }
        .chartYAxis { valueAxis() }
        .chartOverlay { proxy in
            ChartHoverLayer(proxy: proxy) { [points, zone] date in
                nearest(points, to: date, within: 180).map {
                    HoverReadout(date: $0.date, value: $0.value, title: Format.time($0.date, zone), text: "\(Format.int($0.value)) bpm", tint: Palette.heart)
                }
            }
        }
        .accessibilityLabel("Heart rate for the day, \(points.count) minute readings")
    }

    private func domain() -> ClosedRange<Double> {
        var low = resting ?? .infinity, high = peak?.bpm ?? -.infinity
        for point in points { low = min(low, point.value); high = max(high, point.value) }
        if !low.isFinite { low = 50 }
        if !high.isFinite { high = 120 }
        return max(0, ((low - 8) / 10).rounded(.down) * 10)...(((high + 12) / 10).rounded(.up) * 10)
    }
}

/// Heart rate during a workout, over its configured zone bands.
struct WorkoutHeartChart: View {
    let points: [MetricPoint]
    let range: ClosedRange<Date>
    let zone: TimeZone
    let bounds: [Double]

    var body: some View {
        let points = points.filter { range.contains($0.date) }
        let values = points.map(\.value)
        let domain = max(40, ((values.min() ?? 80) - 10).rounded(.down))...((values.max() ?? 160) + 10).rounded(.up)
        Chart {
            ForEach(Array(bounds.enumerated()), id: \.offset) { index, upper in
                let lower = index == 0 ? domain.lowerBound : bounds[index - 1]
                if upper > domain.lowerBound && lower < domain.upperBound {
                    RectangleMark(yStart: .value("Low", max(lower, domain.lowerBound)), yEnd: .value("High", min(upper, domain.upperBound)))
                        .foregroundStyle(Palette.zone(index).opacity(0.24))
                        .annotation(position: .overlay, alignment: .trailing) {
                            Text(HeartZoneTime.titles[min(index, 5)]).font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary).padding(.trailing, 6)
                        }
                }
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("BPM", point.value), series: .value("Segment", point.segment))
                    .foregroundStyle(Palette.heart).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Palette.grid)
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.time(date, zone)).font(.caption2).foregroundStyle(Palette.muted) }
                }
            }
        }
        .chartYAxis { valueAxis() }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            ChartHoverLayer(proxy: proxy) { [points, zone] date in
                nearest(points, to: date, within: 120).map {
                    HoverReadout(date: $0.date, value: $0.value, title: Format.time($0.date, zone), text: "\(Format.int($0.value)) bpm", tint: Palette.heart)
                }
            }
        }
    }
}

/// Seconds per heart-rate zone as labeled horizontal bars.
struct ZoneBars: View {
    let zones: [HeartZoneTime]
    var body: some View {
        let total = max(1, zones.reduce(0) { $0 + $1.seconds })
        let longest = max(1, zones.map(\.seconds).max() ?? 1)
        VStack(spacing: 9) {
            ForEach(zones.reversed()) { zone in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(zone.title).font(.caption.weight(.medium))
                        Text(zone.lower.map { "\(Int($0))–\(Int(zone.upper))" } ?? "< \(Int(zone.upper))")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(width: 78, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.05))
                            Capsule().fill(Palette.zone(zone.index))
                                .frame(width: zone.seconds > 0 ? max(4, proxy.size.width * zone.seconds / longest) : 0)
                        }
                    }
                    .frame(height: 8)
                    Text(Format.duration(minutes: zone.seconds / 60)).font(.caption.weight(.medium)).monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                    Text("\(Int((100 * zone.seconds / total).rounded()))%").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Sleep

struct Hypnogram: View {
    let stages: [SleepStage]
    let zone: TimeZone
    var compact = false
    @State private var selected: Date?
    static let order: [SleepStage.Kind] = [.awake, .rem, .light, .deep]

    var body: some View {
        let known = stages.filter { $0.kind != nil }
        let hovered = selected.flatMap { date in known.first { $0.start <= date && date < $0.end } }
        Chart {
            ForEach(known) { stage in
                BarMark(xStart: .value("Start", stage.start), xEnd: .value("End", stage.end),
                        y: .value("Stage", stage.title), height: .ratio(compact ? 0.8 : 0.72))
                    .foregroundStyle(Palette.stage(stage.kind!))
                    .cornerRadius(compact ? 2 : 3)
                    .opacity(hovered == nil || hovered?.id == stage.id ? 1 : 0.45)
            }
            if let hovered, !compact {
                RuleMark(x: .value("Time", selected!)).foregroundStyle(.white.opacity(0.22))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(title: "\(Format.time(hovered.start, zone)) – \(Format.time(hovered.end, zone))",
                                value: "\(hovered.title) · \(Format.duration(minutes: hovered.minutes))", tint: Palette.stage(hovered.kind!))
                    }
            }
        }
        .chartYScale(domain: Self.order.map(\.title))
        .chartXScale(domain: (known.first?.start ?? Date())...(known.last?.end ?? Date()))
        .chartXAxis {
            if compact {
                AxisMarks(values: [known.first?.start, known.last?.end].compactMap { $0 }) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                        if let date = value.as(Date.self) { Text(Format.time(date, zone)).font(.caption2).foregroundStyle(Palette.muted) }
                    }
                }
            } else { hourAxis(zone: zone, every: 1) }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Palette.grid)
                if !compact {
                    AxisValueLabel { if let name = value.as(String.self) { Text(name).font(.caption).foregroundStyle(.secondary) } }
                }
            }
        }
        .chartXSelection(value: $selected)
        .accessibilityLabel("Sleep stages timeline")
    }
}

/// Minutes per stage with share of the night.
struct StageBreakdown: View {
    let day: BandDay
    var body: some View {
        let kinds: [SleepStage.Kind] = [.deep, .light, .rem, .awake]
        let total = max(1, kinds.reduce(0) { $0 + day.minutes(in: $1) })
        VStack(spacing: 12) {
            ProportionBar(parts: kinds.map { (day.minutes(in: $0), Palette.stage($0)) }, height: 12)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(kinds, id: \.self) { kind in
                    let minutes = day.minutes(in: kind)
                    GridRow {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.stage(kind)).frame(width: 10, height: 10)
                            Text(kind.title).font(.callout)
                        }
                        Spacer()
                        Text(Format.duration(minutes: minutes)).font(.callout.weight(.semibold)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text("\(Int((100 * minutes / total).rounded()))%").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Activity and stress

struct HourlyStepsChart: View {
    let hours: [Int]
    let start: Date
    let zone: TimeZone
    var compact = false
    @State private var selected: Date?

    var body: some View {
        let entries = hours.enumerated().map { (date: start.addingTimeInterval(Double($0.offset) * 3600), steps: $0.element) }
        let hovered = selected.flatMap { date in entries.last { $0.date <= date } }
        Chart {
            ForEach(entries.filter { $0.steps > 0 }, id: \.date) { entry in
                RectangleMark(xStart: .value("Start", entry.date.addingTimeInterval(300)), xEnd: .value("End", entry.date.addingTimeInterval(3300)),
                              yStart: .value("Base", 0), yEnd: .value("Steps", entry.steps))
                    .foregroundStyle(Palette.activity.opacity(hovered == nil || hovered?.date == entry.date ? 1 : 0.4))
                    .cornerRadius(3)
            }
            if let hovered, !compact {
                RuleMark(x: .value("Hour", hovered.date.addingTimeInterval(1800))).foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(title: "\(Format.time(hovered.date, zone)) – \(Format.time(hovered.date.addingTimeInterval(3600), zone))",
                                value: "\(hovered.steps.formatted()) steps", tint: Palette.activity)
                    }
            }
        }
        .chartXScale(domain: start...start.addingTimeInterval(86400))
        .chartXAxis { hourAxis(zone: zone, every: compact ? 6 : 3) }
        .chartYAxis { valueAxis() }
        .chartXSelection(value: $selected)
        .accessibilityLabel("Steps per hour")
    }
}

struct StressDayChart: View {
    let points: [MetricPoint]
    let range: ClosedRange<Date>
    let zone: TimeZone

    var body: some View {
        Chart {
            ForEach(points) { point in
                RectangleMark(xStart: .value("Start", point.date.addingTimeInterval(30)), xEnd: .value("End", point.date.addingTimeInterval(270)),
                              yStart: .value("Base", 0), yEnd: .value("Stress", point.value))
                    .foregroundStyle(Palette.stress(StressLevel(value: point.value)))
                    .cornerRadius(1.5)
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: 0...100)
        .chartXAxis { hourAxis(zone: zone) }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 40, 60, 80, 100]) { value in
                AxisGridLine().foregroundStyle(Palette.grid)
                AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)").font(.caption2).foregroundStyle(Palette.muted) } }
            }
        }
        .chartOverlay { proxy in
            ChartHoverLayer(proxy: proxy, showsPoint: false) { [points, zone] date in
                nearest(points, to: date.addingTimeInterval(-150), within: 300).map {
                    let level = StressLevel(value: $0.value)
                    return HoverReadout(date: $0.date.addingTimeInterval(150), value: $0.value, title: Format.time($0.date, zone),
                                        text: "\(Format.int($0.value)) · \(level.title)", tint: Palette.stress(level))
                }
            }
        }
        .accessibilityLabel("Stress readings for the day")
    }
}

// MARK: - Trends

struct DailyValue: Identifiable {
    let date: String
    let value: Double
    var low: Double?
    var id: String { date }
}

/// One measure across days, as bars or a range. Days are categories so cloud dates never shift time zones.
struct TrendChart: View {
    let values: [DailyValue]
    let tint: Color
    var unit = ""
    var goal: Double?
    var format: (Double) -> String = { Format.int($0) }
    var selectedDate: String?
    var domain: ClosedRange<Double>?
    @State private var hovered: String?

    var body: some View {
        // Label at most four days so narrow cards stay legible; hover names every day.
        let stride = max(1, Int((Double(values.count) / 4).rounded(.up)))
        let labels = Set(values.enumerated().filter { (values.count - 1 - $0.offset) % stride == 0 }.map(\.element.date))
        Chart {
            ForEach(values) { item in
                let emphasized = hovered.map { $0 == item.date } ?? (selectedDate == nil || selectedDate == item.date)
                if let low = item.low {
                    BarMark(x: .value("Day", item.date), yStart: .value("Low", low), yEnd: .value("High", item.value), width: values.count < 6 ? .fixed(18) : .ratio(0.45))
                        .foregroundStyle(tint.opacity(emphasized ? 1 : 0.4)).cornerRadius(4)
                } else if (domain?.lowerBound ?? 0) > 0 {
                    // A scale that doesn't start at zero can't carry bar lengths, so show positions instead.
                    LineMark(x: .value("Day", item.date), y: .value("Value", item.value))
                        .foregroundStyle(tint.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", item.date), y: .value("Value", item.value))
                        .foregroundStyle(tint.opacity(emphasized ? 1 : 0.5)).symbolSize(emphasized ? 90 : 55)
                        .annotation(position: .top, spacing: 4) {
                            if values.count <= 10 { Text(format(item.value)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                        }
                } else {
                    BarMark(x: .value("Day", item.date), y: .value("Value", item.value), width: values.count < 6 ? .fixed(34) : .ratio(0.62))
                        .foregroundStyle(tint.opacity(emphasized ? 1 : 0.4)).cornerRadius(4)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal)).foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(format(goal))").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
            }
            if let hovered, let item = values.first(where: { $0.date == hovered }) {
                RuleMark(x: .value("Day", item.date)).foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(title: Format.longDay(item.date),
                                value: (item.low.map { format($0) + "–" } ?? "") + format(item.value) + (unit.isEmpty ? "" : " " + unit), tint: tint)
                    }
            }
        }
        .chartYScale(domain: domain ?? 0...max(goal ?? 0, values.map(\.value).max() ?? 1) * 1.15)
        .chartXAxis {
            AxisMarks { value in
                if let date = value.as(String.self), labels.contains(date) {
                    AxisValueLabel {
                        Text(values.count <= 4 ? Format.weekday(date) : Format.shortDay(date)).font(.caption2).foregroundStyle(Palette.muted)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis { valueAxis() }
        .chartPlotStyle { $0.clipped() }
        .chartXSelection(value: $hovered)
    }
}
