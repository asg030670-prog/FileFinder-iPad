import Foundation

/// A bookmarked file or folder.
public struct Favorite: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    public var name: String
    public var isDirectory: Bool
    public var category: FileCategory
    public let addedAt: Date

    public init(item: FileItem, addedAt: Date = Date()) {
        self.path = item.path
        self.name = item.name
        self.isDirectory = item.isDirectory
        self.category = item.category
        self.addedAt = addedAt
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    public var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// Persists favorites (bookmarked files and folders).
public final class FavoritesStore {
    public static let storageKey = "FileFinder.favorites"

    private let store: KeyValueStore
    public private(set) var favorites: [Favorite]

    public init(store: KeyValueStore) {
        self.store = store
        self.favorites = store.decode([Favorite].self, forKey: FavoritesStore.storageKey) ?? []
    }

    public func isFavorite(path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        return favorites.contains { $0.path == standardized }
    }

    public func add(_ item: FileItem) {
        guard !isFavorite(path: item.path) else { return }
        favorites.insert(Favorite(item: item), at: 0)
        save()
    }

    public func remove(path: String) {
        let standardized = (path as NSString).standardizingPath
        favorites.removeAll { $0.path == standardized }
        save()
    }

    /// Adds or removes the item; returns the new favorite state.
    @discardableResult
    public func toggle(_ item: FileItem) -> Bool {
        if isFavorite(path: item.path) {
            remove(path: item.path)
            return false
        }
        add(item)
        return true
    }

    /// Updates a favorite after its file was renamed or moved.
    public func updatePath(from oldPath: String, to newItem: FileItem) {
        let standardized = (oldPath as NSString).standardizingPath
        guard let index = favorites.firstIndex(where: { $0.path == standardized }) else { return }
        let addedAt = favorites[index].addedAt
        favorites[index] = Favorite(item: newItem, addedAt: addedAt)
        save()
    }

    /// Removes favorites whose files no longer exist. Returns the number removed.
    @discardableResult
    public func pruneMissing() -> Int {
        let before = favorites.count
        favorites.removeAll { !$0.exists }
        if favorites.count != before { save() }
        return before - favorites.count
    }

    private func save() {
        store.encode(favorites, forKey: FavoritesStore.storageKey)
    }
}
