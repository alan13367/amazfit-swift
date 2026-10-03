import Foundation

public enum ZeppDecoder {
    public static func bandDays(from raw: JSONValue) throws -> [BandDay] {
        guard raw["code"].number == 1 else { throw ZeppError.api(CloudEndpoint.band.title) }
        guard case .array(let records) = raw["data"] else { throw ZeppError.malformed("band data") }
        var unique: [String: BandDay] = [:]
        for record in records {
            guard let date = record["date_time"].string, validDay(date) else { throw ZeppError.malformed("band date") }
            let summary: JSONValue
            switch record["summary"] {
            case .null: summary = .null
            case .object: summary = record["summary"]
            case .string(let encoded) where encoded.isEmpty: summary = .null
            case .string(let encoded):
                guard let data = Data(base64Encoded: encoded), let decoded = try? JSONValue.decode(data),
                      case .object = decoded else { throw ZeppError.malformed("base64 band summary") }
                summary = decoded
            default: throw ZeppError.malformed("band summary")
            }
            let heartRate: [Int]
            switch record["data_hr"] {
            case .null: heartRate = []
            case .string(let encoded):
                guard let data = Data(base64Encoded: encoded), data.count <= 1440 else { throw ZeppError.malformed("heart rate timeline") }
                heartRate = data.map(Int.init)
            default: throw ZeppError.malformed("heart rate timeline")
            }
            let source = record["device_id"].scalarDescription ?? record["source"].scalarDescription ?? "Unknown device"
            let day = BandDay(date: date, source: source, summary: summary, heartRate: heartRate, raw: record)
            if let existing = unique[day.id], (existing.summary["sync"].number ?? 0) > (summary["sync"].number ?? 0) { continue }
            unique[day.id] = day
        }
        return unique.values.sorted { ($0.date, $0.source) < ($1.date, $1.source) }
    }

    private static func validDay(_ string: String) -> Bool {
        guard string.utf8.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: string) else { return false }
        return formatter.string(from: date) == string
    }
}
