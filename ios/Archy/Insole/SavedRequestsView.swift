import SwiftUI

/// Compact list of saved requests; swipe to delete, tap for the details and a share link.
struct SavedRequestsView: View {
    @Environment(InsoleRequestStore.self) private var store

    var body: some View {
        List {
            Text("Saved requests").display(.title)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Space.sm, leading: Space.page, bottom: Space.md, trailing: Space.page))
            if store.requests.isEmpty {
                Text("Nothing saved yet.").foregroundStyle(.inkSecondary)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
            }
            ForEach(store.requests) { request in
                NavigationLink(value: InsoleRoute.request(request.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(request.side.title), \(request.environment == "Microgravity" ? "Zero-g" : request.environment), \(request.material)")
                            .font(.body.weight(.medium))
                        Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote).foregroundStyle(.inkSecondary)
                    }
                    .padding(.vertical, Space.xs)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.line2)
                .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
            }
            .onDelete { offsets in offsets.map { store.requests[$0] }.forEach(store.delete) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .archyScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One saved request: what was configured, the measurements it carries, and a way to share it.
struct SavedRequestView: View {
    @Environment(InsoleRequestStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: InsoleRequest
    @AppStorage(MeasurementUnit.storageKey) private var unit = MeasurementUnit.localeDefault()
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(request.kind).display(.title)
                VStack(spacing: 0) {
                    Hairline()
                    InsoleDetailRow(label: "Foot", value: request.side.title)
                    InsoleDetailRow(label: "Walking on", value: request.environment == "Microgravity" ? "Zero-g" : request.environment)
                    InsoleDetailRow(label: "Material", value: request.material)
                    if let support = request.supportPercent { InsoleDetailRow(label: "Arch support", value: "\(support)%") }
                    ForEach(MeasurementField.allCases) { field in
                        InsoleDetailRow(label: field.title, value: unit.format(millimeters: request.measurementsMM[field], fine: true))
                    }
                    if let scan = request.scan {
                        InsoleDetailRow(label: "Scan", value: "\(scan.filename), \(ByteCountFormatter.string(fromByteCount: Int64(scan.bytes.count), countStyle: .file))")
                    }
                    InsoleDetailRow(label: "Source", value: request.synthetic ? "Sample" : "Saved \(request.assessmentDate.formatted(date: .abbreviated, time: .omitted))")
                }
                VStack(spacing: Space.sm) {
                    ShareLink(item: store.url(request)) { Text("Share for a quote") }
                        .buttonStyle(.archyPrimary)
                    Button("Delete") { confirmingDelete = true }
                        .buttonStyle(.archyGhost)
                        .frame(maxWidth: .infinity)
                }
                Text("Quote request only. Once shared, the recipient may keep a copy.")
                    .font(.footnote).foregroundStyle(.inkTertiary)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.sm)
        }
        .scrollIndicators(.hidden)
        .archyScreen()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this request?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(request); dismiss() }
        } message: { Text("This can't recall copies you already shared.") }
    }
}
