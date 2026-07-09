import SwiftUI
import CCTTCore

/// The resizable detail window: a global time-range + unit toolbar over tabbed
/// breakdowns. Reads the shared stores from the environment.
struct DetailView: View {
    @Environment(UsageStore.self) private var store
    @Environment(DisplayState.self) private var display

    var body: some View {
        @Bindable var display = display
        let breakdown = store.breakdown(range: display.timeRange)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Range", selection: $display.timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()

                Spacer()

                Picker("Unit", selection: $display.unit) {
                    ForEach(DisplayUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
            .padding(10)

            Divider()

            TabView {
                ProjectsTab(breakdown: breakdown, unit: display.unit)
                    .tabItem { Label("Projects", systemImage: "folder") }
                ModelsTab(breakdown: breakdown, unit: display.unit)
                    .tabItem { Label("Models", systemImage: "cpu") }
                AgentsSkillsPluginsTab(breakdown: breakdown, unit: display.unit)
                    .tabItem { Label("Agents", systemImage: "person.2") }
                SessionsTimelineTab(timeline: store.timeline(range: display.timeRange),
                                    sessions: store.sessions(range: display.timeRange),
                                    unit: display.unit)
                    .tabItem { Label("Sessions", systemImage: "clock") }
                ContextWindowsTab(summaries: store.contextSummaries(range: display.timeRange),
                                  seriesProvider: { store.contextSeries(sessionId: $0) })
                    .tabItem { Label("Context", systemImage: "square.stack.3d.up") }
            }
        }
        .frame(minWidth: 660, minHeight: 480)
    }
}
