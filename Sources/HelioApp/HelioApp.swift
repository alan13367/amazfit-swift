import SwiftUI

@main
struct HelioApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 960, minHeight: 680)
                .task {
                    await store.restore()
                    if CommandLine.arguments.contains("--demo") { store.showDemo() }
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Connect Zepp account…") { store.showConnection = true }
                    .keyboardShortcut("k", modifiers: [.command])
                    .disabled(store.isBusy)
                Button("Sync from Zepp") { store.sync() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!store.isConnected || store.isBusy)
                Button("Export cloud data…") { store.export() }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(store.snapshot == nil)
            }
        }
        Settings {
            ConnectionSettings(store: store).padding(28).frame(width: 520)
        }
    }
}
