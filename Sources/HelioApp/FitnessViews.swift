import SwiftUI
import Charts
import HelioCore

struct ActivityView: View {
    @Bindable var store: AppStore

    var body: some View {
        let day = store.day
        let goal = day?.stepGoal ?? 8000
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 30) {
                ZStack {
                    Ring(progress: (day?.steps ?? 0) / goal, tint: Palette.activity, lineWidth: 13)
                    VStack(spacing: 0) {
                        Image(systemName: "figure.walk").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.activity)
                        Text("\(Int(((day?.steps ?? 0) / goal * 100).rounded()))%").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                }
                .frame(width: 138, height: 138)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Steps")
                        Figure(value: Format.int(day?.steps), unit: "of \(Format.int(goal))", size: 40)
                    }
                    HStack(spacing: 30) {
                        MiniStat(title: "Distance", value: Format.distance(day?.distance), unit: "km")
                        MiniStat(title: "Calories", value: Format.int(day?.calories), unit: "kcal")
                        MiniStat(title: "Active time", value: Format.duration(minutes: day?.activeMinutes))
                        MiniStat(title: "Workouts", value: "\(store.dayWorkouts.count)")
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.activity.opacity(0.14), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.activity.opacity(0.18)))

            Card(title: "Steps by hour", symbol: "chart.bar.fill", tint: Palette.activity, subtitle: "From the strap's minute record") {
                if let hours = day?.hourlySteps, let start = store.dayStart, hours.contains(where: { $0 > 0 }) {
                    HourlyStepsChart(hours: hours, start: start, zone: store.zone).frame(height: 200)
                } else {
                    EmptyState(symbol: "shoeprints.fill", text: "No minute-level steps for this day.")
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Movement", symbol: "figure.walk.motion", tint: Palette.activity, subtitle: "Walks and runs the strap detected") {
                    let segments = day?.activitySegments ?? []
                    if segments.isEmpty {
                        EmptyState(symbol: "figure.stand", text: "No continuous movement was detected.", height: 150)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(segments) { segment in
                                SegmentRow(segment: segment, zone: store.zone)
                                if segment.id != segments.last?.id { Divider().overlay(Palette.hairline) }
                            }
                        }
                    }
                }
                TrainingLoadCard(load: store.trainingLoad).frame(maxWidth: 360)
            }
            if store.deviceDays.count >= 2 {
                Card(title: "Daily steps", symbol: "calendar", tint: Palette.activity, subtitle: "Missing days are not zero") {
                    let values = store.deviceDays.compactMap { d in d.steps.map { DailyValue(date: d.date, value: $0) } }
                    TrendChart(values: values, tint: Palette.activity, unit: "steps", goal: goal, selectedDate: store.selectedDate)
                        .frame(height: 190)
                }
            }
        }
    }
}

private struct SegmentRow: View {
    let segment: ActivitySegment
    let zone: TimeZone
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: segment.mode == 4 ? "figure.run" : "figure.walk")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.activity).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.title).font(.callout.weight(.medium))
                Text("\(Format.time(segment.start, zone)) – \(Format.time(segment.end, zone))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                Text(Format.duration(minutes: segment.minutes)).frame(width: 52, alignment: .trailing)
                Text(segment.steps.map { "\(Format.int($0)) steps" } ?? "—").frame(width: 92, alignment: .trailing)
                Text(segment.distance.map { "\(Format.distance($0)) km" } ?? "—").frame(width: 70, alignment: .trailing)
            }
            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct WorkoutsView: View {
    @Bindable var store: AppStore

    var body: some View {
        let workouts = store.workouts
        if workouts.isEmpty {
            Card {
                EmptyState(symbol: "figure.run", text: "No workouts in the downloaded range. Start a workout from the Zepp app while wearing the strap, then sync.", height: 260)
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                Card(title: "History", symbol: "list.bullet", tint: Palette.workout, subtitle: "\(workouts.count) workouts", padding: 14) {
                    VStack(spacing: 8) {
                        ForEach(workouts) { workout in
                            CompactWorkoutRow(workout: workout, zone: workout.timeZone ?? store.zone,
                                              selected: workout.id == store.selectedWorkout?.id) { store.selectedWorkoutID = workout.id }
                        }
                    }
                }
                .frame(width: 290)
                if let workout = store.selectedWorkout { WorkoutDetail(store: store, workout: workout) }
            }
        }
    }
}

