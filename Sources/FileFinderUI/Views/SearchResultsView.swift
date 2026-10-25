#if os(iOS)
import SwiftUI
import FileFinderCore

/// Middle column: search field, toolbar (filters, sort, grouping) and the result list.
struct SearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject var environment: AppEnvironment
    @Binding var selection: FileItem?

    @State private var isShowingFilters = false

    var body: some View {
        resultsContent
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name, .ext or \"phrase\""
            )
            .searchSuggestions {
                ForEach(viewModel.suggestions) { entry in
                    Label(entry.text, systemImage: "clock.arrow.circlepath")
                        .searchCompletion(entry.text)
                }
            }
            .onSubmit(of: .search) {
                viewModel.submit()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterButton
                    sortMenu
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        environment.startReindexing()
                    } label: {
                        Label("Re-index", systemImage: "arrow.clockwise")
                    }
                    .disabled(environment.isIndexing)
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                FilterView(viewModel: viewModel, locations: environment.locations)
            }
            .safeAreaInset(edge: .bottom) {
                statusBar
            }
    }

    private var title: String {
        if viewModel.filter.categories.count == 1, let category = viewModel.filter.categories.first, viewModel.searchText.isEmpty {
            return category.displayName
        }
        return "Search"
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        switch viewModel.state {
        case .idle:
            EmptyStateView(
                title: "Search Your Files",
                systemImage: "magnifyingglass",
                message: "Type a name, an extension such as .pdf, or pick a kind or location in the sidebar.",
                actionTitle: "Show Recent Files",
                action: { viewModel.showRecentFiles() }
            )
        case .searching where viewModel.results.isEmpty:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            EmptyStateView(
                title: "No Results",
                systemImage: "doc.questionmark",
                message: viewModel.filter.isActive
                    ? "Try removing some filters or searching file contents."
                    : "Check the spelling or enable “Search contents” in the filters.",
                actionTitle: viewModel.filter.isActive ? "Clear Filters" : nil,
                action: { viewModel.resetFilters() }
            )
        case .failed(let message):
            EmptyStateView(title: "Search Failed", systemImage: "exclamationmark.triangle", message: message)
        case .searching, .results:
            resultList
        }
    }

    private var resultList: some View {
        List(selection: $selection) {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.results) { result in
                        NavigationLink(value: result.item) {
                            FileRowView(item: result.item, snippet: result.contentSnippet)
                        }
                        .contextMenu { contextMenu(for: result.item) }
                        .swipeActions(edge: .leading) {
                            favoriteButton(for: result.item)
                                .tint(.yellow)
                        }
                    }
                } header: {
                    if viewModel.grouping != .none {
                        Text("\(section.title) (\(section.results.count))")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        favoriteButton(for: item)
        if !item.isDirectory {
            ShareLink(item: item.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            viewModel.filter.folderPath = item.isDirectory ? item.path : item.parentPath
        } label: {
            Label(item.isDirectory ? "Search in Folder" : "Search in Enclosing Folder", systemImage: "folder")
        }
        Button {
            UIPasteboard.general.string = item.path
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }
    }

    private func favoriteButton(for item: FileItem) -> some View {
        let isFavorite = environment.favoritesStore.isFavorite(path: item.path)
        return Button {
            environment.favoritesStore.toggle(item)
            environment.objectWillChange.send()
        } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
        }
    }

    // MARK: - Toolbar

    private var filterButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            Label(
                viewModel.activeFilterCount > 0 ? "Filters (\(viewModel.activeFilterCount))" : "Filters",
                systemImage: viewModel.activeFilterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $viewModel.sort.field) {
                ForEach(SortField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            Picker("Order", selection: $viewModel.sort.ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            Picker("Group By", selection: $viewModel.grouping) {
                ForEach(ResultGrouping.allCases) { grouping in
                    Text(grouping.displayName).tag(grouping)
                }
            }
        } label: {
            Label("Sort & Group", systemImage: "arrow.up.arrow.down.circle")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBar: some View {
        if viewModel.state == .results || environment.isIndexing {
            HStack(spacing: 8) {
                if environment.isIndexing {
                    ProgressView()
                    Text(environment.indexingStatus)
                } else {
                    Text(resultSummary)
                }
                Spacer()
                if let folder = viewModel.filter.folderPath {
                    Button {
                        viewModel.filter.folderPath = nil
                    } label: {
                        Label((folder as NSString).lastPathComponent, systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var resultSummary: String {
        var text = viewModel.isTruncated
            ? "Showing first \(viewModel.results.count) results"
            : "\(viewModel.results.count) result\(viewModel.results.count == 1 ? "" : "s")"
        if let duration = viewModel.lastSearchDuration {
            text += String(format: " · %.0f ms", duration * 1000)
        }
        return text
    }
}
#endif
