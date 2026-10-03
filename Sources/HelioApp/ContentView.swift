import SwiftUI
import HelioCore

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    notices
                    screenContent
                    footer
                }
                .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 28)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .toolbar { toolbar }
        .sheet(isPresented: $store.showConnection) { ConnectionSheet(store: store) }
    }

    private var screen: Screen { store.screen ?? .today }

    @ViewBuilder private var screenContent: some View {
        if screen == .account { ConnectionSettings(store: store) }
        else if store.snapshot == nil { WelcomeView(store: store) }
        else {
            switch screen {
            case .today: TodayView(store: store)
            case .heart: HeartView(store: store)
            case .sleep: SleepView(store: store)
            case .stress: StressView(store: store)
            case .activity: ActivityView(store: store)
            case .workouts: WorkoutsView(store: store)
            case .data: RawDataView(store: store)
            case .account: EmptyView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: screen.symbol).foregroundStyle(screen.tint).font(.system(size: 13, weight: .semibold))
                        Eyebrow(text: screen.title)
                    }
                    Text(headline).font(.system(size: 30, weight: .bold)).lineLimit(1)
                }
                Spacer()
                if store.snapshot != nil && screen.isDaily { DateStepper(store: store) }
            }
            if store.snapshot != nil && screen.isDaily && store.deviceDays.count > 1 { DayStrip(store: store) }
        }
    }

    private var headline: String {
        guard store.snapshot != nil, screen.isDaily, !store.selectedDate.isEmpty else {
            switch screen {
            case .workouts: return "Workouts"
            case .data: return "Raw cloud data"
            case .account: return "Zepp account"
            default: return "Welcome to Helio"
            }
        }
        return Format.relativeDay(store.selectedDate)
    }

    @ViewBuilder private var notices: some View {
        if store.isDemo {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                Text("You're viewing sample data, not readings from your strap.").font(.callout)
                Spacer()
                Button("Exit sample data") { Task { await store.leaveDemo() } }.disabled(store.isBusy)
            }
            .padding(12)
            .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if let error = store.error {
            Banner(title: "Something needs attention", message: error, symbol: "exclamationmark.triangle.fill", tint: Palette.workout)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isBusy ? "arrow.triangle.2.circlepath" : "internaldrive").font(.caption)
            Text(store.status).font(.caption)
            Spacer()
            Text("Independent of Amazfit and Zepp · Not medical advice").font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if store.isBusy {
                ProgressView().controlSize(.small)
                Button("Cancel") { store.cancel() }
            } else {
                Picker("Download range", selection: $store.syncDays) {
                    Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                }
                .frame(width: 100)
                .help("How many recent days to download")
                Button { store.sync() } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(!store.isConnected).help("Download recent data from Zepp (⌘R)")
            }
            Button { store.export() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .disabled(store.snapshot == nil).help("Export downloaded data as JSON")
        }
    }
}

private struct Sidebar: View {
    @Bindable var store: AppStore
    private let sections: [(String, [Screen])] = [("", [.today]), ("Health", [.heart, .sleep, .stress]),
                                                  ("Fitness", [.activity, .workouts]), ("Data", [.data, .account])]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 38, height: 38).padding(-3)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Helio").font(.system(size: 17, weight: .bold))
                    Text("for Mac").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)

            List(selection: $store.screen) {
                ForEach(sections, id: \.0) { title, screens in
                    Section {
                        ForEach(screens) { screen in
                            Label {
                                Text(screen.title)
                            } icon: {
                                Image(systemName: screen.symbol).foregroundStyle(screen.tint)
                            }
                            .tag(screen)
                        }
                    } header: { if !title.isEmpty { Text(title) } }
                }
            }
            .listStyle(.sidebar)

            DeviceCard(store: store).padding(12)
        }
    }
}

