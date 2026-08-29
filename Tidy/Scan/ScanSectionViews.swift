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

/// Space macOS is holding in swap and VM files.
///
/// Three rules this view exists to keep, all of them about not making a
/// promise the app cannot keep: no action button, because Tidy genuinely
/// cannot release these bytes; separate lines per component, because a
/// restart does not treat swapfiles, a sleep image, and a kernel core
/// reservation identically; and the verb is always "macOS is holding" or
/// "a restart returns", never "Tidy frees".
struct RestartReclaimSection: View {
    let survey: RestartReclaimSurvey

    var body: some View {
        ReportSection(title: "A restart usually reclaims this") {
            ForEach(survey.components) { component in
                HStack {
                    Text(component.fileCount > 1
                         ? "\(component.label) (\(component.fileCount))"
                         : component.label)
                        .font(.callout)
                    Spacer()
                    Text(ByteFormat.human(component.bytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Total held").font(.callout.bold())
                Spacer()
                Text(ByteFormat.human(survey.totalBytes))
                    .font(.callout.monospacedDigit().bold())
            }

            Text("""
                 macOS grows these on demand and does not release them while this Mac stays booted, \
                 so Tidy will not touch them. Restarting usually returns most of this space.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let pagedOutBytes = survey.pagedOutBytes {
                Text("""
                     \(ByteFormat.human(pagedOutBytes)) of it is currently paged out, which is \
                     memory that has to come back rather than space a restart hands you.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("How much of this is currently paged out could not be measured (\(survey.pagedOutUnavailableReason ?? "unavailable")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if survey.pageOutsCumulative != nil {
                Text("""
                     The Headroom window also tracks how fast pages are currently being swapped \
                     out, as a pressure signal -- not a measurement of disk writes, and not proof \
                     that swap is being cleared.
                     """)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Measured just now. Swap grows and shrinks constantly.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
