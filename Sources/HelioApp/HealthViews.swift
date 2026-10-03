import SwiftUI
import Charts
import HelioCore

struct HeartView: View {
    @Bindable var store: AppStore

    var body: some View {
        let points = store.heartPoints
        let values = points.map(\.value)
        VStack(alignment: .leading, spacing: 18) {
            TileGrid {
                StatTile(title: "Resting", value: Format.int(store.day?.restingHeartRate), unit: "bpm", detail: "From sleep", symbol: "bed.double.fill", tint: Palette.heart)
                StatTile(title: "Average", value: values.isEmpty ? "—" : Format.int(values.reduce(0, +) / Double(values.count)), unit: "bpm",
                         detail: "Minute readings", symbol: "waveform.path.ecg", tint: Palette.heart)
                StatTile(title: "Lowest", value: Format.int(values.min()), unit: "bpm", detail: lowestTime(points), symbol: "arrow.down", tint: Palette.heart)
                StatTile(title: "Highest", value: Format.int(store.day?.maxHeartRate?.bpm ?? values.max()), unit: "bpm",
                         detail: store.day?.maxHeartRate?.date.map { "at " + Format.time($0, store.zone) }, symbol: "arrow.up", tint: Palette.heart)
                StatTile(title: "Monitored", value: Format.duration(minutes: Double(store.day?.wornMinutes ?? 0)),
                         detail: "Minutes with a reading", symbol: "clock", tint: Palette.heart)
            }
            Card(title: "Heart rate", symbol: "heart.fill", tint: Palette.heart, subtitle: "Hover to inspect a minute · device time zone") {
                HStack(spacing: 14) {
                    LegendItem(title: "Sleep", color: Palette.sleep.opacity(0.5))
                    LegendItem(title: "Workout", color: Palette.workout.opacity(0.5))
                }
            } content: {
                if let range = store.dayRange, !points.isEmpty {
                    HeartRateDayChart(points: points, range: range, zone: store.zone, highlights: store.highlights,
                                      resting: store.day?.restingHeartRate, peak: store.day?.maxHeartRate)
                        .frame(height: 300)
                } else {
                    EmptyState(symbol: "heart", text: "No heart-rate readings for this day. Gaps mean the strap was off or charging.")
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Time in zones", symbol: "flame.fill", tint: Palette.heart, subtitle: zoneSubtitle) {
                    if let zones = dayZones(points), zones.contains(where: { $0.seconds > 0 }) {
                        ZoneBars(zones: zones)
                    } else {
                        EmptyState(symbol: "flame", text: "Zones appear once a workout has synced, because zone limits come from your workout settings.", height: 150)
                    }
                }
                Card(title: "While asleep", symbol: "moon.stars.fill", tint: Palette.sleep, subtitle: "Heart rate during last night's sleep") {
                    let sleep = store.sleepHeartRate.map(\.value)
                    if sleep.isEmpty {
                        EmptyState(symbol: "moon.zzz", text: "No readings during a recorded sleep.", height: 150)
                    } else {
                        HStack(spacing: 26) {
                            MiniStat(title: "Average", value: Format.int(sleep.reduce(0, +) / Double(sleep.count)), unit: "bpm")
                            MiniStat(title: "Lowest", value: Format.int(sleep.min()), unit: "bpm")
                            MiniStat(title: "Resting", value: Format.int(store.day?.restingHeartRate), unit: "bpm")
                        }
                        if let first = store.sleepHeartRate.first?.date, let last = store.sleepHeartRate.last?.date {
                            HeartRateDayChart(points: store.sleepHeartRate, range: first...last, zone: store.zone, resting: store.day?.restingHeartRate)
                                .frame(height: 120)
                        }
                    }
                }
            }
            if store.deviceDays.count >= 2 {
                let days = store.deviceDays
                HStack(alignment: .top, spacing: 18) {
                    Card(title: "Daily range", symbol: "arrow.up.and.down", tint: Palette.heart, subtitle: "Lowest to highest minute reading") {
                        let ranges = store.dailyHeartRanges
                        TrendChart(values: ranges, tint: Palette.heart, unit: "bpm", selectedDate: store.selectedDate,
                                   domain: max(0, (ranges.compactMap(\.low).min() ?? 40) - 10)...((ranges.map(\.value).max() ?? 180) + 10))
                            .frame(height: 170)
                    }
                    Card(title: "Resting heart rate", symbol: "bed.double.fill", tint: Palette.heart, subtitle: "Lower usually means better recovery") {
                        let resting = days.compactMap { d in d.restingHeartRate.map { DailyValue(date: d.date, value: $0) } }
                        if resting.isEmpty { EmptyState(symbol: "heart", text: "No resting values in this range.", height: 170) }
                        else {
                            TrendChart(values: resting, tint: Palette.heart, unit: "bpm", selectedDate: store.selectedDate,
                                       domain: max(0, (resting.map(\.value).min() ?? 50) - 8)...((resting.map(\.value).max() ?? 70) + 6))
                                .frame(height: 170)
                        }
                    }
                }
            }
        }
    }

