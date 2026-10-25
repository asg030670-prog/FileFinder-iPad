import Foundation

/// In-memory index of every known file, grouped by location.
///
/// The index is an actor so it can be updated from background indexing tasks while
/// searches read from it concurrently. Each mutation bumps `generation`, which the
/// search cache uses to invalidate stale results.
public actor FileIndex {
    private var itemsByLocation: [String: [FileItem]] = [:]
    private var lastIndexedByLocation: [String: Date] = [:]
    public private(set) var generation: Int = 0

    private let persistence: IndexPersistence?

    public init(persistence: IndexPersistence? = nil) {
        self.persistence = persistence
    }

    /// All indexed items (across all locations).
    public var allItems: [FileItem] {
        itemsByLocation.values.flatMap { $0 }
    }

    public var count: Int {
        itemsByLocation.values.reduce(0) { $0 + $1.count }
    }

    public func items(in locationID: String) -> [FileItem] {
        itemsByLocation[locationID] ?? []
    }

    public func lastIndexed(locationID: String) -> Date? {
        lastIndexedByLocation[locationID]
    }

    public var indexedLocationIDs: Set<String> { Set(itemsByLocation.keys) }

    /// Replaces the items of a location (after a full scan).
    public func replaceItems(_ items: [FileItem], for locationID: String, date: Date = Date()) {
        itemsByLocation[locationID] = items
        lastIndexedByLocation[locationID] = date
        generation += 1
        Log.index.info("Index updated for location \(locationID): \(items.count) items (generation \(generation))")
    }

    /// Adds or updates a single item (e.g. after a copy/move operation).
    public func upsert(_ item: FileItem) {
        let key = item.locationID ?? ""
        var items = itemsByLocation[key] ?? []
        if let index = items.firstIndex(where: { $0.path == item.path }) {
            items[index] = item
        } else {
            items.append(item)
        }
        itemsByLocation[key] = items
        generation += 1
    }

    /// Removes an item and, if it is a folder, everything inside it.
    public func remove(path: String) {
        let standardized = (path as NSString).standardizingPath
        let prefix = standardized + "/"
        var changed = false
        for (key, items) in itemsByLocation {
            let filtered = items.filter { $0.path != standardized && !$0.path.hasPrefix(prefix) }
            if filtered.count != items.count {
                itemsByLocation[key] = filtered
                changed = true
            }
        }
        if changed { generation += 1 }
    }

    public func removeLocation(_ locationID: String) {
        if itemsByLocation.removeValue(forKey: locationID) != nil {
            generation += 1
        }
        lastIndexedByLocation.removeValue(forKey: locationID)
    }

    public func removeAll() {
        itemsByLocation.removeAll()
        lastIndexedByLocation.removeAll()
        generation += 1
    }

    // MARK: - Persistence

    /// Saves the current index to disk so the next launch can search immediately.
    public func save() {
        guard let persistence else { return }
        let snapshot = IndexSnapshot(itemsByLocation: itemsByLocation, lastIndexedByLocation: lastIndexedByLocation)
        do {
            try persistence.save(snapshot)
        } catch {
            Log.index.error("Failed to save index: \(error.localizedDescription)")
        }
    }

    /// Restores a previously saved index. Returns `true` when a snapshot was loaded.
    @discardableResult
    public func load() -> Bool {
        guard let persistence else { return false }
        do {
            guard let snapshot = try persistence.load() else { return false }
            itemsByLocation = snapshot.itemsByLocation
            lastIndexedByLocation = snapshot.lastIndexedByLocation
            generation += 1
            Log.index.info("Loaded cached index with \(count) items")
            return true
        } catch {
            Log.index.error("Failed to load cached index: \(error.localizedDescription)")
            return false
        }
    }
}

/// Serializable form of the index.
public struct IndexSnapshot: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var itemsByLocation: [String: [FileItem]]
    public var lastIndexedByLocation: [String: Date]

    public init(itemsByLocation: [String: [FileItem]], lastIndexedByLocation: [String: Date]) {
        self.version = IndexSnapshot.currentVersion
        self.itemsByLocation = itemsByLocation
        self.lastIndexedByLocation = lastIndexedByLocation
    }
}

/// Stores index snapshots as compact binary property lists in the Caches directory.
public struct IndexPersistence: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: `<Caches>/FileFinder/index.plist`.
    public static func `default`() -> IndexPersistence {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return IndexPersistence(fileURL: caches.appendingPathComponent("FileFinder", isDirectory: true).appendingPathComponent("index.plist"))
    }

    public func save(_ snapshot: IndexSnapshot) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> IndexSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try PropertyListDecoder().decode(IndexSnapshot.self, from: data)
        guard snapshot.version == IndexSnapshot.currentVersion else {
            Log.index.notice("Discarding index snapshot with unsupported version \(snapshot.version)")
            return nil
        }
        return snapshot
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
