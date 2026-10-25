import Foundation
#if canImport(Combine)
import Combine
#endif

/// Lists and manages favorite (bookmarked) files and folders.
@MainActor
public final class FavoritesViewModel: ObservableObject {
    @Published public private(set) var favorites: [Favorite] = []

    public let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        reload()
    }

    public func reload() {
        favorites = environment.favoritesStore.favorites
    }

    public func remove(_ favorite: Favorite) {
        environment.favoritesStore.remove(path: favorite.path)
        reload()
    }

    public func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where favorites.indices.contains(index) {
            environment.favoritesStore.remove(path: favorites[index].path)
        }
        reload()
    }

    /// Removes favorites whose files were deleted outside the app.
    @discardableResult
    public func pruneMissing() -> Int {
        let removed = environment.favoritesStore.pruneMissing()
        reload()
        return removed
    }

    /// Current file information for a favorite, or `nil` if it no longer exists.
    public func item(for favorite: Favorite) -> FileItem? {
        let locationID = environment.locationStore.location(containing: favorite.path)?.id
        return try? FileItem(url: favorite.url, locationID: locationID)
    }
}
