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

    func testSleepCrossesMidnightAndExcludesAwake() throws {
        let summary: JSONValue = .object(["tz": .string("-21600"), "slp": .object([
            "stage": .array([stage(1380, 1440, 4), stage(1440, 1470, 7), stage(1470, 1530, 8)])
        ])])
        let day = try XCTUnwrap(ZeppDecoder.bandDays(from: band(summary: summary, heart: [])).first)
        XCTAssertEqual(day.deviceTimeZone.secondsFromGMT(), -21600)
        XCTAssertEqual(day.sleepStages.count, 3)
        XCTAssertEqual(day.asleepMinutes, 120)
        XCTAssertEqual(day.sleepStages.last!.end.timeIntervalSince(day.midnight!), 1530 * 60)
        let formatter = DateFormatter()
        formatter.timeZone = day.deviceTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(formatter.string(from: day.sleepStages.last!.end), "2026-02-04 01:30")
    }

    func testOverlappingSleepIsNotDoubleCountedAndInvalidModeIsIgnored() {
        let day = BandDay(date: "2026-02-03", source: "test", summary: .object(["tz": .string("0"), "slp": .object([
            "stage": .array([stage(0, 60, 4), stage(30, 90, 5), stage(90, 100, 7), stage(100, 110, 1e100)])
        ])]), heartRate: [], raw: .null)
        XCTAssertEqual(day.asleepMinutes, 90)
        XCTAssertEqual(day.sleepStages.count, 3)
        let unknown = BandDay(date: day.date, source: "test", summary: .object(["slp": .object(["stage": .array([stage(0, 60, 99)])])]), heartRate: [], raw: .null)
        XCTAssertNil(unknown.asleepMinutes)
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

    func testDemoHasNoCredentialsAndSurvivesRoundTrip() throws {
        let demo = CloudSnapshot.demo()
        XCTAssertEqual(demo.days.count, 7)
        XCTAssertEqual(demo.payloads.count, 7)
        XCTAssertFalse(demo.days[0].heartRatePoints.isEmpty)
        XCTAssertNotNil(demo.days[0].asleepMinutes)
        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(CloudSnapshot.self, from: data)
        XCTAssertEqual(decoded.days.count, 7)
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