    private var zoneSubtitle: String {
        guard let bounds = store.heartZoneBounds, let top = bounds.last else { return "Whole day" }
        return "Whole day · limits from your \(Int(top)) bpm maximum"
    }

    private func lowestTime(_ points: [MetricPoint]) -> String? {
        points.min { $0.value < $1.value }.map { "at " + Format.time($0.date, store.zone) }
    }

    private func dayZones(_ points: [MetricPoint]) -> [HeartZoneTime]? {
        guard let bounds = store.heartZoneBounds, !points.isEmpty else { return nil }
        var minutes = Array(repeating: 0.0, count: bounds.count)
        for point in points {
            if let index = bounds.firstIndex(where: { point.value < $0 }) { minutes[index] += 1 }
            else { minutes[bounds.count - 1] += 1 }
        }
        return bounds.enumerated().map { index, upper in
            HeartZoneTime(index: index, seconds: minutes[index] * 60, lower: index == 0 ? nil : bounds[index - 1], upper: upper)
        }
    }
}

struct SleepView: View {
    @Bindable var store: AppStore

    var body: some View {
        if let day = store.day, !store.stages.isEmpty {
            content(day)
        } else {
            Card {
                EmptyState(symbol: "moon.zzz", text: "No sleep was recorded for the night ending on \(Format.longDay(store.selectedDate)). Wear the strap overnight and sync it in Zepp.", height: 260)
            }
            if store.deviceDays.count >= 2 { history }
        }
    }

    @ViewBuilder private func content(_ day: BandDay) -> some View {
        let zone = store.zone
        let stages = store.stages
        let start = stages.first!.start
        let end = stages.last!.end
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 28) {
                ZStack {
                    Ring(progress: (day.sleepScore ?? 0) / 100, tint: Palette.sleep, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text(Format.int(day.sleepScore)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("SCORE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 138, height: 138)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Asleep")
                        Figure(value: Format.duration(minutes: day.asleepMinutes), size: 40)
                        Text("\(Format.time(start, zone)) – \(Format.time(end, zone)) · \(Format.duration(minutes: end.timeIntervalSince(start) / 60)) in bed")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 30) {
                        MiniStat(title: "Wake-ups", value: Format.int(day.wakeCount))
                        MiniStat(title: "Awake", value: Format.duration(minutes: day.minutes(in: .awake)))
                        MiniStat(title: "Resting HR", value: Format.int(day.restingHeartRate), unit: "bpm")
                        MiniStat(title: "Efficiency", value: efficiency(day, start, end), unit: "%")
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.sleep.opacity(0.16), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.sleep.opacity(0.18)))

            Card(title: "Sleep stages", symbol: "waveform", tint: Palette.sleep, subtitle: "Hover a stage for its time and length") {
                HStack(spacing: 14) {
                    ForEach(Hypnogram.order, id: \.self) { LegendItem(title: $0.title, color: Palette.stage($0)) }
                }
            } content: {
                Hypnogram(stages: stages, zone: zone).frame(height: 210)
                if !store.sleepHeartRate.isEmpty {
                    Divider().overlay(Palette.hairline)
                    HStack {
                        Eyebrow(text: "Heart rate while asleep")
                        Spacer()
                        let values = store.sleepHeartRate.map(\.value)
                        Text("avg \(Format.int(values.reduce(0, +) / Double(values.count))) · low \(Format.int(values.min())) bpm")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    HeartRateDayChart(points: store.sleepHeartRate, range: start...end, zone: zone, resting: day.restingHeartRate)
                        .frame(height: 110)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Stage breakdown", symbol: "chart.bar.fill", tint: Palette.sleep) { StageBreakdown(day: day) }
                Card(title: "About this night", symbol: "info.circle", tint: Palette.sleep) {
                    VStack(alignment: .leading, spacing: 10) {
                        fact("Deep sleep", "\(share(day, .deep))% of sleep. Adults usually spend 13–23% in deep sleep.")
                        fact("REM", "\(share(day, .rem))% of sleep. REM typically fills 20–25% of the night.")
                        fact("Record date", "Zepp files a night under the morning it ended.")
                    }
                }
            }
            if store.deviceDays.count >= 2 { history }
        }
    }

    private var history: some View {
        let days = store.deviceDays
        return HStack(alignment: .top, spacing: 18) {
            Card(title: "Time asleep", symbol: "bed.double.fill", tint: Palette.sleep) {
                let values = days.compactMap { d in d.asleepMinutes.map { DailyValue(date: d.date, value: $0 / 60) } }
                if values.isEmpty { EmptyState(symbol: "moon.zzz", text: "No nights in this range.", height: 160) }
                else {
                    TrendChart(values: values, tint: Palette.sleep, unit: "", goal: 8, format: { Format.duration(minutes: $0 * 60) },
                               selectedDate: store.selectedDate).frame(height: 160)
                }
            }
            Card(title: "Sleep score", symbol: "star.fill", tint: Palette.sleep) {
                let values = days.compactMap { d in d.sleepScore.map { DailyValue(date: d.date, value: $0) } }
                if values.isEmpty { EmptyState(symbol: "moon.zzz", text: "No scores in this range.", height: 160) }
                else { TrendChart(values: values, tint: Palette.sleep, selectedDate: store.selectedDate, domain: 0...100).frame(height: 160) }
            }
        }
    }

    private func fact(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold))
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func share(_ day: BandDay, _ kind: SleepStage.Kind) -> Int {
        guard let asleep = day.asleepMinutes, asleep > 0 else { return 0 }
        return Int((100 * day.minutes(in: kind) / asleep).rounded())
    }
    private func efficiency(_ day: BandDay, _ start: Date, _ end: Date) -> String {
        guard let asleep = day.asleepMinutes else { return "—" }
        return Format.int(100 * asleep / (end.timeIntervalSince(start) / 60))
    }
}

struct StressView: View {
    @Bindable var store: AppStore