private struct CompactWorkoutRow: View {
    let workout: Workout
    let zone: TimeZone
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: workout.info.symbol, tint: Palette.workout, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.info.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(workout.start.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(Format.duration(minutes: workout.duration / 60)).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(9)
            .background(selected ? Palette.workout.opacity(0.14) : Color.white.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct WorkoutDetail: View {
    @Bindable var store: AppStore
    let workout: Workout

    var body: some View {
        let zone = workout.timeZone ?? store.zone
        let heart = store.cached("workoutHR:" + workout.id) {
            store.snapshot?.heartRatePoints(from: workout.start, to: workout.end, source: store.selectedSource) ?? []
        }
        // The strap's daily peak is sampled more finely than minute averages; use it when it falls inside this workout.
        let peak = store.deviceDays.compactMap(\.maxHeartRate).first { $0.date.map { workout.start...workout.end ~= $0 } ?? false }?.bpm
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                IconBadge(symbol: workout.info.symbol, tint: Palette.workout, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.info.title).font(.system(size: 24, weight: .semibold))
                    Text(workout.start.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: zone))
                         + " · \(Format.time(workout.start, zone)) – \(Format.time(workout.end, zone))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.workout.opacity(0.16), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.workout.opacity(0.18)))

            TileGrid(minimum: 140) {
                StatTile(title: "Duration", value: Format.duration(seconds: workout.duration), symbol: "timer", tint: Palette.workout)
                StatTile(title: "Calories", value: Format.int(workout.calories), unit: "kcal", symbol: "flame.fill", tint: Palette.workout)
                StatTile(title: "Avg HR", value: Format.int(workout.averageHeartRate), unit: "bpm", symbol: "heart.fill", tint: Palette.heart)
                StatTile(title: "Max HR", value: Format.int(workout.maxHeartRate ?? peak ?? heart.map(\.value).max()), unit: "bpm",
                         detail: workout.maxHeartRate == nil ? (peak != nil ? "Day's peak" : heart.isEmpty ? nil : "From minute data") : nil, symbol: "arrow.up.heart.fill", tint: Palette.heart)
                if let distance = workout.distance {
                    StatTile(title: "Distance", value: Format.distance(distance), unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Palette.workout)
                }
                if workout.distance != nil, workout.averagePace != nil {
                    StatTile(title: "Avg pace", value: Format.pace(workout.averagePace), unit: "/km", symbol: "speedometer", tint: Palette.workout)
                }
                if let steps = workout.steps { StatTile(title: "Steps", value: Format.int(steps), symbol: "shoeprints.fill", tint: Palette.activity) }
                if let cadence = workout.cadence { StatTile(title: "Cadence", value: Format.int(cadence), unit: "spm", symbol: "metronome.fill", tint: Palette.workout) }
                if let stride = workout.strideLength { StatTile(title: "Stride", value: Format.int(stride), unit: "cm", symbol: "ruler", tint: Palette.workout) }
                if !workout.sets.isEmpty {
                    StatTile(title: "Sets", value: "\(workout.sets.count)", detail: "\(workout.sets.reduce(0, +)) reps", symbol: "dumbbell.fill", tint: Palette.workout)
                }
            }

            Card(title: "Heart rate", symbol: "heart.fill", tint: Palette.heart, subtitle: "Minute readings from the strap, over your zones") {
                if heart.count > 2 {
                    WorkoutHeartChart(points: heart, range: workout.start...workout.end, zone: zone,
                                      bounds: workout.zones.map(\.upper).isEmpty ? (store.heartZoneBounds ?? []) : workout.zones.map(\.upper))
                        .frame(height: 230)
                } else {
                    EmptyState(symbol: "heart", text: "No minute heart-rate readings cover this workout.", height: 150)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Time in zones", symbol: "flame.fill", tint: Palette.heart) {
                    if workout.zones.isEmpty { EmptyState(symbol: "flame", text: "No zone breakdown recorded.", height: 150) }
                    else { ZoneBars(zones: workout.zones) }
                }
                Card(title: "Effort", symbol: "bolt.heart.fill", tint: Palette.load) {
                    VStack(alignment: .leading, spacing: 14) {
                        EffectBar(title: "Aerobic training effect", value: workout.aerobicEffect)
                        EffectBar(title: "Anaerobic training effect", value: workout.anaerobicEffect)
                        HStack(spacing: 30) {
                            MiniStat(title: "Exercise load", value: Format.int(workout.exerciseLoad))
                            MiniStat(title: "Perceived effort", value: workout.perceivedEffort.map { "\(Format.int($0))" } ?? "—", unit: workout.perceivedEffort == nil ? "" : "/ 10")
                        }
                    }
                }
            }
            if !workout.sets.isEmpty {
                Card(title: "Sets", symbol: "dumbbell.fill", tint: Palette.workout, subtitle: "Repetitions counted by the strap") {
                    SetsChart(sets: workout.sets).frame(height: 160)
                }
            }
        }
    }
}

private struct EffectBar: View {
    let title: String
    let value: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\(Format.decimal($0)) · \(label($0))" } ?? "—").font(.caption.weight(.semibold)).monospacedDigit()
            }
            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    let fill = max(0, min(1, (value ?? 0) - Double(index)))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(Palette.load).frame(width: proxy.size.width * fill)
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
    }
    private func label(_ value: Double) -> String {
        switch value {
        case ..<1: "None"
        case ..<2: "Minor"
        case ..<3: "Maintaining"
        case ..<4: "Improving"
        case ..<5: "Highly improving"
        default: "Overreaching"
        }
    }
}

private struct SetsChart: View {
    let sets: [Int]
    @State private var hovered: Int?
    var body: some View {
        Chart {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, reps in
                BarMark(x: .value("Set", index + 1), y: .value("Reps", reps), width: .ratio(0.6))
                    .foregroundStyle(Palette.workout.opacity(hovered == nil || hovered == index + 1 ? 1 : 0.4))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 3) {
                        Text("\(reps)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: 0.4...(Double(sets.count) + 0.6))
        .chartXAxis {
            AxisMarks(values: Array(1...sets.count)) { value in
                AxisValueLabel { if let set = value.as(Int.self) { Text("\(set)").font(.caption2).foregroundStyle(Palette.muted) } }
            }
        }
        .chartYAxis { valueAxis() }
        .chartXSelection(value: $hovered)
    }
}
