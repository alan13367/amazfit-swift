import Foundation
import XCTest
@testable import HelioCore

final class CoreTests: XCTestCase {
    func testCredentialsAreTrimmedAndValidated() throws {
        let credentials = try ZeppCredentials(userID: " 1234\n", token: " session-token\n", region: .europe)
        XCTAssertEqual(credentials.userID, "1234")
        XCTAssertEqual(credentials.token, "session-token")
        for id in ["", "a12", "12/3", "１２３"] {
            XCTAssertThrowsError(try ZeppCredentials(userID: id, token: "secret", region: .us))
        }
        for token in ["", "a b", "secret\r\nInjected: yes", "é", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try ZeppCredentials(userID: "123", token: token, region: .us))
        }
        let invalid = Data(#"{"userID":"oops","token":"secret","region":"us"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ZeppCredentials.self, from: invalid))
    }

    func testJSONRoundTripAndNumericStrings() throws {
        let bytes = Data(#"{"number":3.25,"string":"42","boolean":true,"null":null,"array":[1,"x"]}"#.utf8)
        let value = try JSONValue.decode(bytes)
        XCTAssertEqual(value["number"].number, 3.25)
        XCTAssertEqual(value["string"].number, 42)
        XCTAssertEqual(value["boolean"], .bool(true))
        XCTAssertNil(value["boolean"].number)
        XCTAssertEqual(value["absent"], .null)
        XCTAssertEqual(value["array"].array.count, 2)
        XCTAssertNil(JSONValue.string("nan").number)
        XCTAssertEqual(try JSONValue.decode(JSONEncoder().encode(value)), value)
    }

    func testBandSummaryAndHeartRateKeepMinuteIndexes() throws {
        let summary: JSONValue = .object(["tz": .string("0"), "stp": .object(["ttl": .number(600)]),
                                          "slp": .object(["rhr": .number(55)])])
        let raw = try band(summary: summary, heart: [0, 60, 254, 255, 61, 62])
        let days = try ZeppDecoder.bandDays(from: raw)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].source, "10289411")
        XCTAssertEqual(days[0].steps, 600)
        XCTAssertEqual(days[0].restingHeartRate, 55)
        XCTAssertEqual(days[0].heartRate, [0, 60, 254, 255, 61, 62])
        let points = days[0].heartRatePoints
        XCTAssertEqual(points.map(\.value), [60, 61, 62])
        XCTAssertEqual(points.map(\.segment), [0, 1, 1])
        XCTAssertEqual(points[1].date.timeIntervalSince(days[0].midnight!), 240)
    }

    func testMissingMetricsAreNotZero() throws {
        let day = try XCTUnwrap(ZeppDecoder.bandDays(from: band(summary: .object([:]), heart: [])).first)
        XCTAssertNil(day.steps)
        XCTAssertNil(day.sleepScore)
        XCTAssertNil(day.asleepMinutes)
        XCTAssertNil(day.sleepWindowMinutes)
        XCTAssertTrue(day.heartRatePoints.isEmpty)
        let zero = BandDay(date: day.date, source: "test", summary: .object(["stp": .object(["ttl": .number(0)])]), heartRate: [], raw: .null)
        XCTAssertEqual(zero.steps, 0)
    }

    func testMalformedBandDataIsRejected() throws {
        XCTAssertThrowsError(try ZeppDecoder.bandDays(from: .object(["code": .number(-1), "data": .array([])])))
        XCTAssertThrowsError(try ZeppDecoder.bandDays(from: .object(["code": .number(1)])))
        for record: JSONValue in [
            .object(["date_time": .string("2026-02-30")]),
            .object(["date_time": .string("2026-2-03")]),
            .object(["date_time": .string("2026-02-03"), "summary": .string("invalid-base64")]),
            .object(["date_time": .string("2026-02-03"), "data_hr": .string(Data(repeating: 60, count: 1441).base64EncodedString())])
        ] {
            XCTAssertThrowsError(try ZeppDecoder.bandDays(from: .object(["code": .number(1), "data": .array([record])])))
        }
    }

    func testDuplicateDailyRecordsUseMostRecentSync() throws {
        let older = try band(summary: .object(["sync": .number(1), "stp": .object(["ttl": .number(50)])]), heart: [])
        let newer = try band(summary: .object(["sync": .number(2), "stp": .object(["ttl": .number(100)])]), heart: [])
        let combined: JSONValue = .object(["code": .number(1), "data": .array(newer["data"].array + older["data"].array)])
        let days = try ZeppDecoder.bandDays(from: combined)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].steps, 100)
    }

    func testSleepStagesCountFromPreviousMidnightWithInclusiveStops() throws {
        // Shaped like a real Helio record: the record date is the morning the night ended,
        // stage minutes count from the midnight before it, and stop minutes are inclusive.
        let midnight = 1_770_098_400.0 // 2026-02-03 00:00 at UTC-6
        let summary: JSONValue = .object(["tz": .string("-21600"), "slp": .object([
            "st": .number(midnight + 8 * 60), "ed": .number(midnight + 91 * 60), "wc": .number(1),
            "stage": .array([stage(1448, 1455, 4), stage(1456, 1456, 7), stage(1457, 1500, 5), stage(1501, 1530, 8)])
        ])])
        let day = try XCTUnwrap(ZeppDecoder.bandDays(from: band(summary: summary, heart: [])).first)
        XCTAssertEqual(day.deviceTimeZone.secondsFromGMT(), -21600)
        XCTAssertEqual(day.sleepStages.count, 4)
        XCTAssertEqual(day.sleepStages.first?.start, day.sleepStart)
        XCTAssertEqual(day.sleepStages[1].minutes, 1)
        XCTAssertEqual(day.asleepMinutes, 82)
        XCTAssertEqual(day.minutes(in: .deep), 44)
        XCTAssertEqual(day.minutes(in: .rem), 30)
        XCTAssertEqual(day.wakeCount, 1)
        let formatter = DateFormatter()
        formatter.timeZone = day.deviceTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(formatter.string(from: day.sleepStages.first!.start), "2026-02-03 00:08")
        XCTAssertEqual(formatter.string(from: day.sleepStages.last!.end), "2026-02-03 01:31")
    }

    func testSleepStageAnchorFollowsReportedStart() {
        // Older or synthetic records whose stage minutes count from the record's own midnight.
        let midnight = 1_770_076_800.0 // 2026-02-03 UTC
        let day = BandDay(date: "2026-02-03", source: "test", summary: .object(["tz": .string("0"), "slp": .object([
            "st": .number(midnight + 20 * 60), "stage": .array([stage(20, 99, 4), stage(100, 151, 5)])
        ])]), heartRate: [], raw: .null)
        XCTAssertEqual(day.sleepStages.first?.start.timeIntervalSince1970, midnight + 20 * 60)
        XCTAssertEqual(day.asleepMinutes, 132)
    }

    func testOverlappingSleepIsNotDoubleCountedAndInvalidModeIsIgnored() {
        let day = BandDay(date: "2026-02-03", source: "test", summary: .object(["tz": .string("0"), "slp": .object([
            "stage": .array([stage(0, 60, 4), stage(30, 90, 5), stage(90, 100, 7), stage(100, 110, 1e100)])
        ])]), heartRate: [], raw: .null)
        XCTAssertEqual(day.asleepMinutes, 91)
        XCTAssertEqual(day.sleepStages.count, 3)
        let unknown = BandDay(date: day.date, source: "test", summary: .object(["slp": .object(["stage": .array([stage(0, 60, 99)])])]), heartRate: [], raw: .null)
        XCTAssertNil(unknown.asleepMinutes)
    }

    func testMinuteActivityBytesGiveHourlySteps() {
        var bytes = [UInt8](repeating: 0, count: 4320)
        bytes[0] = 126
        bytes[60 * 3 + 2] = 40   // 01:00
        bytes[61 * 3 + 2] = 35   // 01:01
        bytes[1439 * 3 + 2] = 9  // 23:59
        let day = BandDay(date: "2026-02-03", source: "test", summary: .object(["stp": .object(["ttl": .number(84)])]), heartRate: [],
                          raw: .object(["data": .string(Data(bytes).base64EncodedString())]))
        XCTAssertEqual(day.activityMinutes.count, 1440)
        XCTAssertEqual(day.activityMinutes[0].kind, 126)
        XCTAssertEqual(day.hourlySteps?[1], 75)
        XCTAssertEqual(day.hourlySteps?[23], 9)
        XCTAssertEqual(day.hourlySteps?.reduce(0, +), 84)
        let truncated = BandDay(date: day.date, source: "test", summary: .null, heartRate: [],
                                raw: .object(["data": .string(Data([1, 2]).base64EncodedString())]))
        XCTAssertNil(truncated.hourlySteps)
    }

    func testSummaryExtrasAndActivitySegments() {
        let day = BandDay(date: "2026-02-03", source: "24458523001421", summary: .object([
            "tz": .string("0"), "goal": .number(8000), "hr": .object(["maxHr": .object(["hr": .number(166), "ts": .number(1_770_140_000)])]),
            "stp": .object(["stage": .array([.object(["start": .number(1131), "stop": .number(1138), "mode": .number(3), "step": .number(734)]),
                                             .object(["start": .number(973), "stop": .number(978), "mode": .number(1)])])])
        ]), heartRate: [], raw: .object(["source": .number(10289411)]))
        XCTAssertEqual(day.stepGoal, 8000)
        XCTAssertEqual(day.maxHeartRate?.bpm, 166)
        XCTAssertEqual(day.activitySegments.map(\.title), ["Walk", "Brisk walk"])
        XCTAssertEqual(day.activeMinutes, 14)
        XCTAssertEqual(day.deviceName, "Helio Strap")
        let empty = BandDay(date: day.date, source: "24458523001421", summary: .object(["hr": .object(["maxHr": .object(["hr": .number(0)])])]),
                            heartRate: [], raw: .null)
        XCTAssertNil(empty.maxHeartRate)
        XCTAssertNil(empty.activeMinutes)
        XCTAssertEqual(empty.deviceName, "Device ··1421")
    }

    func testStressNestedJSONStringAndDateFilter() throws {
        let ms = 1_770_076_800_000.0 // 2026-02-03 UTC
        let text = #"[{"time":1770076800000,"value":42},{"time":1770077100000,"value":0},{"time":1770163200000,"value":70}]"#
        let snapshot = CloudSnapshot(fetchedAt: Date(), startDate: "2026-02-03", endDate: "2026-02-04", region: .us, days: [],
            payloads: [EndpointPayload(endpoint: .stress, raw: .object(["items": .array([.object(["data": .string(text)])])]))], warnings: [])
        let points = snapshot.stressPoints(on: "2026-02-03", timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value, 42)
        XCTAssertEqual(points.first?.date.timeIntervalSince1970, ms / 1000)
    }

    func testStressSummariesAndTrainingLoad() {
        let zone = TimeZone(secondsFromGMT: 7200)!
        let snapshot = CloudSnapshot(fetchedAt: Date(), startDate: "2026-10-02", endDate: "2026-10-03", region: .europe, days: [], payloads: [
            EndpointPayload(endpoint: .stress, raw: .object(["items": .array([.object([
                "timestamp": .number(1_790_892_000_001), "avgStress": .string("49"), "minStress": .string("31"), "maxStress": .string("66"),
                "relaxProportion": .string("15"), "normalProportion": .string("71"), "mediumProportion": .string("14"), "highProportion": .string("0")
            ])])])),
            EndpointPayload(endpoint: .sportLoad, raw: .object(["items": .array([.object([
                "dayId": .string("2026-10-02"), "wtlSum": .number(39), "currnetDayTrainLoad": .number(39),
                "wtlSumOptimalMin": .number(54), "wtlSumOptimalMax": .number(182), "wtlSumOverreaching": .number(219)
            ])])]))
        ], warnings: [])
        let stress = snapshot.stressDays(timeZone: zone)
        XCTAssertEqual(stress.map(\.date), ["2026-10-02"])
        XCTAssertEqual(stress.first?.average, 49)
        XCTAssertEqual(stress.first?.proportions, [15, 71, 14, 0])
        XCTAssertEqual(StressLevel(value: 39), .relaxed)
        XCTAssertEqual(StressLevel(value: 80), .high)
        XCTAssertEqual(snapshot.trainingLoad.first?.weeklyLoad, 39)
        XCTAssertEqual(snapshot.trainingLoad.first?.dayLoad, 39)
        XCTAssertEqual(snapshot.trainingLoad.first?.status, "Low")
    }

    func testWorkoutDecodingIgnoresSentinelsAndParsesZones() throws {
        let item: JSONValue = .object([
            "trackid": .string("1790956091"), "end_time": .string("1790959759"), "run_time": .string("3668"), "type": .number(52),
            "dis": .string("0.0"), "calorie": .string("455.0"), "avg_heart_rate": .string("108.0"), "max_heart_rate": .number(140),
            "min_heart_rate": .number(86), "heart_range": .string("504,97;2481,117;675,136;4,156;0,175;0,195"),
            "te": .number(11), "anaerobic_te": .number(1), "exercise_load": .number(7), "rpe": .number(4),
            "avg_stride_length": .number(-1), "VO2_max": .number(-1), "avg_pace": .string("0.0"),
            "strength_training_group": .string(#"[{"count":10,"actionType":60},{"actionType":0,"count":7}]"#),
            "syncedTimezone": .string("Europe/Madrid")
        ])
        let treadmill: JSONValue = .object(["trackid": .string("1790959811"), "end_time": .string("1790961911"), "type": .number(8),
                                            "dis": .string("2331.0"), "avg_pace": .string("0.8983"), "avg_heart_rate": .string("135.0"),
                                            "max_heart_rate": .number(-1)])
        let snapshot = CloudSnapshot(fetchedAt: Date(), startDate: "2026-10-02", endDate: "2026-10-02", region: .europe, days: [], payloads: [
            EndpointPayload(endpoint: .workouts, raw: .object(["code": .number(1), "data": .object(["summary": .array([item, treadmill, .object(["type": .number(1)])])])]))
        ], warnings: [])
        let workouts = snapshot.workouts
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(workouts[0].info.title, "Treadmill")
        XCTAssertNil(workouts[0].maxHeartRate)
        XCTAssertEqual(workouts[0].distance, 2331)
        let strength = workouts[1]
        XCTAssertEqual(strength.info.title, "Strength training")
        XCTAssertEqual(strength.duration, 3668)
        XCTAssertNil(strength.distance)
        XCTAssertNil(strength.strideLength)
        XCTAssertNil(strength.averagePace)
        XCTAssertEqual(strength.aerobicEffect ?? 0, 1.1, accuracy: 0.001)
        XCTAssertEqual(strength.sets, [10, 7])
        XCTAssertEqual(strength.zones.map(\.seconds), [504, 2481, 675, 4, 0, 0])
        XCTAssertNil(strength.zones[0].lower)
        XCTAssertEqual(strength.zones[1].lower, 97)
        XCTAssertEqual(strength.zones[5].title, "VO₂ max")
        XCTAssertEqual(strength.timeZone?.identifier, "Europe/Madrid")
        XCTAssertEqual(snapshot.heartZoneBounds, [97, 117, 136, 156, 175, 195])
        XCTAssertTrue(HeartZoneTime.parse("10,97;5,90").isEmpty)
    }

    func testDemoHasNoCredentialsAndSurvivesRoundTrip() throws {
        let demo = CloudSnapshot.demo()
        XCTAssertEqual(demo.days.count, 14)
        XCTAssertEqual(demo.payloads.count, CloudEndpoint.allCases.count)
        XCTAssertFalse(demo.days[0].heartRatePoints.isEmpty)
        XCTAssertNotNil(demo.days[0].asleepMinutes)
        XCTAssertEqual(demo.days[0].hourlySteps?.reduce(0, +), demo.days[0].steps.map(Int.init))
        XCTAssertFalse(demo.workouts.isEmpty)
        XCTAssertFalse(demo.trainingLoad.isEmpty)
        XCTAssertFalse(demo.stressDays().isEmpty)
        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(CloudSnapshot.self, from: data)
        XCTAssertEqual(decoded.days.count, 14)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apptoken"))
    }
}

func band(summary: JSONValue, heart: [UInt8]) throws -> JSONValue {
    let encoded = try JSONEncoder().encode(summary).base64EncodedString()
    return .object(["code": .number(1), "data": .array([.object([
        "date_time": .string("2026-02-03"), "source": .number(10289411),
        "summary": .string(encoded), "data_hr": .string(Data(heart).base64EncodedString())
    ])])])
}
private func stage(_ start: Double, _ end: Double, _ mode: Double) -> JSONValue {
    .object(["start": .number(start), "stop": .number(end), "mode": .number(mode)])
}