    var body: some View {
        let points = store.stressPoints
        let summary = store.stressDay
        let values = points.map(\.value)
        VStack(alignment: .leading, spacing: 18) {
            TileGrid {
                StatTile(title: "Average", value: Format.int(summary?.average ?? (values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))),
                         detail: (summary?.average).map { StressLevel(value: $0).title }, symbol: "gauge.with.dots.needle.33percent", tint: Palette.stress)
                StatTile(title: "Lowest", value: Format.int(summary?.minimum ?? values.min()), symbol: "arrow.down", tint: Palette.stress)
                StatTile(title: "Highest", value: Format.int(summary?.maximum ?? values.max()), symbol: "arrow.up", tint: Palette.stress)
                StatTile(title: "Readings", value: "\(points.count)", detail: "Every 5 minutes when enabled", symbol: "clock", tint: Palette.stress)
            }
            Card(title: "Stress through the day", symbol: "brain.head.profile", tint: Palette.stress, subtitle: "Scores from 1 to 100, derived from heart-rate variability") {
                HStack(spacing: 12) {
                    ForEach(StressLevel.allCases, id: \.self) { LegendItem(title: $0.title, color: Palette.stress($0)) }
                }
            } content: {
                if let range = store.dayRange, !points.isEmpty {
                    StressDayChart(points: points, range: range, zone: store.zone).frame(height: 250)
                } else {
                    EmptyState(symbol: "brain", text: "No stress readings for this day. Turn on automatic stress monitoring in Zepp to collect them.")
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Time at each level", symbol: "chart.bar.fill", tint: Palette.stress) {
                    if let proportions = summary?.proportions ?? levelShares(values) {
                        ProportionBar(parts: StressLevel.allCases.map { (proportions[$0.rawValue], Palette.stress($0)) }, height: 14)
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                            ForEach(StressLevel.allCases, id: \.self) { level in
                                GridRow {
                                    LegendItem(title: level.title, color: Palette.stress(level))
                                    Text("\(Int(level.range.lowerBound))–\(Int(level.range.upperBound))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    Spacer()
                                    Text("\(Int(proportions[level.rawValue]))%").font(.callout.weight(.semibold)).monospacedDigit()
                                }
                            }
                        }
                    } else {
                        EmptyState(symbol: "chart.bar", text: "No level breakdown for this day.", height: 150)
                    }
                }
                Card(title: "Daily average", symbol: "calendar", tint: Palette.stress) {
                    let daily = store.stressDays.compactMap { s in s.average.map { DailyValue(date: s.date, value: $0) } }
                    if daily.isEmpty { EmptyState(symbol: "chart.bar", text: "No daily stress summaries.", height: 150) }
                    else { TrendChart(values: daily, tint: Palette.stress, selectedDate: store.selectedDate, domain: 0...100).frame(height: 150) }
                }
            }
            Banner(title: "Stress is not HRV", message: "The strap computes stress from heart-rate variability, but Zepp's cloud returns only the score. Helio does not convert it back into an HRV value.", tint: Palette.stress)
        }
    }

    private func levelShares(_ values: [Double]) -> [Double]? {
        guard !values.isEmpty else { return nil }
        return StressLevel.allCases.map { level in (100 * Double(values.filter { StressLevel(value: $0) == level }.count) / Double(values.count)).rounded() }
    }
}
