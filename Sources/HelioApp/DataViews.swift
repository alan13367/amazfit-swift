import SwiftUI
import HelioCore

struct RawDataView: View {
    @Bindable var store: AppStore
    @State private var endpoint: CloudEndpoint = .band
    @State private var decoded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Banner(title: "Private health data", message: "These are the responses exactly as Zepp returned them, including fields Helio doesn't chart yet. They can contain account and device identifiers. Session tokens are removed before saving.", symbol: "lock.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CloudEndpoint.allCases) { item in
                        let payload = store.snapshot?.payload(item)
                        Button { endpoint = item } label: {
                            HStack(spacing: 6) {
                                Circle().fill(color(payload)).frame(width: 7, height: 7)
                                Text(item.title).font(.callout.weight(endpoint == item ? .semibold : .regular))
                                Text(count(payload)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(endpoint == item ? Color.white.opacity(0.1) : Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let payload = store.snapshot?.payload(endpoint) {
                if let warning = payload.warning {
                    Banner(title: "Note", message: warning, symbol: "exclamationmark.triangle.fill", tint: Palette.workout)
                }
                Card(title: endpoint.title, symbol: "curlybraces", tint: Palette.muted,
                     subtitle: "\(store.snapshot?.startDate ?? "") to \(store.snapshot?.endDate ?? "") · select text to copy") {
                    if endpoint == .band {
                        Toggle("Decoded summary for \(Format.shortDay(store.selectedDate))", isOn: $decoded).toggleStyle(.switch).controlSize(.small)
                    }
                } content: {
                    JSONText(value: endpoint == .band && decoded ? store.day?.summary ?? .null : payload.raw)
                }
            } else {
                Card { EmptyState(symbol: "icloud.slash", text: "This endpoint wasn't downloaded.") }
            }
            HStack {
                Button { store.export() } label: { Label("Export everything as JSON…", systemImage: "square.and.arrow.up") }
                Spacer()
            }
        }
    }

    private func count(_ payload: EndpointPayload?) -> String {
        guard let payload else { return "" }
        let items = payload.raw["items"].array.count + payload.raw["data"].array.count + payload.raw["data"]["summary"].array.count
        return items > 0 ? "\(items)" : ""
    }
    private func color(_ payload: EndpointPayload?) -> Color {
        guard let payload else { return Palette.muted }
        if payload.warning != nil && payload.raw == .null { return Palette.heart }
        return count(payload).isEmpty ? Palette.muted : Palette.activity
    }
}

struct JSONText: View {
    let value: JSONValue
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(value.prettyPrinted).font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(hex: 0xC9D1D9))
                .textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120, maxHeight: 520)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("JSON cloud response")
    }
}
