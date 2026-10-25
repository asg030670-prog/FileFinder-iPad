import Foundation
#if canImport(Combine)
import Combine
#endif

/// Composition root: creates and owns every service and store, and coordinates indexing.
///
/// Views receive the environment (or the view models created from it), never the services
/// directly, which keeps the UI layer free of business logic (MVVM).
@MainActor
public final class AppEnvironment: ObservableObject {
    public let configuration: AppConfiguration
    public let index: FileIndex
    public let searchEngine: SearchEngine
    public let indexingService: IndexingService
    public let fileOperations: FileOperationsService
    public let previewService: FilePreviewService
    public let historyStore: SearchHistoryStore
    public let favoritesStore: FavoritesStore
    public let locationStore: LocationStore

    @Published public private(set) var isIndexing = false
    @Published public private(set) var indexedItemCount = 0
    @Published public private(set) var indexingStatus: String = ""
    @Published public private(set) var lastIndexingErrors: [String] = []
    @Published public private(set) var locations: [SearchLocation] = []
    @Published public private(set) var lastFullIndexDate: Date?

    private var indexTask: Task<Void, Never>?
    private var hasStarted = false
    private var indexObservers: [UUID: @MainActor () -> Void] = [:]

    public init(
        configuration: AppConfiguration = .default,
        keyValueStore: KeyValueStore = UserDefaults.standard,
        indexPersistence: IndexPersistence? = .default(),
        documentsURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ) {
        self.configuration = configuration
        let index = FileIndex(persistence: indexPersistence)
        self.index = index
        let contentSearcher = ContentSearcher(maximumFileSize: configuration.maximumContentSearchFileSize)
        self.searchEngine = SearchEngine(
            index: index,
            cache: SearchCache(capacity: configuration.searchCacheCapacity),
            contentSearcher: contentSearcher,
            maximumContentSearchFiles: configuration.maximumContentSearchFiles
        )
        self.indexingService = IndexingService(index: index, scanner: FileScanner(options: configuration.scanOptions))
        self.fileOperations = FileOperationsService()
        self.previewService = FilePreviewService(maximumPreviewCharacters: configuration.maximumPreviewCharacters, contentSearcher: contentSearcher)
        self.historyStore = SearchHistoryStore(store: keyValueStore, maximumEntries: configuration.maximumHistoryEntries)
        self.favoritesStore = FavoritesStore(store: keyValueStore)
        self.locationStore = LocationStore(store: keyValueStore, documentsURL: documentsURL)
        self.locations = locationStore.locations
    }

    // MARK: - Index observation

    /// Registers a handler called on the main actor every time the index changes.
    @discardableResult
    public func addIndexObserver(_ handler: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        indexObservers[id] = handler
        return id
    }

    public func removeIndexObserver(_ id: UUID) {
        indexObservers.removeValue(forKey: id)
    }

    public func notifyIndexChanged() {
        Task { @MainActor in
            self.indexedItemCount = await self.index.count
            for handler in self.indexObservers.values { handler() }
        }
    }

    // MARK: - Indexing

