#if os(iOS)
import SwiftUI
import FileFinderCore

/// Bookmarked files and folders.
struct FavoritesView: View {
    @ObservedObject var viewModel: FavoritesViewModel
    @Binding var selection: FileItem?

    var body: some View {
        Group {
            if viewModel.favorites.isEmpty {
                EmptyStateView(
                    title: "No Favorites",
                    systemImage: "star",
                    message: "Add files to your favorites from the result list (swipe right) or from the file details."
                )
            } else {
                List(selection: $selection) {
                    ForEach(viewModel.favorites) { favorite in
                        if let item = viewModel.item(for: favorite) {
                            NavigationLink(value: item) {
                                FileRowView(item: item)
                            }
                        } else {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(favorite.name)
                                    Text("File no longer available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in
                        viewModel.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.pruneMissing()
                    } label: {
                        Label("Remove Missing Files", systemImage: "trash.slash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(viewModel.favorites.isEmpty)
            }
        }
        .onAppear { viewModel.reload() }
    }
}
#endif
