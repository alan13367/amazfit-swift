import SwiftUI
import HelioCore

private enum Screen: String, CaseIterable, Identifiable {
    case overview, heart, sleep, activity, cloud, connection
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .heart: "Heart & stress"
        case .sleep: "Sleep"
        case .activity: "Activity & load"
        case .cloud: "All cloud fields"
        case .connection: "Connection"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .heart: "heart"
        case .sleep: "moon"
        case .activity: "figure.walk"
        case .cloud: "curlybraces"
        case .connection: "link"
        }
    }
}

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var selection: Screen? = .overview
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg").font(.title).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Helio").font(.title2.weight(.semibold))
                        Text("YOUR HEALTH, ON MAC").font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                List(Screen.allCases, selection: $selection) { screen in
                    Label(screen.title, systemImage: screen.icon).tag(screen).padding(.vertical, 5)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 12) {
                    Label(store.isConnected ? "Zepp session saved" : "No account connected", systemImage: store.isConnected ? "checkmark.shield" : "lock")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(store.isConnected ? "Update connection" : "Connect Zepp account") { store.showConnection = true }
                        .buttonStyle(.borderedProminent).disabled(store.isBusy)
                    Button("Explore sample data") { store.showDemo(); selection = .overview }
                        .buttonStyle(.plain).font(.caption).disabled(store.isBusy)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if store.isDemo {
                        HStack {
                            Label("Sample data. Not readings from your strap.", systemImage: "eye").font(.callout.weight(.medium))
                            Spacer()
                            Button("Exit sample data") { Task { await store.leaveDemo() } }.disabled(store.isBusy)
                        }.padding(14).background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let error = store.error {
                        Notice(title: "Something needs attention", message: error, symbol: "exclamationmark.triangle", color: .orange)
                    }
                    if let snapshot = store.snapshot, !snapshot.warnings.isEmpty {
                        Notice(title: "Cloud connection notes", message: snapshot.warnings.joined(separator: "\n"), symbol: "icloud.slash", color: .orange)
                    }
                    if selection == .connection { ConnectionSettings(store: store) }
                    else if store.snapshot == nil { welcome }
                    else {
                        if selection != .cloud { selectors }
                        switch selection ?? .overview {
                        case .overview: OverviewView(store: store)
                        case .heart: HeartView(store: store)
                        case .sleep: SleepView(store: store)
                        case .activity: ActivityView(store: store)
                        case .cloud: CloudFieldsView(store: store)
                        case .connection: EmptyView()
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                        Label(store.status, systemImage: store.isBusy ? "arrow.down.circle" : "internaldrive").font(.caption).foregroundStyle(.secondary)
                        Text("Helio is independent of Amazfit and Zepp. Data shown here is not medical advice.").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(28).frame(maxWidth: 1160, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.mint).preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { store.cancel() }
                } else {
                    Picker("Download range", selection: $store.syncDays) {
                        Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                    }.frame(width: 110)
                    Button { store.sync() } label: { Label("Sync", systemImage: "arrow.clockwise") }
                        .disabled(!store.isConnected).help("Download recent data from Zepp")
                }
                Button { store.export() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(store.snapshot == nil).help("Export cloud data as JSON")
            }
        }
        .sheet(isPresented: $store.showConnection) { ConnectionSheet(store: store) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text((selection ?? .overview).title).font(.system(size: 30, weight: .semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if let snapshot = store.snapshot {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.isDemo ? "SAMPLE DATA" : "LAST DOWNLOAD").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Text(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).monospacedDigit()
                }
            }
        }
    }
    private var subtitle: String {
        switch selection ?? .overview {
        case .overview: "A closer look at the data your strap shares with Zepp."
        case .heart: "Heart rate and stress are separate measurements. Stress is not HRV."
        case .sleep: "Sleep is shown on the cloud record's date, often the night you fell asleep."
        case .activity: "Daily movement and the training fields returned by your account."
        case .cloud: "Downloaded responses, including fields we have not decoded yet."
        case .connection: "Direct access to Zepp. No third-party server."
        }
    }
    private var selectors: some View {
        HStack(spacing: 20) {
            Picker("Band date", selection: $store.selectedDate) {
                ForEach(Array((store.snapshot?.dates ?? []).reversed()), id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 220)
            Picker("Device", selection: $store.selectedSource) {
                ForEach(store.snapshot?.sources ?? [], id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 320)
            Spacer()
        }.onChange(of: store.selectedSource) { if store.day == nil { store.selectLatest() } }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 54, weight: .light)).foregroundStyle(.mint)
            Text("Your Helio Strap.\nA little more room to see it.").font(.system(size: 34, weight: .medium))
            Text("Sync your strap with Zepp on your iPhone, then connect your Zepp account here. Helio downloads the cloud records and keeps a local copy for offline viewing.")
                .foregroundStyle(.secondary).frame(maxWidth: 590, alignment: .leading)
            HStack {
                Button("Connect Zepp account") { store.showConnection = true }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("Try sample data") { store.showDemo() }.controlSize(.large)
            }
            Divider().padding(.vertical, 8)
            Notice(title: "Unofficial cloud connection", message: "Zepp does not provide a documented public Helio account API. This app uses community-documented endpoints, which can change. Your password goes to Zepp's website, not Helio. HRV, readiness, SpO₂, and respiratory rate do not yet have a verified data route here.", symbol: "info.circle", color: .mint)
        }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}
