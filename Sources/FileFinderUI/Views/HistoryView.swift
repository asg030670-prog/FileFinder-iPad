#if os(iOS)
import SwiftUI
import FileFinderCore

/// Previously executed searches.
struct HistoryView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (SearchHistoryEntry) -> Void

    var body: some View {
        Group {
            if viewModel.history.isEmpty {
                EmptyStateView(
                    title: "No Search History",
                    systemImage: "clock.arrow.circlepath",
                    message: "Searches you submit with the Search key appear here."
                )
            } else {
                List {
                    ForEach(viewModel.history) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            HStack {
                                Label(entry.text, systemImage: "magnifyingglass")
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(entry.resultCount) results")
                                    Text(entry.date, style: .relative)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { viewModel.history[$0] }.forEach(viewModel.removeHistoryEntry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", role: .destructive) {
                    viewModel.clearHistory()
                }
                .disabled(viewModel.history.isEmpty)
            }
        }
    }
}
#endif