    /// Loads the cached index from disk, then refreshes it in the background if it is stale.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        // Re-establish security-scoped access so cached results can be previewed and opened.
        for location in locationStore.enabledLocations where location.kind == .userSelected {
            do {
                _ = try locationStore.beginAccessing(location)
            } catch {
                lastIndexingErrors.append(error.localizedDescription)
            }
        }
        if await index.load() {
            indexedItemCount = await index.count
            for handler in indexObservers.values { handler() }
        }
        if needsReindexing {
            await reindexAll()
        }
    }

    /// `true` when a location was never indexed or its index is older than `reindexIntervalMinutes`.
    public var needsReindexing: Bool {
        let interval = TimeInterval(configuration.reindexIntervalMinutes * 60)
        return locationStore.enabledLocations.contains { location in
            guard let last = location.lastIndexed else { return true }
            return Date().timeIntervalSince(last) > interval
        }
    }

    /// Re-indexes in the background when the index is stale (e.g. when the app becomes active).
    public func refreshIfNeeded() {
        guard hasStarted, needsReindexing else { return }
        startReindexing()
    }

    /// Starts re-indexing (if not already running) without waiting for completion.
    public func startReindexing() {
        guard !isIndexing, indexTask == nil else { return }
        indexTask = Task {
            await self.reindexAll()
            self.indexTask = nil
        }
    }

    /// Re-indexes every enabled location sequentially.
    public func reindexAll() async {
        if isIndexing { return }
        isIndexing = true
        lastIndexingErrors = []
        defer { isIndexing = false }
        Log.index.info("Re-indexing \(locationStore.enabledLocations.count) locations")

        // Drop items of locations that were removed or disabled.
        let enabledIDs = Set(locationStore.enabledLocations.map(\.id))
        for id in await index.indexedLocationIDs where !enabledIDs.contains(id) {
            await index.removeLocation(id)
        }

        for location in locationStore.enabledLocations {
            if Task.isCancelled { break }
            await reindex(location)
        }
        await index.save()
        lastFullIndexDate = Date()
        indexingStatus = "\(indexedItemCount) items indexed"
    }

    /// Re-indexes a single location.
    public func reindex(_ location: SearchLocation) async {
        let root: URL
        do {
            root = try locationStore.beginAccessing(location)
        } catch {
            lastIndexingErrors.append(error.localizedDescription)
            return
        }
        indexingStatus = "Indexing \(location.name)…"
        let name = location.name
        let outcome = await indexingService.indexLocation(id: location.id, root: root) { [weak self] count in
            Task { @MainActor in
                self?.indexingStatus = "Indexing \(name)… \(count) items"
            }
        }
        if let errorDescription = outcome.errorDescription {
            lastIndexingErrors.append("\(location.name): \(errorDescription)")
        } else {
            locationStore.markIndexed(location.id, itemCount: outcome.itemCount)
        }
        locations = locationStore.locations
        indexedItemCount = await index.count
        for handler in indexObservers.values { handler() }
    }

    public func cancelIndexing() {
        indexTask?.cancel()
    }

    // MARK: - Locations

    @discardableResult
    public func addLocation(_ url: URL) throws -> SearchLocation {
        let location = try locationStore.addFolder(url)
        locations = locationStore.locations
        Task { await self.reindex(location); await self.index.save() }
        return location
    }

    public func removeLocation(_ location: SearchLocation) {
        locationStore.remove(location)
        locations = locationStore.locations
        Task {
            await self.index.removeLocation(location.id)
            await self.index.save()
            self.notifyIndexChanged()
        }
    }

    public func setLocation(_ location: SearchLocation, enabled: Bool) {
        locationStore.setEnabled(enabled, for: location)
        locations = locationStore.locations
        Task {
            if enabled {
                if let updated = self.locationStore.location(withID: location.id) {
                    await self.reindex(updated)
                }
            } else {
                await self.index.removeLocation(location.id)
                self.notifyIndexChanged()
            }
            await self.index.save()
        }
    }

    public func locationName(for item: FileItem) -> String? {
        guard let id = item.locationID else { return nil }
        return locationStore.location(withID: id)?.name
    }

    public var locationNames: [String: String] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) })
    }

    // MARK: - Index maintenance after file operations

    /// Refreshes the index entry for `url` after it was created or modified.
    public func registerChange(at url: URL, replacing oldPath: String? = nil) async {
        if let oldPath {
            await index.remove(path: oldPath)
        }
        let locationID = locationStore.location(containing: url.path)?.id
        if let item = try? FileItem(url: url, locationID: locationID) {
            await index.upsert(item)
            if item.isDirectory {
                // Pick up the contents of copied/moved folders.
                if let children = try? FileScanner(options: configuration.scanOptions).scan(root: url, locationID: locationID) {
                    for child in children { await index.upsert(child) }
                }
            }
        }
        notifyIndexChanged()
    }

    public func registerDeletion(of path: String) async {
        await index.remove(path: path)
        favoritesStore.remove(path: path)
        notifyIndexChanged()
    }
}
