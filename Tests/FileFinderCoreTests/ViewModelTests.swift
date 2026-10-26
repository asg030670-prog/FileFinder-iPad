import XCTest
@testable import FileFinderCore

@MainActor
final class SearchViewModelTests: XCTestCase {
    var tmp: TemporaryDirectory!
    var environment: AppEnvironment!

    override func setUp() async throws {
        tmp = try TemporaryDirectory()
        let documents = try tmp.createFolder("Documents")
        try tmp.createFile("Documents/Budget 2024.xlsx", contents: "numbers")
        try tmp.createFile("Documents/Trip/photo.jpg", contents: "jpg")
        try tmp.createFile("Documents/notes.txt", contents: "remember the budget meeting")
        var configuration = AppConfiguration()
        configuration.searchDebounceMilliseconds = 20
        environment = AppEnvironment(
            configuration: configuration,
            keyValueStore: InMemoryKeyValueStore(),
            indexPersistence: IndexPersistence(fileURL: tmp.url.appendingPathComponent("index.plist")),
            documentsURL: documents
        )
        await environment.start()
    }

    override func tearDown() async throws {
        environment = nil
        tmp = nil
    }

    func testStartIndexesDocuments() async {
        XCTAssertEqual(environment.indexedItemCount, 4)
        XCTAssertFalse(environment.isIndexing)
        XCTAssertNotNil(environment.locations.first?.lastIndexed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path("index.plist")))
        XCTAssertFalse(environment.needsReindexing)
    }

    func testCachedIndexIsLoadedOnNextLaunch() async {
        let restarted = AppEnvironment(
            keyValueStore: InMemoryKeyValueStore(),
            indexPersistence: IndexPersistence(fileURL: tmp.url.appendingPathComponent("index.plist")),
            documentsURL: nil
        )
        await restarted.start()
        XCTAssertEqual(restarted.indexedItemCount, 4, "items come from the cached index without scanning")
    }

    func testDebouncedRealTimeSearch() async {
        let viewModel = SearchViewModel(environment: environment)
        viewModel.searchText = "b"
        viewModel.searchText = "bu"
        viewModel.searchText = "budget"
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.results.map(\.item.name), ["Budget 2024.xlsx"])
        XCTAssertEqual(viewModel.state, .results)

        viewModel.searchContents = true
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.results.map(\.item.name), ["Budget 2024.xlsx", "notes.txt"])

        viewModel.searchText = "zzz"
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.state, .empty)

        viewModel.clear()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testFiltersGroupingAndSorting() async {
        let viewModel = SearchViewModel(environment: environment)
        viewModel.showCategory(.image)
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.results.map(\.item.name), ["photo.jpg"])
        XCTAssertEqual(viewModel.activeFilterCount, 1)

        viewModel.resetFilters()
        viewModel.filter.includeFolders = false
        viewModel.sort = SortOption(field: .name, ascending: true)
        viewModel.grouping = .category
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.results.map(\.item.name), ["Budget 2024.xlsx", "notes.txt", "photo.jpg"])
        XCTAssertEqual(viewModel.sections.map(\.title), ["Documents", "Spreadsheets", "Images"])
    }

    func testHistoryAndSuggestions() async {
        let viewModel = SearchViewModel(environment: environment)
        viewModel.searchText = "budget"
        viewModel.submit()
        await viewModel.waitForPendingSearch()
        viewModel.searchText = "photo"
        viewModel.submit()
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.history.map(\.text), ["photo", "budget"])

        viewModel.searchText = "bu"
        XCTAssertEqual(viewModel.suggestions.map(\.text), ["budget"])

        viewModel.applyHistoryEntry(viewModel.history[1])
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.searchText, "budget")
        XCTAssertEqual(viewModel.history.map(\.text), ["budget", "photo"])

        viewModel.removeHistoryEntry(viewModel.history[0])
        XCTAssertEqual(viewModel.history.map(\.text), ["photo"])
        viewModel.clearHistory()
        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testDetailActionsUpdateIndexAndFavorites() async throws {
        let searchViewModel = SearchViewModel(environment: environment)
        searchViewModel.searchText = "notes"
        await searchViewModel.waitForPendingSearch()
        let item = try XCTUnwrap(searchViewModel.results.first?.item)

        let detail = FileDetailViewModel(item: item, environment: environment)
        await detail.load()
        XCTAssertEqual(detail.textPreview, "remember the budget meeting")
        XCTAssertFalse(detail.metadata.isEmpty)

        detail.toggleFavorite()
        XCTAssertTrue(detail.isFavorite)

        var changes: [(String, FileItem?)] = []
        detail.onItemChanged = { changes.append(($0, $1)) }

        await detail.rename(to: "journal.txt")
        XCTAssertNil(detail.errorMessage)
        XCTAssertEqual(detail.item.name, "journal.txt")
        XCTAssertTrue(detail.isFavorite, "favorite follows the renamed file")
        XCTAssertEqual(changes.last?.1?.name, "journal.txt")
        let paths = await environment.index.allItems.map(\.name)
        XCTAssertTrue(paths.contains("journal.txt"))
        XCTAssertFalse(paths.contains("notes.txt"))

        let backup = try tmp.createFolder("Documents/Backup")
        await detail.copy(to: backup)
        XCTAssertNil(detail.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("journal.txt").path))

        await detail.move(to: backup)
        XCTAssertEqual(detail.item.name, "journal 2.txt")
        XCTAssertEqual(detail.item.parentName, "Backup")

        await detail.delete()
        XCTAssertTrue(detail.isDeleted)
        XCTAssertFalse(environment.favoritesStore.isFavorite(path: detail.item.path))
        XCTAssertNil(changes.last?.1)

        await detail.rename(to: "again.txt")
        XCTAssertNotNil(detail.errorMessage, "operating on a deleted file reports an error")
    }

    func testFavoritesAndLocationsViewModels() async throws {
        let favorites = FavoritesViewModel(environment: environment)
        let item = try FileItem(url: tmp.url.appendingPathComponent("Documents/notes.txt"))
        environment.favoritesStore.add(item)
        favorites.reload()
        XCTAssertEqual(favorites.favorites.count, 1)
        XCTAssertEqual(favorites.item(for: favorites.favorites[0])?.locationID, LocationStore.appDocumentsID)
        favorites.remove(atOffsets: IndexSet(integer: 0))
        XCTAssertTrue(favorites.favorites.isEmpty)

        let external = try tmp.createFolder("External")
        try tmp.createFile("External/song.mp3")
        let locations = LocationsViewModel(environment: environment)
        locations.handlePickerResult(.success([external]))
        XCTAssertNil(locations.errorMessage)
        XCTAssertEqual(locations.locations.count, 2)
        let added = try XCTUnwrap(locations.locations.last)
        await locations.reindex(added)
        XCTAssertEqual(environment.indexedItemCount, 5)

        let search = SearchViewModel(environment: environment)
        search.showLocation(added)
        await search.waitForPendingSearch()
        XCTAssertEqual(search.results.map(\.item.name), ["song.mp3"])
    }
}
