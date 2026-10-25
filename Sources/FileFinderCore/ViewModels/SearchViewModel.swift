import Foundation
#if canImport(Combine)
import Combine
#endif

/// Drives the search screen: real-time (debounced) searching, filters, sorting,
/// grouping, search history and suggestions.
@MainActor
public final class SearchViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case searching
        case results
        case empty
        case failed(String)
    }

    // MARK: Inputs

    /// Text typed by the user; every change triggers a debounced search.
    @Published public var searchText: String = "" {
        didSet { if searchText != oldValue { textDidChange() } }
    }
    @Published public var filter: SearchFilter = .none {
        didSet { if filter != oldValue { scheduleSearch(immediately: true) } }
    }
    @Published public var searchContents: Bool {
        didSet { if searchContents != oldValue { scheduleSearch(immediately: true) } }
    }
    @Published public var sort: SortOption = .default {
        didSet { if sort != oldValue { resort() } }
    }
    @Published public var grouping: ResultGrouping = .none {
        didSet { if grouping != oldValue { regroup() } }
    }

    // MARK: Outputs

    @Published public private(set) var results: [SearchResult] = []
    @Published public private(set) var sections: [ResultSection] = []
    @Published public private(set) var state: State = .idle
    @Published public private(set) var history: [SearchHistoryEntry] = []
    @Published public private(set) var suggestions: [SearchHistoryEntry] = []
    @Published public private(set) var lastSearchDuration: TimeInterval?
    /// `true` when the result list was truncated to `AppConfiguration.maximumResults`.
    @Published public private(set) var isTruncated = false

    public let environment: AppEnvironment
    private var searchTask: Task<Void, Never>?
    private var observerID: UUID?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.searchContents = environment.configuration.contentSearchEnabledByDefault
        self.history = environment.historyStore.entries
        self.suggestions = environment.historyStore.suggestions(matching: "")
        self.observerID = environment.addIndexObserver { [weak self] in
            self?.indexDidChange()
        }
    }

    // MARK: - Query

    public var currentQuery: SearchQuery {
        SearchQuery(
            text: searchText,
            scope: searchContents ? .all : .default,
            filter: filter,
            sort: sort,
            limit: environment.configuration.maximumResults
        )
    }

    public var hasQuery: Bool { !currentQuery.isEmpty }

    public var activeFilterCount: Int { filter.activeFilterCount }

    // MARK: - Searching

    private func textDidChange() {
        suggestions = environment.historyStore.suggestions(matching: searchText)
        scheduleSearch(immediately: false)
    }

    /// Cancels any pending search and schedules a new one after the debounce delay.
    public func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        let delay = immediately ? 0 : environment.configuration.searchDebounceMilliseconds
        searchTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    /// Runs the current query immediately and awaits the results.
    public func performSearch() async {
        let query = currentQuery
        guard !query.isEmpty else {
            results = []
            sections = []
            isTruncated = false
            state = .idle
            return
        }
        state = .searching
        let startDate = Date()
        do {
            let found = try await environment.searchEngine.search(query)
            guard !Task.isCancelled, query == currentQuery else { return }
            results = found
            isTruncated = found.count >= query.limit
            lastSearchDuration = Date().timeIntervalSince(startDate)
            regroup()
            state = found.isEmpty ? .empty : .results
        } catch is CancellationError {
            return
        } catch FileFinderError.cancelled {
            return
        } catch {
            Log.search.error("Search failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Waits for the pending (debounced) search to finish. Mainly useful for tests.
    public func waitForPendingSearch() async {
        // A new search may be scheduled while waiting (e.g. when the index changes); wait for that one too.
        while let task = searchTask {
            await task.value
            if task == searchTask { break }
        }
    }

    /// Called when the user submits the search field: saves the query in the history.
    public func submit() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        environment.historyStore.record(text, resultCount: results.count)
        history = environment.historyStore.entries
        scheduleSearch(immediately: true)
    }

    public func applyHistoryEntry(_ entry: SearchHistoryEntry) {
        searchText = entry.text
        submit()
    }

    public func removeHistoryEntry(_ entry: SearchHistoryEntry) {
        environment.historyStore.remove(entry)
        history = environment.historyStore.entries
        suggestions = environment.historyStore.suggestions(matching: searchText)
    }

    public func clearHistory() {
        environment.historyStore.clear()
        history = []
        suggestions = []
    }

    // MARK: - Filters

    public func toggleCategory(_ category: FileCategory) {
        if filter.categories.contains(category) {
            filter.categories.remove(category)
        } else {
            filter.categories.insert(category)
        }
    }

    /// Shows everything in a category (used by the sidebar shortcuts).
    public func showCategory(_ category: FileCategory) {
        filter = SearchFilter(categories: [category])
    }

    public func showLocation(_ location: SearchLocation) {
        filter = SearchFilter(locationIDs: [location.id])
    }

    public func showRecentFiles(days: Int = 7) {
        var newFilter = SearchFilter(dateFilter: .lastDays(days), includeFolders: false)
        newFilter.categories = []
        filter = newFilter
        sort = SortOption(field: .modificationDate, ascending: false)
    }

    public func resetFilters() {
        filter = .none
    }

    public func clear() {
        searchTask?.cancel()
        searchText = ""
        filter = .none
        results = []
        sections = []
        state = .idle
    }

    // MARK: - Results

    private func resort() {
        results = SearchEngine.sort(results, by: sort)
        regroup()
        // Re-run so truncated result sets pick the right top N for the new order.
        if isTruncated { scheduleSearch(immediately: true) }
    }

    private func regroup() {
        sections = ResultSection.group(results, by: grouping, locationNames: environment.locationNames)
    }

    private func indexDidChange() {
        guard hasQuery else { return }
        scheduleSearch(immediately: true)
    }

    /// Removes a result locally (e.g. after deletion) without waiting for a new search.
    public func removeResult(path: String) {
        results.removeAll { $0.item.path == path || $0.item.isContained(in: path) }
        regroup()
    }
}
