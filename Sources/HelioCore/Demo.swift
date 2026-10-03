import Foundation

public extension CloudSnapshot {
    static func demo(now: Date = Date()) -> CloudSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        var days: [BandDay] = []
        var stress: [JSONValue] = []
        for offset in -6...0 {
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            let date = formatter.string(from: start)
            let heart = (0..<1440).map { minute -> Int in
                if minute > 1350 || (minute > 830 && minute < 880) { return 0 }
                let base = minute < 420 ? 54.0 : 72.0
                let workout = (1020...1080).contains(minute) ? 55.0 : 0.0
                return Int(base + sin(Double(minute) / 27) * 6 + cos(Double(minute) / 11) * 3 + workout)
            }
            let summary: JSONValue = .object([
                "tz": .string(String(TimeZone.current.secondsFromGMT(for: start))),
                "sn": .string("DEMO-STRAP"),
                "stp": .object(["ttl": .number(Double(7200 + (offset + 6) * 430)),
                                 "dis": .number(Double(5000 + (offset + 6) * 240)), "cal": .number(1850)]),
                "slp": .object(["st": .number(start.addingTimeInterval(20 * 60).timeIntervalSince1970),
                                 "ed": .number(start.addingTimeInterval(465 * 60).timeIntervalSince1970),
                                 "rhr": .number(54), "ss": .number(Double(81 + offset)),
                                 "dp": .number(96), "lt": .number(239),
                                 "stage": .array([
                                    stage(20, 100, 4), stage(100, 152, 5), stage(152, 230, 4),
                                    stage(230, 271, 8), stage(271, 282, 7), stage(282, 326, 5),
                                    stage(326, 407, 4), stage(407, 465, 8)
                                 ])])
            ])
            days.append(BandDay(date: date, source: "Demo Helio Strap", summary: summary,
                                heartRate: heart, raw: .object(["date_time": .string(date), "summary": summary])))
            let readings: [JSONValue] = stride(from: 0, to: 1440, by: 5).map { minute in
                .object(["time": .number(start.addingTimeInterval(Double(minute) * 60).timeIntervalSince1970 * 1000),
                         "value": .number(Double(Int(30 + sin(Double(minute) / 90) * 15)))])
            }
            stress.append(.object(["timestamp": .number(start.timeIntervalSince1970 * 1000),
                                   "avgStress": .string("30"), "data": .array(readings)]))
        }
        let payloads = [EndpointPayload(endpoint: .band, raw: .object(["code": .number(1), "data": .array(days.map(\.raw))])),
                        EndpointPayload(endpoint: .stress, raw: .object(["items": .array(stress)]))] +
            [CloudEndpoint.exertion, .phn, .sportLoad, .vo2Max, .workouts].map {
                EndpointPayload(endpoint: $0, raw: .object(["items": .array([])]))
            }
        return CloudSnapshot(fetchedAt: now, startDate: days.first!.date, endDate: days.last!.date,
                             region: .us, days: days, payloads: payloads, warnings: [])
    }
}

private func stage(_ start: Double, _ stop: Double, _ mode: Double) -> JSONValue {
    .object(["start": .number(start), "stop": .number(stop), "mode": .number(mode)])
}
