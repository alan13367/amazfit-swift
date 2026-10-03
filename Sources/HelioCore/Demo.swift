import Foundation

public extension CloudSnapshot {
    /// Two weeks of synthetic records shaped like real Helio responses. Never saved as account data.
    static func demo(now: Date = Date()) -> CloudSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = dayFormatter(.current)
        let today = calendar.startOfDay(for: now)
        let nowMinute = min(1439, Int(now.timeIntervalSince(today) / 60))
        var random = SeededRandom(seed: 7)
        var days: [BandDay] = []
        var stress: [JSONValue] = []
        var workouts: [JSONValue] = []
        var loads: [JSONValue] = []
        var dailyLoads: [Double] = []
        for offset in -13...0 {
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            let date = formatter.string(from: start)
            let lastMinute = offset == 0 ? nowMinute : 1439
            // Sleep from the previous evening into this morning. Stage minutes count from the previous midnight.
            let bedtime = 1380 + random.int(-40...50)
            let wake = 1440 + 400 + random.int(-30...60)
            let stages = sleepStages(from: bedtime, to: wake, random: &random)
            let sleepStart = start.addingTimeInterval(Double(bedtime - 1440) * 60)
            let sleepEnd = start.addingTimeInterval(Double(wake - 1440 + 1) * 60)
            let workout = offset % 2 == 0 ? (start: 1050 + random.int(-60...60), length: 35 + random.int(0...30),
                                              type: [1, 52, 8][(-offset / 2) % 3]) : nil
            var heart = [Int](repeating: 0, count: 1440)
            var activity = [UInt8](repeating: 0, count: 4320)
            var segments: [JSONValue] = []
            var walking: (start: Int, steps: Int)?
            let rest = 54 + random.double(-2...3)
            for minute in 0...lastMinute {
                let asleep = minute < wake - 1440
                let inWorkout = workout.map { (($0.start)..<($0.start + $0.length)).contains(minute) } ?? false
                var bpm = asleep ? rest + 4 * sin(Double(minute) / 70) : 72 + 9 * sin(Double(minute) / 47) + 4 * cos(Double(minute) / 13)
                var steps = 0
                var kind: UInt8 = asleep ? 120 : 80
                if inWorkout, let workout {
                    let progress = Double(minute - workout.start) / Double(workout.length)
                    bpm = (workout.type == 52 ? 105 : 128) + 30 * sin(progress * .pi) + random.double(-6...6)
                    if workout.type != 52 { steps = 150 + random.int(-10...12); kind = 64 }
                } else if !asleep, random.double(0...1) < 0.16 {
                    steps = random.int(20...115)
                    bpm += Double(steps) / 6
                    kind = 64
                }
                if steps >= 20 && walking == nil { walking = (minute, 0) }
                if let current = walking {
                    if steps < 20 || minute == lastMinute {
                        if minute - current.start >= 3 {
                            let run = workout?.type == 1 && inWorkout
                            segments.append(.object(["start": .number(Double(current.start)), "stop": .number(Double(minute - 1)),
                                                      "mode": .number(run ? 4 : current.steps / (minute - current.start) > 100 ? 3 : 1),
                                                      "step": .number(Double(current.steps)), "dis": .number(Double(current.steps) * 0.74),
                                                      "cal": .number(Double(current.steps) / 22)]))
                        }
                        walking = nil
                    } else { walking!.steps += steps }
                }
                // A short gap while the strap is charging.
                let charging = (760..<792).contains(minute)
                heart[minute] = charging ? 254 : Int(bpm + random.double(-2...2))
                activity[minute * 3] = charging ? 126 : kind
                activity[minute * 3 + 1] = UInt8(min(255, steps))
                activity[minute * 3 + 2] = UInt8(min(255, steps))
            }
            for minute in (lastMinute + 1)..<1440 { heart[minute] = 254; activity[minute * 3] = 126 }
            let totalSteps = stride(from: 2, to: 4320, by: 3).reduce(0) { $0 + Int(activity[$1]) }
            let peak = heart.enumerated().filter { (1...253).contains($0.element) }.max { $0.element < $1.element }
            let minutes = { (mode: Double) in stages.filter { $0.mode == mode }.reduce(0) { $0 + $1.stop - $1.start + 1 } }
            let summary: JSONValue = .object([
                "v": .number(6), "goal": .number(8000), "sn": .string("DEMO-0000"),
                "tz": .string(String(TimeZone.current.secondsFromGMT(for: start))),
                "hr": .object(["maxHr": .object(["hr": .number(Double(peak?.element ?? 0)),
                                                  "ts": .number(start.timeIntervalSince1970 + Double(peak?.offset ?? 0) * 60)])]),
                "stp": .object(["ttl": .number(Double(totalSteps)), "dis": .number(Double(totalSteps) * 0.74),
                                 "cal": .number(Double(totalSteps) / 22 + 1450), "stage": .array(segments)]),
                "slp": .object(["st": .number(sleepStart.timeIntervalSince1970), "ed": .number(sleepEnd.timeIntervalSince1970),
                                 "rhr": .number(rest.rounded()), "ss": .number(Double(72 + random.int(0...20))),
                                 "dp": .number(minutes(5)), "lt": .number(minutes(4)), "dt": .number(minutes(8)), "wk": .number(minutes(7)),
                                 "wc": .number(Double(stages.filter { $0.mode == 7 }.count)),
                                 "stage": .array(stages.map { .object(["start": .number($0.start), "stop": .number($0.stop), "mode": .number($0.mode)]) })])
            ])
            let raw: JSONValue = .object(["date_time": .string(date), "source": .number(10289411), "summary": summary,
                                          "data": .string(Data(activity).base64EncodedString())])
            days.append(BandDay(date: date, source: "DEMO-0000", summary: summary, heartRate: heart, raw: raw))

            let readings: [(time: Double, value: Int)] = stride(from: 0, to: lastMinute, by: 5).compactMap { minute in
                guard !(760..<792).contains(minute) else { return nil }
                let asleep = minute < wake - 1440
                let base = asleep ? 18.0 : 42 + 18 * sin(Double(minute) / 110)
                return (start.addingTimeInterval(Double(minute) * 60).timeIntervalSince1970 * 1000,
                        max(1, min(100, Int(base + random.double(-9...14)))))
            }
            if !readings.isEmpty {
                let values = readings.map(\.value)
                let share = { (range: ClosedRange<Int>) in String(100 * values.filter { range.contains($0) }.count / values.count) }
                let encoded = String(decoding: try! JSONEncoder().encode(readings.map { ["time": $0.time, "value": Double($0.value)] }), as: UTF8.self)
                stress.append(.object(["timestamp": .number(start.timeIntervalSince1970 * 1000 + 1), "data": .string(encoded),
                                       "avgStress": .string(String(values.reduce(0, +) / values.count)),
                                       "minStress": .string(String(values.min()!)), "maxStress": .string(String(values.max()!)),
                                       "relaxProportion": .string(share(1...39)), "normalProportion": .string(share(40...59)),
                                       "mediumProportion": .string(share(60...79)), "highProportion": .string(share(80...100))]))
            }

            var dayLoad = 0.0
            if let workout, workout.start + workout.length <= lastMinute {
                let samples = heart[workout.start..<(workout.start + workout.length)].map(Double.init)
                let bounds = [97.0, 117, 136, 156, 175, 195]
                let zones = bounds.enumerated().map { index, upper in
                    "\(samples.filter { $0 < upper && $0 >= (index == 0 ? 0 : bounds[index - 1]) }.count * 60),\(Int(upper))"
                }.joined(separator: ";")
                let begin = start.timeIntervalSince1970 + Double(workout.start) * 60
                let stepCount = activity[(workout.start * 3)..<((workout.start + workout.length) * 3)].enumerated()
                    .filter { $0.offset % 3 == 2 }.reduce(0) { $0 + Int($1.element) }
                let distance = workout.type == 52 ? 0 : Double(stepCount) * (workout.type == 1 ? 1.05 : 0.74)
                dayLoad = Double(workout.length) * (workout.type == 1 ? 1.4 : 0.7)
                workouts.append(.object([
                    "trackid": .string(String(Int(begin))), "end_time": .string(String(Int(begin) + workout.length * 60)),
                    "run_time": .string(String(workout.length * 60)), "type": .number(Double(workout.type)),
                    "dis": .string(String(distance)), "calorie": .string(String(Double(workout.length) * 8.5)),
                    "avg_heart_rate": .string(String(Int(samples.reduce(0, +) / Double(samples.count)))),
                    "max_heart_rate": .number(samples.max()!), "min_heart_rate": .number(samples.min()!),
                    "heart_range": .string(zones), "te": .number(Double(18 + random.int(0...16))),
                    "anaerobic_te": .number(Double(workout.type == 1 ? 12 : 3)), "exercise_load": .number(dayLoad.rounded()),
                    "rpe": .number(Double(4 + random.int(0...3))), "sn": .string("DEMO-0000"),
                    "avg_pace": .string(distance > 0 ? String(Double(workout.length * 60) / distance) : "0"),
                    "avg_frequency": .string(workout.type == 52 ? "0" : "150"), "avg_stride_length": .number(workout.type == 1 ? 105 : workout.type == 8 ? 74 : -1),
                    "total_step": .number(Double(stepCount)), "syncedTimezone": .string(TimeZone.current.identifier),
                    "strength_training_group": .string(workout.type == 52
                        ? String(decoding: try! JSONEncoder().encode((0..<12).map { _ in ["count": 8 + random.int(0...6), "actionType": 0] }), as: UTF8.self) : "")
                ]))
            }
            dailyLoads.append(dayLoad)
            loads.append(.object(["dayId": .string(date), "wtlSum": .number(dailyLoads.suffix(7).reduce(0, +).rounded()),
                                  "currnetDayTrainLoad": .number(dayLoad.rounded()), "wtlSumOptimalMin": .number(54),
                                  "wtlSumOptimalMax": .number(182), "wtlSumOverreaching": .number(219)]))
        }
        let payloads = [EndpointPayload(endpoint: .band, raw: .object(["code": .number(1), "data": .array(days.map(\.raw))])),
                        EndpointPayload(endpoint: .stress, raw: .object(["items": .array(stress)])),
                        EndpointPayload(endpoint: .exertion, raw: .object(["items": .array([])])),
                        EndpointPayload(endpoint: .phn, raw: .object(["items": .array([])])),
                        EndpointPayload(endpoint: .sportLoad, raw: .object(["items": .array(loads.reversed())])),
                        EndpointPayload(endpoint: .vo2Max, raw: .object(["items": .array([])])),
                        EndpointPayload(endpoint: .workouts, raw: .object(["code": .number(1), "data": .object(["next": .number(-1), "summary": .array(workouts.reversed())])]))]
        return CloudSnapshot(fetchedAt: now, startDate: days.first!.date, endDate: days.last!.date,
                             region: .us, days: days, payloads: payloads, warnings: [])
    }
}

private func sleepStages(from bedtime: Int, to wake: Int, random: inout SeededRandom) -> [(start: Double, stop: Double, mode: Double)] {
    var stages: [(start: Double, stop: Double, mode: Double)] = []
    var minute = bedtime
    var cycle = 0
    while minute < wake {
        // Deep sleep is concentrated early in the night and REM grows toward morning.
        let plan: [(Double, Int)] = [(4, 18 + random.int(0...12)), (5, max(6, 42 - cycle * 10 + random.int(-5...5))),
                                     (4, 22 + random.int(0...15)), (8, 10 + cycle * 7 + random.int(0...6))]
            + (random.double(0...1) < 0.45 ? [(7, 1 + random.int(0...4))] : [])
        for (mode, length) in plan where minute < wake {
            let stop = min(wake, minute + length - 1)
            stages.append((Double(minute), Double(stop), mode))
            minute = stop + 1
        }
        cycle += 1
    }
    return stages
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
}
