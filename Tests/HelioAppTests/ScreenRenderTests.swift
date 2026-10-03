import AppKit
import SwiftUI
import XCTest
import HelioCore
@testable import HelioApp

/// Renders each screen to PNG for visual review. Opt-in only:
/// `HELIO_RENDER_DIR=/path swift test --filter ScreenRenderTests`
/// Set `HELIO_SNAPSHOT` to a cache file to render real data instead of the demo. Output stays local.
@MainActor
final class ScreenRenderTests: XCTestCase {
    func testRenderScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["HELIO_RENDER_DIR"] else { throw XCTSkip("Set HELIO_RENDER_DIR to render screens.") }
        let store = AppStore()
        if let path = environment["HELIO_SNAPSHOT"] {
            let envelope = try JSONValue.decode(Data(contentsOf: URL(fileURLWithPath: path)))
            store.snapshot = try JSONDecoder().decode(CloudSnapshot.self, from: JSONEncoder().encode(envelope["snapshot"]))
        } else {
            store.snapshot = .demo()
        }
        store.selectLatest()
        if let date = environment["HELIO_DATE"] { store.selectedDate = date }
        let screens: [(String, AnyView)] = [
            ("today", AnyView(TodayView(store: store))), ("heart", AnyView(HeartView(store: store))),
            ("sleep", AnyView(SleepView(store: store))), ("stress", AnyView(StressView(store: store))),
            ("activity", AnyView(ActivityView(store: store))), ("workouts", AnyView(WorkoutsView(store: store))),
            ("data", AnyView(RawDataView(store: store)))
        ]
        for (name, content) in screens {
            let view = VStack(alignment: .leading, spacing: 20) {
                Text(Format.relativeDay(store.selectedDate)).font(.system(size: 30, weight: .bold))
                content
            }
            .padding(32).frame(width: 1180).background(Palette.background)
            .environment(\.colorScheme, .dark).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
