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
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if let attachment {
                        Text(attachment.filename).font(.body).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.bytes.count), countStyle: .file))
                            .font(.footnote).foregroundStyle(.inkSecondary)
                    } else {
                        Text("Attach a \(side.title.lowercased()) foot scan").font(.body)
                        Text("STL, OBJ, PLY, GLB or USDZ, up to 20 MB").font(.footnote).foregroundStyle(.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Space.sm)
                if attachment != nil {
                    Button("Remove") { attachment = nil; errorMessage = nil }
                        .buttonStyle(.archyGhost)
                }
                Button(attachment == nil ? "Choose" : "Replace") { importing = true }
                    .buttonStyle(.archyGhost)
                    .accessibilityIdentifier("scan.choose")
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.negative)
            }
        }
        .animation(Motion.snappy, value: attachment)
        .animation(Motion.snappy, value: errorMessage)
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
