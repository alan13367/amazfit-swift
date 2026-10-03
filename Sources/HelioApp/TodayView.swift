import SwiftUI
import Charts
import HelioCore

struct TodayView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroRow
            heartCard
            HStack(alignment: .top, spacing: 18) {
                sleepCard
                activityCard
            }
            HStack(alignment: .top, spacing: 18) {
                WorkoutsSummaryCard(store: store)
                TrainingLoadCard(load: store.trainingLoad).frame(maxWidth: 340)
            }
            if store.deviceDays.count >= 2 { TrendsSection(store: store) }
        }
    }

    private var heroRow: some View {
        let day = store.day
        let goal = day?.stepGoal ?? 8000
        let stress = store.stressDay
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
            HeroTile(title: "Steps", value: Format.int(day?.steps), unit: "",
                     detail: day?.steps == nil ? "No step summary" : "\(Int(((day?.steps ?? 0) / goal * 100).rounded()))% of \(Format.int(goal))",
                     symbol: "figure.walk", tint: Palette.activity, progress: (day?.steps ?? 0) / goal) { store.screen = .activity }
            HeroTile(title: "Sleep score", value: Format.int(day?.sleepScore), unit: "",
                     detail: day?.asleepMinutes.map { "\(Format.duration(minutes: $0)) asleep" } ?? "No sleep recorded",
                     symbol: "moon.stars.fill", tint: Palette.sleep, progress: (day?.sleepScore ?? 0) / 100) { store.screen = .sleep }
            HeroTile(title: "Resting heart rate", value: Format.int(day?.restingHeartRate), unit: "bpm",
                     detail: day?.maxHeartRate.map { "Max \(Format.int($0.bpm)) at \(Format.time($0.date, store.zone))" } ?? "Measured during sleep",
                     symbol: "heart.fill", tint: Palette.heart, progress: nil) { store.screen = .heart }
            HeroTile(title: "Stress", value: Format.int(stress?.average), unit: "avg",
                     detail: stress?.average.map { StressLevel(value: $0).title + " day" } ?? "No stress readings",
                     symbol: "brain.head.profile", tint: Palette.stress, progress: (stress?.average ?? 0) / 100) { store.screen = .stress }
        }
    }

    private var heartCard: some View {
        let points = store.heartPoints
        return Card(title: "Heart rate", symbol: "heart.fill", tint: Palette.heart, subtitle: "Minute readings across the device day") {
            Button("Details") { store.screen = .heart }.buttonStyle(LinkButtonStyle())
        } content: {
            if let range = store.dayRange, !points.isEmpty {
                HStack(spacing: 28) {
                    MiniStat(title: "Average", value: Format.int(points.map(\.value).reduce(0, +) / Double(points.count)), unit: "bpm")
                    MiniStat(title: "Lowest", value: Format.int(points.map(\.value).min()), unit: "bpm")
                    MiniStat(title: "Highest", value: Format.int(store.day?.maxHeartRate?.bpm ?? points.map(\.value).max()), unit: "bpm")
                    MiniStat(title: "Monitored", value: Format.duration(minutes: Double(store.day?.wornMinutes ?? 0)))
                    Spacer()
                }
                HeartRateDayChart(points: points, range: range, zone: store.zone, highlights: store.highlights,
                                  resting: store.day?.restingHeartRate, peak: store.day?.maxHeartRate)
                    .frame(height: 210)
            } else {
                EmptyState(symbol: "heart", text: "No heart-rate readings for this day.")
            }
        }
    }

    private var sleepCard: some View {
        Card(title: "Last night", symbol: "moon.stars.fill", tint: Palette.sleep, subtitle: sleepSubtitle) {
            Button("Details") { store.screen = .sleep }.buttonStyle(LinkButtonStyle())
        } content: {
            if let day = store.day, !store.stages.isEmpty {
                HStack(spacing: 26) {
                    MiniStat(title: "Asleep", value: Format.duration(minutes: day.asleepMinutes))
                    MiniStat(title: "Deep", value: Format.duration(minutes: day.minutes(in: .deep)), tint: Palette.stage(.deep))
                    MiniStat(title: "REM", value: Format.duration(minutes: day.minutes(in: .rem)), tint: Palette.stage(.rem))
                    Spacer()
                }
                Hypnogram(stages: store.stages, zone: store.zone, compact: true).frame(height: 96)
                ProportionBar(parts: [SleepStage.Kind.deep, .light, .rem, .awake].map { (day.minutes(in: $0), Palette.stage($0)) }, height: 6)
                HStack(spacing: 14) {
                    ForEach([SleepStage.Kind.deep, .light, .rem, .awake], id: \.self) { LegendItem(title: $0.title, color: Palette.stage($0)) }
                }
            } else {
                EmptyState(symbol: "moon.zzz", text: "No sleep was recorded for the night ending on this day.", height: 190)
            }
        }
    }

    private var sleepSubtitle: String {
        guard let start = store.stages.first?.start, let end = store.stages.last?.end else { return "Night ending this morning" }
        return "\(Format.time(start, store.zone)) – \(Format.time(end, store.zone))"
    }

    private var activityCard: some View {
        Card(title: "Activity", symbol: "figure.walk", tint: Palette.activity, subtitle: "Steps by hour") {
            Button("Details") { store.screen = .activity }.buttonStyle(LinkButtonStyle())
        } content: {
            HStack(spacing: 26) {
                MiniStat(title: "Distance", value: Format.distance(store.day?.distance), unit: "km")
                MiniStat(title: "Calories", value: Format.int(store.day?.calories), unit: "kcal")
                MiniStat(title: "Active", value: Format.duration(minutes: store.day?.activeMinutes))
                Spacer()
            }
            if let hours = store.day?.hourlySteps, let start = store.dayStart, hours.contains(where: { $0 > 0 }) {
                HourlyStepsChart(hours: hours, start: start, zone: store.zone, compact: true).frame(height: 132)
            } else {
                EmptyState(symbol: "shoeprints.fill", text: "No steps recorded yet for this day.", height: 132)
            }
        }
    }
}

