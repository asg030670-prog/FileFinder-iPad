#if os(iOS)
import SwiftUI
import FileFinderCore

/// Shows the most recent log entries (indexing, searches, file operations) for diagnostics.
struct ActivityLogView: View {
    @State private var entries: [LogEntry] = []

    var body: some View {
        List(Array(entries.reversed())) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.level.description)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color(for: entry.level))
                    Text(entry.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    entries = LogStore.shared.recentEntries()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    LogStore.shared.clear()
                    entries = []
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .onAppear { entries = LogStore.shared.recentEntries() }
        .overlay {
            if entries.isEmpty {
                EmptyStateView(title: "No Activity", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .teal
        case .warning: return .orange
        case .error: return .red
        }
    }
}
#endif
