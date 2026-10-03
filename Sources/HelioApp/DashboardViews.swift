import SwiftUI
import Charts
import HelioCore

struct OverviewView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(title: "Resting heart rate", value: integer(store.day?.restingHeartRate), unit: "bpm", symbol: "heart", color: .pink)
                MetricCard(title: "Sleep score", value: integer(store.day?.sleepScore), unit: "/ 100", symbol: "moon", color: .indigo)
                MetricCard(title: "Steps", value: integer(store.day?.steps), unit: "steps", symbol: "figure.walk", color: .mint)
                MetricCard(title: "Asleep", value: duration(store.day?.asleepMinutes), unit: "known stages", symbol: "bed.double", color: .indigo)
                MetricCard(title: "Distance", value: store.day?.distance.map { ($0 / 1000).formatted(.number.precision(.fractionLength(1))) } ?? "Not available", unit: "km", symbol: "map", color: .mint)
                MetricCard(title: "Calories", value: integer(store.day?.calories), unit: "kcal, cloud total", symbol: "flame", color: .orange)
            }
            HeartRatePanel(day: store.day)
            Panel(title: "Daily steps", subtitle: "One cloud summary per device and date. Missing days are not zero.") {
                let days = store.snapshot?.days.filter { $0.source == store.selectedSource && $0.steps != nil }.sorted { $0.date < $1.date } ?? []
                if days.isEmpty { NoData(text: "No step summaries were returned.") }
                else {
                    // Cloud day labels must not shift when the Mac is in a different time zone.
                    Chart(days) { day in
                        if let steps = day.steps {
                            BarMark(x: .value("Date", day.date), y: .value("Steps", steps)).foregroundStyle(.mint.gradient).cornerRadius(4)
                        }
                    }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
                        .frame(height: 180).accessibilityLabel("Daily steps for the selected device")
                }
            }
        }
    }
}

struct HeartRatePanel: View {
    let day: BandDay?
    var body: some View {
        Panel(title: "Heart rate", subtitle: "Minute-by-minute cloud readings. Gaps indicate missing or invalid samples. Device time zone.") {
            let points = day?.heartRatePoints ?? []
            if points.isEmpty { NoData(text: "No heart rate readings for this device and date.") }
            else {
                HStack(spacing: 24) {
                    SmallStat(title: "Average", value: integer(points.map(\.value).reduce(0, +) / Double(points.count)), unit: "bpm")
                    SmallStat(title: "Low", value: integer(points.map(\.value).min()), unit: "bpm")
                    SmallStat(title: "High", value: integer(points.map(\.value).max()), unit: "bpm")
                    Spacer()
                    Text("\(points.count.formatted()) samples").font(.caption).foregroundStyle(.secondary)
                }
                TimelineChart(points: points, color: .pink, range: nil, zone: day?.deviceTimeZone ?? .current).frame(height: 230)
            }
        }
    }
}

struct HeartView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            HeartRatePanel(day: store.day)
            Panel(title: "Stress timeline", subtitle: "Account-level cloud readings, 1–100. May include other devices. Not an HRV measurement.") {
                let points = store.snapshot?.stressPoints(on: store.selectedDate, timeZone: store.day?.deviceTimeZone ?? .current) ?? []
                if points.isEmpty { NoData(text: "No stress readings for this date. Check All cloud fields for endpoint status.") }
                else { TimelineChart(points: points, color: .orange, range: 0...100, zone: store.day?.deviceTimeZone ?? .current).frame(height: 230) }
            }
            Notice(title: "Where is HRV?", message: "The API reference does not identify a verified HRV endpoint. Helio does not convert stress into an HRV value or invent a readiness score. Any new fields returned by these endpoints remain visible in All cloud fields.", symbol: "info.circle", color: .mint)
        }
    }
}

struct SleepView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                MetricCard(title: "Asleep", value: duration(store.day?.asleepMinutes), unit: "known stages only", symbol: "bed.double", color: .indigo)
                MetricCard(title: "Sleep window", value: duration(store.day?.sleepWindowMinutes), unit: "includes awake time", symbol: "clock", color: .purple)
                MetricCard(title: "Sleep score", value: integer(store.day?.sleepScore), unit: "/ 100", symbol: "moon", color: .indigo)
            }
            Panel(title: "Sleep stages", subtitle: sleepSubtitle) {
                let stages = store.day?.sleepStages ?? []
                if stages.isEmpty { NoData(text: "No main sleep stages were returned. Nap and irregular sleep fields remain available in the decoded summary.") }
                else {
                    Chart(stages) { stage in
                        BarMark(xStart: .value("Start", stage.start), xEnd: .value("End", stage.end), y: .value("Stage", stage.title))
                            .foregroundStyle(by: .value("Stage", stage.title)).cornerRadius(3)
                    }
                    .chartForegroundStyleScale(["Awake": Color.orange, "REM": Color.mint, "Light": Color.indigo.opacity(0.8), "Deep": Color.purple, "Unknown": Color.gray])
                    .chartXAxis { timeAxis(zone: store.day?.deviceTimeZone ?? .current) }
                    .frame(height: 200)
                    HStack(spacing: 28) {
                        ForEach(["Deep", "Light", "REM", "Awake"], id: \.self) { name in
                            SmallStat(title: name, value: duration(stages.filter { $0.title == name }.reduce(0) { $0 + $1.minutes }), unit: "")
                        }
                    }.padding(.top, 12)
                }
            }
            Panel(title: "Decoded sleep summary", subtitle: "Nap fields, sleep versions, and other values exactly as Zepp returned them.") {
                JSONText(value: store.day?.summary["slp"] ?? .null)
            }
        }
    }
    private var sleepSubtitle: String {
        guard let day = store.day, let start = day.sleepStart, let end = day.sleepEnd else { return "The cloud record's date is not necessarily the date you woke up." }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: day.deviceTimeZone)
        return "\(start.formatted(style)) to \(end.formatted(style)). Device time zone."
    }
}

