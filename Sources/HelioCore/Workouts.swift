import Foundation

/// A workout from the experimental `/v1/sport/run/history.json` response.
/// Zepp uses negative sentinels (-1, -274, -20000) for fields a sport does not record; those decode as nil.
public struct Workout: Identifiable, Sendable {
    public let id: String
    public let type: Int
    public let start: Date
    public let end: Date
    public let activeSeconds: Double?
    public let distance: Double?
    public let calories: Double?
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?
    public let minHeartRate: Double?
    public let zones: [HeartZoneTime]
    /// Zepp shows training effect on a 0.0–5.0 scale; the response stores tenths.
    public let aerobicEffect: Double?
    public let anaerobicEffect: Double?
    public let exerciseLoad: Double?
    public let perceivedEffort: Double?
    /// Seconds per meter.
    public let averagePace: Double?
    public let cadence: Double?
    public let strideLength: Double?
    public let steps: Double?
    public let sets: [Int]
    public let serial: String?
    public let timeZone: TimeZone?

    public var duration: TimeInterval { activeSeconds ?? end.timeIntervalSince(start) }
    public var info: SportInfo { SportInfo(type: type, hasSets: !sets.isEmpty, hasDistance: (distance ?? 0) > 0) }

    init?(_ item: JSONValue) {
        guard let startSeconds = item["trackid"].number, let begin = epochDate(startSeconds) else { return nil }
        let endDate = epochDate(item["end_time"].number) ?? begin.addingTimeInterval(item["run_time"].number ?? 0)
        guard endDate >= begin, endDate.timeIntervalSince(begin) < 86400 * 2 else { return nil }
        id = item["trackid"].scalarDescription ?? String(Int(startSeconds))
        type = Int(item["type"].number ?? -1)
        start = begin
        end = endDate
        activeSeconds = positive(item["run_time"].number)
        distance = positive(item["dis"].number)
        calories = positive(item["calorie"].number)
        averageHeartRate = heart(item["avg_heart_rate"].number)
        maxHeartRate = heart(item["max_heart_rate"].number)
        minHeartRate = heart(item["min_heart_rate"].number)
        zones = HeartZoneTime.parse(item["heart_range"].string)
        aerobicEffect = positive(item["te"].number).map { $0 / 10 }
        anaerobicEffect = positive(item["anaerobic_te"].number).map { $0 / 10 }
        exerciseLoad = positive(item["exercise_load"].number)
        perceivedEffort = positive(item["rpe"].number)
        averagePace = positive(item["avg_pace"].number)
        cadence = positive(item["avg_frequency"].number)
        strideLength = positive(item["avg_stride_length"].number)
        steps = positive(item["total_step"].number)
        if let text = item["strength_training_group"].string, let data = text.data(using: .utf8),
           let groups = try? JSONValue.decode(data) {
            sets = groups.array.compactMap { $0["count"].number.flatMap { $0 > 0 && $0 < 10_000 ? Int($0) : nil } }
        } else { sets = [] }
        serial = item["sn"].string.flatMap { $0.isEmpty ? nil : $0 }
        timeZone = item["syncedTimezone"].string.flatMap(TimeZone.init(identifier:))
    }
}

public struct HeartZoneTime: Identifiable, Sendable {
    public let index: Int
    public let seconds: Double
    public let lower: Double?
    public let upper: Double
    public var id: Int { index }
    public var title: String { HeartZoneTime.titles[min(index, HeartZoneTime.titles.count - 1)] }
    public init(index: Int, seconds: Double, lower: Double?, upper: Double) {
        self.index = index; self.seconds = seconds; self.lower = lower; self.upper = upper
    }
    public static let titles = ["Light", "Warm-up", "Fat burn", "Aerobic", "Anaerobic", "VO₂ max"]

    /// Parses "seconds,upperBPM;…". Each bucket covers the range from the previous bound up to its own.
    /// In real records the bounds sit at 50, 60, 70, 80, 90, and 100% of the configured maximum heart rate,
    /// and the time-weighted bucket midpoints reproduce the workout's reported average.
    static func parse(_ text: String?) -> [HeartZoneTime] {
        guard let text else { return [] }
        var previous: Double?
        var result: [HeartZoneTime] = []
        for (index, part) in text.split(separator: ";").enumerated() {
            let fields = part.split(separator: ",")
            guard fields.count == 2, let seconds = Double(fields[0]), let upper = Double(fields[1]),
                  seconds >= 0, (30...260).contains(upper), upper > (previous ?? 0) else { return [] }
            result.append(HeartZoneTime(index: index, seconds: seconds, lower: previous, upper: upper))
            previous = upper
        }
        return result
    }
}

public struct SportInfo: Sendable {
    public let title: String
    public let symbol: String
    init(type: Int, hasSets: Bool, hasDistance: Bool) {
        switch type {
        case 1: (title, symbol) = ("Outdoor run", "figure.run")
        case 6: (title, symbol) = ("Walk", "figure.walk")
        case 7: (title, symbol) = ("Trail run", "figure.hiking")
        case 8: (title, symbol) = ("Treadmill", "figure.run.treadmill")
        case 9: (title, symbol) = ("Outdoor cycling", "figure.outdoor.cycle")
        case 10: (title, symbol) = ("Indoor cycling", "figure.indoor.cycle")
        case 12: (title, symbol) = ("Elliptical", "figure.elliptical")
        case 14: (title, symbol) = ("Pool swim", "figure.pool.swim")
        case 15: (title, symbol) = ("Open water swim", "figure.open.water.swim")
        case 16: (title, symbol) = ("Free training", "figure.mixed.cardio")
        case 21: (title, symbol) = ("Jump rope", "figure.jumprope")
        case 52: (title, symbol) = ("Strength training", "figure.strengthtraining.traditional")
        case 60: (title, symbol) = ("Yoga", "figure.yoga")
        default:
            if hasSets { (title, symbol) = ("Strength training", "figure.strengthtraining.traditional") }
            else if hasDistance { (title, symbol) = ("Workout", "figure.run") }
            else { (title, symbol) = ("Workout", "figure.mixed.cardio") }
        }
    }
}

public extension CloudSnapshot {
    var workouts: [Workout] {
        let summary = payload(.workouts)?.raw["data"]["summary"].array ?? []
        var unique: [String: Workout] = [:]
        for item in summary { if let workout = Workout(item) { unique[workout.id] = workout } }
        return unique.values.sorted { $0.start > $1.start }
    }

    /// Zone bounds from the most recent workout that reported them, for coloring daily heart rate.
    var heartZoneBounds: [Double]? {
        guard let zones = workouts.first(where: { $0.zones.count >= 3 })?.zones else { return nil }
        return zones.map(\.upper)
    }
}

private func heart(_ value: Double?) -> Double? {
    guard let value, (25...254).contains(value) else { return nil }
    return value
}
