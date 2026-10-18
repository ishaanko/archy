import SwiftUI
import UniformTypeIdentifiers

/// Reads a user-chosen file into memory. It does not validate geometry or upload data.
@MainActor
struct ScanAttachmentPicker: View {
    let side: FootSide
    @Binding var attachment: InsoleScan?
    @State private var importing = false
    @State private var errorMessage: String?

    private static let maximumBytes = 20 * 1_024 * 1_024
    private static let allowedExtensions: Set<String> = ["stl", "obj", "ply", "glb", "usdz"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Optional \(side.rawValue) foot scan", systemImage: "cube.transparent")
                .font(.headline)
            Text("STL, OBJ, PLY, GLB or USDZ · up to 20 MB")
                .font(.subheadline).foregroundStyle(Color.archySecondary)
            if let attachment {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.filename).font(.subheadline.weight(.medium))
                        .lineLimit(3).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.bytes.count), countStyle: .file))
                        .font(.caption).foregroundStyle(Color.archySecondary)
                }.accessibilityElement(children: .combine)
                Text("Included in your export.")
                    .font(.subheadline.weight(.medium))
                Text("Check this is the correct foot. Calibration and fit need specialist review.")
                    .font(.footnote).foregroundStyle(Color.archySecondary)
            }
            HStack {
                Button(attachment == nil ? "Choose scan file" : "Replace scan file") { importing = true }
                    .accessibilityIdentifier("scan.choose")
                if attachment != nil {
                    Spacer()
                    Button("Remove", role: .destructive) { attachment = nil; errorMessage = nil }
                        .accessibilityIdentifier("scan.remove")
                }
            }.font(.subheadline.weight(.medium)).tint(Color.archyAccent)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Color.archyAccent)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { (result: Result<URL, Error>) in
            switch result {
            case .success(let url): read(url)
            case .failure(let error):
                if !isCancellation(error) { errorMessage = error.localizedDescription }
            }
        }
    }

    private func read(_ url: URL) {
        errorMessage = nil
        guard Self.allowedExtensions.contains(url.pathExtension.lowercased()) else {
            errorMessage = "Choose an STL, OBJ, PLY, GLB, or USDZ file."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard metadata.isRegularFile == true else {
                errorMessage = "Choose a regular scan file, rather than a folder."
                return
            }
            guard let size = metadata.fileSize else {
                errorMessage = "The file size could not be checked. Choose a locally available file."
                return
            }
            guard size <= Self.maximumBytes else {
                errorMessage = "This file is larger than 20 MB. Choose a smaller scan."
                return
            }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= Self.maximumBytes else {
                errorMessage = "This file is larger than 20 MB. Choose a smaller scan."
                return
            }
            guard !bytes.isEmpty else {
                errorMessage = "This file is empty. Choose a scan containing data."
                return
            }
            attachment = InsoleScan(filename: url.lastPathComponent, side: side, bytes: bytes)
        } catch {
            if !isCancellation(error) { errorMessage = error.localizedDescription }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