struct ActivityView: View {
    @Bindable var store: AppStore
    private var trainingItems: [JSONValue] {
        (store.snapshot?.payload(.exertion)?.raw["items"].array ?? []).sorted { ($0["timestamp"].number ?? 0) < ($1["timestamp"].number ?? 0) }
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                MetricCard(title: "Steps", value: integer(store.day?.steps), unit: "steps", symbol: "figure.walk", color: .mint)
                MetricCard(title: "Calories", value: integer(store.day?.calories), unit: "kcal, cloud total", symbol: "flame", color: .orange)
                MetricCard(title: "Distance", value: store.day?.distance.map { ($0 / 1000).formatted(.number.precision(.fractionLength(1))) } ?? "Not available", unit: "km", symbol: "map", color: .mint)
            }
            Panel(title: "Training load", subtitle: "Account-level records for the downloaded range. These are not filtered to the selected device or date.") {
                let latest = trainingItems.last?["value"] ?? .null
                HStack(spacing: 28) {
                    SmallStat(title: "Latest acute load", value: integer(latest["atl"].number), unit: "")
                    SmallStat(title: "Latest chronic load", value: integer(latest["ctl"].number), unit: "")
                    SmallStat(title: "Latest load balance", value: integer(latest["tsb"].number), unit: "")
                }
                if trainingItems.isEmpty { NoData(text: "No training-load records were returned.") }
                else {
                    Chart {
                        ForEach(Array(trainingItems.enumerated()), id: \.offset) { _, item in
                            if let ms = item["timestamp"].number {
                                ForEach(["atl", "ctl", "tsb"], id: \.self) { field in
                                    if let value = item["value"][field].number {
                                        LineMark(x: .value("Date", Date(timeIntervalSince1970: ms / 1000)), y: .value("Load", value))
                                            .foregroundStyle(by: .value("Metric", field.uppercased()))
                                    }
                                }
                            }
                        }
                    }.frame(height: 220)
                }
            }
            ForEach([CloudEndpoint.phn, .sportLoad, .vo2Max, .workouts]) { endpoint in
                Panel(title: endpoint.title, subtitle: "Account-level response for the downloaded range. Additional field mapping is pending verification.") {
                    if let payload = store.snapshot?.payload(endpoint) {
                        if let warning = payload.warning { Text(warning).foregroundStyle(.orange) }
                        if payload.raw["items"].array.isEmpty && payload.raw["data"].array.isEmpty {
                            Text("No recognized list records. The full response is shown below.").font(.caption).foregroundStyle(.secondary)
                        }
                        JSONText(value: payload.raw)
                    } else { NoData(text: "Not downloaded.") }
                }
            }
        }
    }
}

struct CloudFieldsView: View {
    @Bindable var store: AppStore
    @State private var endpoint: CloudEndpoint = .band
    @State private var decoded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Notice(title: "Private health data", message: "These responses can include account and device identifiers. Export only to a location you trust. Authentication tokens are not included. Missing fields are not a zero reading.", symbol: "lock", color: .mint)
            Picker("Endpoint", selection: $endpoint) {
                ForEach(CloudEndpoint.allCases) { Text($0.title).tag($0) }
            }.frame(width: 360)
            if let payload = store.snapshot?.payload(endpoint) {
                if let warning = payload.warning { Text(warning).foregroundStyle(.orange).textSelection(.enabled) }
                if endpoint == .band {
                    Toggle("Show decoded summary for selected device and date", isOn: $decoded)
                    if decoded {
                        Text("\(store.selectedDate) · \(store.selectedSource)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Panel(title: endpoint.title, subtitle: "Range \(store.snapshot?.startDate ?? "") to \(store.snapshot?.endDate ?? ""). Scroll and select text to inspect fields.") {
                    JSONText(value: endpoint == .band && decoded ? store.day?.summary ?? .null : payload.raw)
                }
            } else { NoData(text: "This endpoint has not been downloaded.") }
            Button("Export all downloaded data…") { store.export() }
        }
    }
}
