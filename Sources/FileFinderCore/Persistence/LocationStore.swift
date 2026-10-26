import Foundation

/// Persists the folders that FileFinder scans and manages security-scoped access to them.
public final class LocationStore {
    public static let storageKey = "FileFinder.locations"
    public static let appDocumentsID = "app-documents"

    private let store: KeyValueStore
    public private(set) var locations: [SearchLocation]
    /// URLs for which `startAccessingSecurityScopedResource` is currently active.
    private var accessedURLs: [String: URL] = [:]

    public init(store: KeyValueStore, documentsURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        self.store = store
        var locations = store.decode([SearchLocation].self, forKey: LocationStore.storageKey) ?? []
        if let documentsURL {
            if let index = locations.firstIndex(where: { $0.id == LocationStore.appDocumentsID }) {
                // The container path changes between installs/updates; always refresh it.
                locations[index].path = documentsURL.standardizedFileURL.path
            } else {
                locations.insert(
                    SearchLocation(id: LocationStore.appDocumentsID, name: "FileFinder Documents", path: documentsURL.path, kind: .appDocuments),
                    at: 0
                )
            }
        }
        self.locations = locations
    }

    deinit {
        stopAccessingAll()
    }

    public var enabledLocations: [SearchLocation] { locations.filter(\.isEnabled) }

    public func location(withID id: String) -> SearchLocation? {
        locations.first { $0.id == id }
    }

    /// Adds a folder picked by the user (e.g. from `fileImporter`). The URL must be
    /// security-scoped; a bookmark is created so access persists across launches.
    @discardableResult
    public func addFolder(_ url: URL) throws -> SearchLocation {
        let standardizedPath = url.standardizedFileURL.path
        if let existing = locations.first(where: { $0.path == standardizedPath }) {
            return existing
        }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let bookmark: Data?
        do {
            bookmark = try LocationStore.makeBookmark(for: url)
        } catch {
            Log.persistence.error("Could not create bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
            throw FileFinderError.accessDenied(path: url.path)
        }
        let location = SearchLocation(name: url.lastPathComponent, path: standardizedPath, kind: .userSelected, bookmarkData: bookmark)
        locations.append(location)
        save()
        Log.persistence.info("Added location \(location.name)")
        return location
    }

    public func remove(_ location: SearchLocation) {
        guard location.kind != .appDocuments else { return }
        stopAccessing(location)
        locations.removeAll { $0.id == location.id }
        save()
    }

    public func setEnabled(_ enabled: Bool, for location: SearchLocation) {
        update(location.id) { $0.isEnabled = enabled }
    }

    public func markIndexed(_ locationID: String, itemCount: Int, date: Date = Date()) {
        update(locationID) {
            $0.lastIndexed = date
            $0.itemCount = itemCount
        }
    }

    /// Resolves the bookmark of a location and starts security-scoped access.
    /// Call `stopAccessing(_:)` when done (or keep access for the app lifetime).
    public func beginAccessing(_ location: SearchLocation) throws -> URL {
        if let url = accessedURLs[location.id] { return url }
        guard location.kind == .userSelected, let bookmarkData = location.bookmarkData else {
            return location.url
        }
        var isStale = false
        let url: URL
        do {
            url = try LocationStore.resolveBookmark(bookmarkData, isStale: &isStale)
        } catch {
            Log.persistence.error("Bookmark for \(location.name) could not be resolved: \(error.localizedDescription)")
            throw FileFinderError.bookmarkResolutionFailed(name: location.name)
        }
        let didStart = url.startAccessingSecurityScopedResource()
        if didStart { accessedURLs[location.id] = url }
        if isStale, let refreshed = try? LocationStore.makeBookmark(for: url) {
            update(location.id) {
                $0.bookmarkData = refreshed
                $0.path = url.standardizedFileURL.path
            }
        }
        return url
    }

    public func stopAccessing(_ location: SearchLocation) {
        if let url = accessedURLs.removeValue(forKey: location.id) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public func stopAccessingAll() {
        for url in accessedURLs.values { url.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll()
    }

    /// Returns the location that contains `path`, preferring the most specific one.
    public func location(containing path: String) -> SearchLocation? {
        let standardized = (path as NSString).standardizingPath
        return locations
            .filter { standardized == $0.path || standardized.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    private func update(_ id: String, _ change: (inout SearchLocation) -> Void) {
        guard let index = locations.firstIndex(where: { $0.id == id }) else { return }
        change(&locations[index])
        save()
    }

    private func save() {
        store.encode(locations, forKey: LocationStore.storageKey)
    }

    // MARK: - Bookmarks

    static func makeBookmark(for url: URL) throws -> Data? {
        #if canImport(Darwin)
        #if os(macOS)
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        #else
        // Bookmarks are not supported outside Apple platforms; plain paths are used instead.
        return nil
        #endif
    }

    static func resolveBookmark(_ data: Data, isStale: inout Bool) throws -> URL {
        #if canImport(Darwin)
        #if os(macOS)
        return try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        #else
        throw FileFinderError.bookmarkResolutionFailed(name: "")
        #endif
    }
}

#if !canImport(Darwin)
extension URL {
    // Security-scoped resources only exist on Apple platforms.
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
#endif
