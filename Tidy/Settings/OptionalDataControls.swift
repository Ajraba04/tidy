import SwiftUI

/// Clears only the optional stores named in the actor-issued review. No file
/// operations, policy changes or recovery reset are performed by the view.
struct OptionalDataControls: View {
    let services: AppExecutionServices
    @State private var review: AppDataClearReview?
    @State private var busy = false
    @State private var message: String?
    @State private var requestID = UUID()

    var body: some View {
        GroupBox("Optional app data") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Clear completed reports or the scan index. Settings, local consent and mandatory recovery records are preserved. Future history follows your existing settings.")
                    .font(.caption)
                ForEach(OptionalDataKind.allCases) { kind in
                    Button("Review \(kind.title.lowercased())…") { prepare(kind) }
                        .disabled(busy || services.isClearingOptionalData)
                        .accessibilityIdentifier("settings.data.review." + kind.rawValue)
                }
                if let review {
                    Text(review.kind.title).font(.headline)
                    Text("Current logical file size: \(review.byteCount) bytes")
                    ForEach(review.storagePaths, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text("The index database keeps its schema and may retain allocated space. This is not a promise of reclaimed disk space.")
                        .font(.caption)
                    HStack {
                        Button("Clear reviewed data", role: .destructive) { confirm(review) }
                            .disabled(busy)
                            .accessibilityIdentifier("settings.data.confirm")
                        Button("Cancel", role: .cancel) { cancel() }.disabled(busy)
                            .accessibilityIdentifier("settings.data.cancel")
                    }
                }
                if busy { ProgressView("Updating optional data…") }
                if let message {
                    Text(message).font(.caption)
                        .accessibilityIdentifier("settings.data.status")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { cancel() }
    }

    private func prepare(_ kind: OptionalDataKind) {
        cancel()
        let id = UUID(); requestID = id; busy = true; message = nil
        Task { @MainActor in
            do {
                let value = try await services.previewOptionalDataClearing(kind)
                guard requestID == id else {
                    services.cancelOptionalDataReview(value.id); return
                }
                review = value
            } catch {
                guard requestID == id else { return }
                message = "Review unavailable. Finish or cancel active work, then try again. Unsafe or unreadable storage is preserved."
            }
            busy = false
        }
    }

    private func confirm(_ value: AppDataClearReview) {
        busy = true
        let id = requestID
        Task { @MainActor in
            do {
                try await services.confirmOptionalDataClearing(value)
                guard requestID == id else { return }
                message = "Reviewed \(value.kind.title.lowercased()) cleared."
            } catch {
                guard requestID == id else { return }
                message = "Clearing was not confirmed. Data may have changed, work may be active, or storage may be unavailable. Review again before retrying."
            }
            review = nil; busy = false
        }
    }

    private func cancel() {
        requestID = UUID()
        if let review { services.cancelOptionalDataReview(review.id) }
        review = nil; busy = false
    }
}
