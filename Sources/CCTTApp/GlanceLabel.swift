import SwiftUI
import CCTTCore

/// Popover contents: overall total + top projects/models. Placeholder for the
/// rich popover built in Plan 3; proves the pipeline end-to-end for now.
struct PopoverView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total tokens: \(DefaultPaths.formatTokens(snapshot.overall.total))")
                .font(.headline)
            Text("\(snapshot.overall.eventCount) messages")
                .font(.caption).foregroundStyle(.secondary)

            if !snapshot.byProject.isEmpty {
                Divider()
                Text("Top projects").font(.caption.bold())
                ForEach(snapshot.byProject.prefix(5), id: \.key) { r in
                    HStack {
                        Text(r.key).lineLimit(1)
                        Spacer()
                        Text(DefaultPaths.formatTokens(r.totals.total))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            if snapshot.parseErrors > 0 {
                Text("\(snapshot.parseErrors) unparsed lines")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Divider()
            Button("Quit CCTT") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
