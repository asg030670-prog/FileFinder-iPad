import Foundation
#if canImport(Combine)
import Combine
#endif

/// Drives the file detail screen: metadata, text preview, favorites and quick actions
/// (copy, move, rename, delete). Sharing and QuickLook are handled by the view.
@MainActor
public final class FileDetailViewModel: ObservableObject {
    @Published public private(set) var item: FileItem
    @Published public private(set) var metadata: [MetadataEntry] = []
    @Published public private(set) var textPreview: String?
    @Published public private(set) var isFavorite: Bool
    @Published public private(set) var isDeleted = false
    @Published public var errorMessage: String?
    @Published public private(set) var statusMessage: String?

    public let environment: AppEnvironment
    /// Called after the item was deleted, renamed or moved (old path, new item or `nil` if deleted).
    public var onItemChanged: ((String, FileItem?) -> Void)?

    public init(item: FileItem, environment: AppEnvironment) {
        self.item = item
        self.environment = environment
        self.isFavorite = environment.favoritesStore.isFavorite(path: item.path)
    }

    public var locationName: String? { environment.locationName(for: item) }

    public var canPreviewText: Bool { environment.previewService.canPreviewText(item) }

    /// Loads metadata and the text preview (off the main thread).
    public func load() async {
        let item = self.item
        let service = environment.previewService
        let locationName = self.locationName
        let loaded = await Task.detached(priority: .userInitiated) { () -> ([MetadataEntry], String?) in
            let metadata = service.metadata(for: item, locationName: locationName)
            let preview = service.canPreviewText(item) ? try? service.textPreview(for: item) : nil
            return (metadata, preview)
        }.value
        guard item == self.item else { return }
        metadata = loaded.0
        textPreview = loaded.1
    }

    public func toggleFavorite() {
        isFavorite = environment.favoritesStore.toggle(item)
    }

    // MARK: - Quick actions

    public func copy(to folder: URL) async {
        await perform("Copied to \(folder.lastPathComponent)", folder: folder) { [operations = environment.fileOperations, item] in
            let destination = try operations.copy(item.url, into: folder)
            await self.environment.registerChange(at: destination)
        }
    }

    public func move(to folder: URL) async {
        await perform("Moved to \(folder.lastPathComponent)", folder: folder) { [operations = environment.fileOperations, item] in
            let destination = try operations.move(item.url, into: folder)
            guard destination.standardizedFileURL.path != item.path else { return }
            await self.environment.registerChange(at: destination, replacing: item.path)
            self.updateItem(from: destination, oldPath: item.path)
        }
    }

    public func rename(to newName: String) async {
        await perform("Renamed to \(newName)") { [operations = environment.fileOperations, item] in
            let destination = try operations.rename(item.url, to: newName)
            guard destination.standardizedFileURL.path != item.path else { return }
            await self.environment.registerChange(at: destination, replacing: item.path)
            self.updateItem(from: destination, oldPath: item.path)
        }
    }

    public func delete() async {
        await perform("Deleted \(item.name)") { [operations = environment.fileOperations, item] in
            try operations.delete(item.url)
            await self.environment.registerDeletion(of: item.path)
            self.isFavorite = false
            self.isDeleted = true
            self.onItemChanged?(item.path, nil)
        }
    }

    private func updateItem(from url: URL, oldPath: String) {
        let locationID = environment.locationStore.location(containing: url.path)?.id
        guard let newItem = try? FileItem(url: url, locationID: locationID) else { return }
        if environment.favoritesStore.isFavorite(path: oldPath) {
            environment.favoritesStore.updatePath(from: oldPath, to: newItem)
        }
        item = newItem
        isFavorite = environment.favoritesStore.isFavorite(path: newItem.path)
        onItemChanged?(oldPath, newItem)
        Task { await load() }
    }

    /// Runs an operation with security-scoped access to the destination folder and reports errors.
    private func perform(_ successMessage: String, folder: URL? = nil, _ operation: () async throws -> Void) async {
        let didAccess = folder?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { folder?.stopAccessingSecurityScopedResource() } }
        do {
            try await operation()
            statusMessage = successMessage
            errorMessage = nil
        } catch {
            Log.operations.error("\(successMessage) failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