private struct DeviceCard: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isConnected || store.snapshot != nil {
                HStack(spacing: 10) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill").foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.isDemo ? "Sample strap" : store.deviceName).font(.callout.weight(.semibold))
                        Text(syncText).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if store.isConnected {
                    Button { store.sync() } label: {
                        Label(store.isBusy ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular).disabled(store.isBusy)
                }
            }
            if !store.isConnected {
                Button("Connect Zepp account") { store.showConnection = true }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(store.isBusy)
                if store.snapshot == nil {
                    Button("Explore sample data") { store.showDemo(); store.screen = .today }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(store.isBusy)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var syncText: String {
        guard let snapshot = store.snapshot else { return "Not synced yet" }
        let when = snapshot.fetchedAt.formatted(.relative(presentation: .named))
        return "Synced \(when)"
    }
}

private struct DateStepper: View {
    @Bindable var store: AppStore
    var body: some View {
        HStack(spacing: 2) {
            Button { store.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 26, height: 24) }
                .disabled(!store.canGoBack).keyboardShortcut(.leftArrow, modifiers: [.command])
            Menu {
                ForEach(store.deviceDays.reversed()) { day in
                    Button(Format.longDay(day.date)) { store.selectedDate = day.date }
                }
            } label: {
                Text(Format.shortDay(store.selectedDate)).font(.callout.weight(.medium)).monospacedDigit()
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button { store.step(1) } label: { Image(systemName: "chevron.right").frame(width: 26, height: 24) }
                .disabled(!store.canGoForward).keyboardShortcut(.rightArrow, modifiers: [.command])
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .help("Previous or next day (⌘← / ⌘→)")
    }
}

/// One chip per downloaded day, with a small ring for the day's step goal.
private struct DayStrip: View {
    @Bindable var store: AppStore
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.deviceDays) { day in
                        let selected = day.date == store.selectedDate
                        Button { store.selectedDate = day.date } label: {
                            VStack(spacing: 6) {
                                Text(Format.weekday(day.date)).font(.system(size: 10, weight: .semibold)).foregroundStyle(selected ? .primary : .secondary)
                                ZStack {
                                    Ring(progress: (day.steps ?? 0) / (day.stepGoal ?? 8000), tint: Palette.activity, lineWidth: 3.5)
                                    Text(Format.dayNumber(day.date)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                }
                                .frame(width: 34, height: 34)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 8)
                            .background(selected ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Palette.hairline : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(day.date)
                        .help(Format.longDay(day.date))
                    }
                }
            }
            .onAppear { proxy.scrollTo(store.selectedDate, anchor: .trailing) }
            .onChange(of: store.selectedDate) { proxy.scrollTo(store.selectedDate) }
        }
    }
}

private struct WelcomeView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack {
                Circle().fill(Palette.heart.opacity(0.12)).frame(width: 120).offset(x: -26, y: 10)
                Circle().fill(Palette.sleep.opacity(0.14)).frame(width: 100).offset(x: 40, y: -14)
                Circle().fill(Palette.activity.opacity(0.12)).frame(width: 80).offset(x: 34, y: 42)
                Image(systemName: "waveform.path.ecg").font(.system(size: 50, weight: .semibold)).foregroundStyle(Palette.accent)
            }
            .frame(width: 180, height: 140, alignment: .center)
            Text("Your Helio Strap,\non a bigger screen.").font(.system(size: 36, weight: .bold))
            Text("Sync the strap with Zepp on your iPhone, then connect your Zepp account here. Helio downloads heart rate, sleep, stress, steps, and workouts, and keeps a private copy on this Mac.")
                .font(.title3).foregroundStyle(.secondary).frame(maxWidth: 620, alignment: .leading)
            HStack(spacing: 12) {
                Button("Connect Zepp account") { store.showConnection = true }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("Explore sample data") { store.showDemo() }.controlSize(.large)
            }
            Banner(title: "Unofficial connection", message: "Zepp doesn't publish an API for the Helio Strap. Helio uses community-documented endpoints that may change. Your password goes to Zepp's website, never to Helio.")
                .frame(maxWidth: 680)
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
    }
}
