import SwiftUI

/// The Scan tab at rest: how a scan works in one glance, previous scans, then Start (or a sample on devices without LiDAR).
@MainActor
struct ScanIntroView: View {
    let isSupported: Bool
    let previous: [SavedScan]
    let onStart: () -> Void
    let onSample: () -> Void
    let onTips: () -> Void
    let onImport: () -> Void
    let onOpen: (SavedScan) -> Void
    let onDelete: (SavedScan) -> Void

    @AppStorage(MeasurementUnit.storageKey) private var unit = MeasurementUnit.localeDefault()
    @State private var pendingDelete: SavedScan?

    private static let tips = [
        "Ask someone to hold the phone.",
        "Stand barefoot on a plain floor.",
        "Two slow laps around your foot.",
    ]

    var body: some View {
        List {
            Text("Scan your foot")
                .display(.hero)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.sm)
                .reveal(0)
                .introRow()
            PositioningDiagram()
                .reveal(1)
                .introRow()
            VStack(spacing: 0) {
                ForEach(Array(Self.tips.enumerated()), id: \.offset) { index, tip in
                    if index > 0 { Hairline() }
                    Text(tip)
                        .foregroundStyle(.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.md)
                }
            }
            .reveal(2)
            .introRow()
            previousScans
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { actions.reveal(3) }
        .confirmationDialog("Delete this scan?", isPresented: deleting, titleVisibility: .visible, presenting: pendingDelete) { scan in
            Button("Delete", role: .destructive) { onDelete(scan) }
        } message: { _ in
            Text("Its model and photos are removed from this iPhone.")
        }
    }

    private var deleting: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    // MARK: Previous scans

    @ViewBuilder
    private var previousScans: some View {
        if previous.isEmpty {
            Button("Import a scan", action: onImport)
                .buttonStyle(.archyGhost)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("scan.import")
                .introRow()
        } else {
            HStack {
                Text("Previous scans").display(.headline)
                Spacer()
                Button("Import a scan", action: onImport)
                    .buttonStyle(.archyGhost)
                    .font(.subheadline)
                    .accessibilityIdentifier("scan.import")
            }
            .padding(.top, Space.md)
            .introRow()
            ForEach(previous) { scan in
                Button { onOpen(scan) } label: { row(scan) }
                    .buttonStyle(.archyPressable)
                    .accessibilityIdentifier("scan.previous")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparatorTint(.line2)
                    .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { pendingDelete = scan }
                    }
            }
        }
    }

    /// Date and time, then the length and arch once measured.
    private func row(_ scan: SavedScan) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.date.formatted(.dateTime.month(.abbreviated).day().year()))
                Text(scan.date.formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.inkSecondary)
            }
            Spacer()
            if let length = scan.summary?.lengthMM, let isFlat = scan.summary?.isFlat {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(unit.format(millimeters: length)).monospacedDigit()
                    Text(isFlat ? "Flat arch" : "Normal arch")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.sm) {
            if isSupported {
                Button("Start scan", action: onStart)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("scan.start")
                HStack {
                    Button("How to scan", action: onTips)
                    Button("View a sample", action: onSample)
                        .accessibilityIdentifier("scan.sample")
                }
                .buttonStyle(.archyGhost)
            } else {
                Text("Scanning needs an iPhone with LiDAR.")
                    .font(.callout)
                    .foregroundStyle(.inkSecondary)
                Button("View a sample scan", action: onSample)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("scan.sample")
                Button("How to scan", action: onTips)
                    .buttonStyle(.archyGhost)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity)
        .background(Color.bg)
    }
}

private extension View {
    /// A plain, separator-free list row at the page margins.
    func introRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Space.sm, leading: Space.page, bottom: Space.sm, trailing: Space.page))
    }
}
