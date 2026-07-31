import SwiftUI
import TidyCore

/// A titled section with a leading count/size summary, used to give every
/// report section the same shape.
struct ReportSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.vertical, 4)
    }
}

struct RankedItemsList: View {
    let items: [RankedItem]
    let emptyText: String

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { item in
                HStack {
                    Text(PathDisplay.tilde(item.path))
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(ByteFormat.human(item.bytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SimpleTextList: View {
    let lines: [String]
    let emptyText: String

    var body: some View {
        if lines.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
