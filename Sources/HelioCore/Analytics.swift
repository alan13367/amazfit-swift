import Foundation

public struct MetricPoint: Identifiable, Sendable {
    public let date: Date
    public let value: Double
    public let segment: Int
    public var id: Date { date }
    public init(date: Date, value: Double, segment: Int = 0) {
        self.date = date
        self.value = value
        self.segment = segment
    }
}

public extension BandDay {
    var midnight: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = deviceTimeZone
        return formatter.date(from: date)
    }

    var deviceTimeZone: TimeZone {
        if let seconds = summary["tz"].number, abs(seconds) <= 86400,
           let zone = TimeZone(secondsFromGMT: Int(seconds)) {
            return zone
        }
        return .current
    }

    var heartRatePoints: [MetricPoint] {
        guard let start = midnight else { return [] }
        var segment = 0
        var lastMinute: Int?
        return heartRate.prefix(1440).enumerated().compactMap { minute, value in
            guard (1...253).contains(value) else { return nil }
            if let lastMinute, minute - lastMinute > 1 { segment += 1 }
            lastMinute = minute
            return MetricPoint(date: start.addingTimeInterval(Double(minute) * 60), value: Double(value), segment: segment)
        }
    }

    var steps: Double? { summary["stp"]["ttl"].number }
    var calories: Double? { summary["stp"]["cal"].number }
    var distance: Double? { summary["stp"]["dis"].number }
    var restingHeartRate: Double? { positive(summary["slp"]["rhr"].number) }
    var sleepScore: Double? { positive(summary["slp"]["ss"].number) }
    var sleepStart: Date? { epochDate(summary["slp"]["st"].number) }
    var sleepEnd: Date? { epochDate(summary["slp"]["ed"].number) }
    var sleepWindowMinutes: Double? {
        guard let start = sleepStart, let end = sleepEnd, end > start else { return nil }
        return end.timeIntervalSince(start) / 60
    }
    // Only known asleep stages count. The interval between start and end also contains awake time.
    var asleepMinutes: Double? {
        let stages = sleepStages.filter { [4, 5, 7, 8].contains($0.mode) }
        guard !stages.isEmpty else { return nil }
        let asleep = stages.filter { [4, 5, 8].contains($0.mode) }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var interval: (start: Date, end: Date)?
        for stage in asleep {
            if let previous = interval {
                if stage.start <= previous.end { interval = (previous.start, max(previous.end, stage.end)) }
                else { total += previous.end.timeIntervalSince(previous.start); interval = (stage.start, stage.end) }
            } else { interval = (stage.start, stage.end) }
        }
        if let interval { total += interval.end.timeIntervalSince(interval.start) }
        return total / 60
    }
    var sleepStages: [SleepStage] {
        guard let start = midnight else { return [] }
        return summary["slp"]["stage"].array.enumerated().compactMap { index, item in
            guard let lower = item["start"].number, let upper = item["stop"].number,
                  let mode = item["mode"].number, (0...255).contains(mode), mode.rounded() == mode,
                  lower >= 0, upper > lower, upper <= 4320 else { return nil }
            return SleepStage(id: index, start: start.addingTimeInterval(lower * 60),
                              end: start.addingTimeInterval(upper * 60), mode: Int(mode))
        }
    }
}

public struct SleepStage: Identifiable, Sendable {
    public let id: Int
    public let start: Date
    public let end: Date
    public let mode: Int
    public var minutes: Double { end.timeIntervalSince(start) / 60 }
    public var title: String {
        switch mode { case 4: "Light"; case 5: "Deep"; case 7: "Awake"; case 8: "REM"; default: "Unknown" }
    }
}

public extension CloudSnapshot {
    var dates: [String] { Array(Set(days.map(\.date))).sorted() }
    var sources: [String] { Array(Set(days.map(\.source))).sorted() }
    func day(on date: String, source: String?) -> BandDay? {
        days.first { $0.date == date && (source == nil || $0.source == source) }
    }
    func payload(_ endpoint: CloudEndpoint) -> EndpointPayload? { payloads.first { $0.endpoint == endpoint } }
    func stressPoints(on date: String, timeZone: TimeZone = .current) -> [MetricPoint] {
        let items = payload(.stress)?.raw["items"].array ?? []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var values: [Date: Double] = [:]
        for item in items {
            let data = item["data"]
            let readings: [JSONValue]
            if let text = data.string, let bytes = text.data(using: .utf8), let decoded = try? JSONValue.decode(bytes) {
                readings = decoded.array
            } else { readings = data.array }
            for reading in readings {
                guard let ms = reading["time"].number, ms > 0,
                      let value = reading["value"].number, (1...100).contains(value) else { continue }
                let timestamp = Date(timeIntervalSince1970: ms / 1000)
                if formatter.string(from: timestamp) == date { values[timestamp] = value }
            }
        }
        var segment = 0
        var previous: Date?
        return values.keys.sorted().map { timestamp in
            if let previous, timestamp.timeIntervalSince(previous) > 600 { segment += 1 }
            previous = timestamp
            return MetricPoint(date: timestamp, value: values[timestamp]!, segment: segment)
        }
    }
}

private func positive(_ value: Double?) -> Double? {
    guard let value, value > 0 else { return nil }
    return value
}
private func epochDate(_ value: Double?) -> Date? {
    guard let value, value > 0, value < 32_503_680_000 else { return nil }
    return Date(timeIntervalSince1970: value)
}
