#if os(iOS)
import SwiftUI
import FileFinderCore

/// Root of the app: a three column split view (sidebar · results · detail) that adapts to
/// portrait, landscape, Split View and Slide Over on iPad.
public struct FileFinderRootView: View {
    @ObservedObject private var environment: AppEnvironment
    @StateObject private var searchViewModel: SearchViewModel
    @StateObject private var favoritesViewModel: FavoritesViewModel
    @StateObject private var locationsViewModel: LocationsViewModel

    @State private var sidebarSelection: SidebarItem? = .search
    @State private var selectedItem: FileItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(environment: AppEnvironment) {
        self.environment = environment
        _searchViewModel = StateObject(wrappedValue: SearchViewModel(environment: environment))
        _favoritesViewModel = StateObject(wrappedValue: FavoritesViewModel(environment: environment))
        _locationsViewModel = StateObject(wrappedValue: LocationsViewModel(environment: environment))
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(environment: environment, selection: $sidebarSelection)
                .navigationTitle("FileFinder")
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: sidebarSelection) { newValue in
            apply(newValue)
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebarSelection ?? .search {
        case .favorites:
            FavoritesView(viewModel: favoritesViewModel, selection: $selectedItem)
        case .history:
            HistoryView(viewModel: searchViewModel) { entry in
                sidebarSelection = .search
                searchViewModel.applyHistoryEntry(entry)
            }
        case .manageLocations:
            LocationsView(viewModel: locationsViewModel, environment: environment)
        case .activityLog:
            ActivityLogView()
        case .search, .recent, .category, .location:
            SearchResultsView(viewModel: searchViewModel, environment: environment, selection: $selectedItem)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedItem {
            FileDetailView(item: selectedItem, environment: environment) { oldPath, newItem in
                handleChange(oldPath: oldPath, newItem: newItem)
            }
            .id(selectedItem.id)
        } else {
            EmptyStateView(
                title: "No File Selected",
                systemImage: "doc.text.magnifyingglass",
                message: "Select a file to see its preview, details and actions."
            )
        }
    }

    private func apply(_ item: SidebarItem?) {
        guard let item, item.showsResults else { return }
        selectedItem = nil
        switch item {
        case .search:
            searchViewModel.resetFilters()
            searchViewModel.sort = .default
        case .recent:
            searchViewModel.searchText = ""
            searchViewModel.showRecentFiles()
        case .category(let category):
            searchViewModel.searchText = ""
            searchViewModel.showCategory(category)
        case .location(let id):
            if let location = environment.locations.first(where: { $0.id == id }) {
                searchViewModel.searchText = ""
                searchViewModel.showLocation(location)
            }
        default:
            break
        }
    }

    private func handleChange(oldPath: String, newItem: FileItem?) {
        searchViewModel.removeResult(path: oldPath)
        favoritesViewModel.reload()
        selectedItem = newItem
    }
}
#endif