struct HeroTile: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    let symbol: String
    let tint: Color
    let progress: Double?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    if let progress {
                        Ring(progress: progress, tint: tint, lineWidth: 7)
                    } else {
                        Circle().fill(tint.opacity(0.14))
                    }
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                        .symbolEffect(.pulse, options: .repeating, isActive: progress == nil && hovering)
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: title)
                    Figure(value: value, unit: unit, size: 30)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [tint.opacity(hovering ? 0.16 : 0.10), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(hovering ? 0.35 : 0.14)))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.label
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
    }
}

struct WorkoutsSummaryCard: View {
    @Bindable var store: AppStore
    var body: some View {
        let today = store.dayWorkouts
        let shown = today.isEmpty ? Array(store.workouts.prefix(1)) : today
        Card(title: "Workouts", symbol: "dumbbell.fill", tint: Palette.workout,
             subtitle: today.isEmpty ? (shown.isEmpty ? "None in this range" : "None on this day · most recent") : "\(today.count) on this day") {
            Button("All") { store.screen = .workouts }.buttonStyle(LinkButtonStyle())
        } content: {
            if shown.isEmpty {
                EmptyState(symbol: "figure.run", text: "Workouts you record on the strap appear here after syncing.", height: 110)
            } else {
                VStack(spacing: 10) {
                    ForEach(shown) { workout in
                        WorkoutRow(workout: workout, zone: store.zone, showDate: today.isEmpty) { store.showWorkout(workout) }
                    }
                }
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: Workout
    let zone: TimeZone
    var showDate = false
    var selected = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBadge(symbol: workout.info.symbol, tint: Palette.workout, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.info.title).font(.system(size: 14, weight: .semibold))
                        Text((showDate ? workout.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone)) + " · " : "")
                             + "\(Format.time(workout.start, zone)) – \(Format.time(workout.end, zone))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        MiniStat(title: "Time", value: Format.duration(minutes: workout.duration / 60))
                        if let distance = workout.distance { MiniStat(title: "Distance", value: Format.distance(distance), unit: "km") }
                        MiniStat(title: "Avg HR", value: Format.int(workout.averageHeartRate), unit: "bpm")
                        MiniStat(title: "Calories", value: Format.int(workout.calories), unit: "kcal")
                    }
                }
                if !workout.zones.isEmpty {
                    ProportionBar(parts: workout.zones.map { ($0.seconds, Palette.zone($0.index)) }, height: 5)
                }
            }
            .padding(12)
            .background(Color.white.opacity(selected ? 0.07 : hovering ? 0.045 : 0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Palette.workout.opacity(0.5) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct TrainingLoadCard: View {
    let load: TrainingLoadDay?
    var body: some View {
        Card(title: "Training load", symbol: "chart.line.uptrend.xyaxis", tint: Palette.load, subtitle: "Last 7 days") {
            if let load {
                HStack(alignment: .firstTextBaseline) {
                    Figure(value: Format.int(load.weeklyLoad), size: 34)
                    Spacer()
                    Text(load.status).font(.callout.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.load.opacity(0.15), in: Capsule())
                }
                LoadGauge(load: load)
                if let low = load.optimalMin, let high = load.optimalMax {
                    Text("Optimal range \(Format.int(low))–\(Format.int(high))" + (load.dayLoad.map { " · \(Format.int($0)) added this day" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                EmptyState(symbol: "chart.line.uptrend.xyaxis", text: "No training-load record was returned.", height: 110)
            }
        }
    }
}

struct LoadGauge: View {
    let load: TrainingLoadDay
    var body: some View {
        let top = max(load.overreaching ?? 0, load.weeklyLoad, load.optimalMax ?? 0) * 1.15
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (value: Double) in width * min(1, max(0, value / max(top, 1))) }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07)).frame(height: 10)
                if let low = load.optimalMin, let high = load.optimalMax {
                    Capsule().fill(Palette.load.opacity(0.35)).frame(width: x(high) - x(low), height: 10).offset(x: x(low))
                }
                if let over = load.overreaching {
                    Rectangle().fill(Palette.muted).frame(width: 2, height: 16).offset(x: x(over) - 1)
                }
                Circle().fill(.white).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Palette.load, lineWidth: 4))
                    .offset(x: x(load.weeklyLoad) - 8)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityLabel("Weekly load \(Format.int(load.weeklyLoad)), \(load.status)")
    }
}

struct TrendsSection: View {
    @Bindable var store: AppStore
    var body: some View {
        let days = store.deviceDays
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Trends · \(Format.shortDay(days.first!.date)) – \(Format.shortDay(days.last!.date))").padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
                trend("Steps", symbol: "figure.walk", tint: Palette.activity,
                      values: days.compactMap { d in d.steps.map { DailyValue(date: d.date, value: $0) } }, goal: days.last?.stepGoal)
                trend("Resting heart rate", symbol: "heart.fill", tint: Palette.heart,
                      values: days.compactMap { d in d.restingHeartRate.map { DailyValue(date: d.date, value: $0) } }, unit: "bpm", domain: restingDomain(days))
                trend("Sleep", symbol: "moon.stars.fill", tint: Palette.sleep,
                      values: days.compactMap { d in d.asleepMinutes.map { DailyValue(date: d.date, value: $0 / 60) } }, unit: "h",
                      format: { Format.duration(minutes: $0 * 60) })
                trend("Average stress", symbol: "brain.head.profile", tint: Palette.stress,
                      values: store.stressDays.compactMap { s in s.average.map { DailyValue(date: s.date, value: $0) } })
            }
        }
    }

    private func restingDomain(_ days: [BandDay]) -> ClosedRange<Double> {
        let values = days.compactMap(\.restingHeartRate)
        return max(1, (values.min() ?? 50) - 8)...((values.max() ?? 70) + 8)
    }

    private func trend(_ title: String, symbol: String, tint: Color, values: [DailyValue], goal: Double? = nil,
                       unit: String = "", format: @escaping (Double) -> String = { Format.int($0) },
                       domain: ClosedRange<Double>? = nil) -> some View {
        Card(title: title, symbol: symbol, tint: tint) {
            if values.isEmpty {
                EmptyState(symbol: "chart.bar", text: "No data in this range.", height: 130)
            } else {
                TrendChart(values: values, tint: tint, unit: unit, goal: goal, format: format, selectedDate: store.selectedDate, domain: domain)
                    .frame(height: 130)
            }
        }
    }
}

extension AppStore {
    /// Sleep and workouts that overlap the selected day, for shading timelines.
    var highlights: [Highlight] {
        guard let range = dayRange else { return [] }
        return cached("highlights:" + selectedDate) { computeHighlights(range) }
    }

    private func computeHighlights(_ range: ClosedRange<Date>) -> [Highlight] {
        var result: [Highlight] = []
        for day in deviceDays {
            let stages = stages(day)
            guard let start = stages.first?.start, let end = stages.last?.end,
                  end > range.lowerBound, start < range.upperBound else { continue }
            result.append(Highlight(id: "sleep-" + day.date, start: start, end: end, title: "Sleep", symbol: "moon.fill", tint: Palette.sleep))
        }
        for workout in workouts where workout.end > range.lowerBound && workout.start < range.upperBound {
            result.append(Highlight(id: workout.id, start: workout.start, end: workout.end, title: workout.info.title,
                                    symbol: workout.info.symbol, tint: Palette.workout, compact: true))
        }
        return result
    }
}
