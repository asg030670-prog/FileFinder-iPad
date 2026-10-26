import Foundation

/// Result of indexing a single location.
public struct IndexingOutcome: Sendable, Hashable {
    public let locationID: String
    public let itemCount: Int
    public let duration: TimeInterval
    public let errorDescription: String?

    public var succeeded: Bool { errorDescription == nil }
}

/// Runs file system scans on a low-priority background task and stores the results in the `FileIndex`.
public final class IndexingService: Sendable {
    public let index: FileIndex
    public let scanner: FileScanner

    public init(index: FileIndex, scanner: FileScanner = FileScanner()) {
        self.index = index
        self.scanner = scanner
    }

    /// Scans `root` (off the main thread, `.utility` priority) and replaces the location's items in the index.
    /// - Parameter onProgress: Called periodically with the number of items found so far.
    public func indexLocation(
        id locationID: String,
        root: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> IndexingOutcome {
        let scanner = self.scanner
        let startDate = Date()
        let scanTask = Task.detached(priority: .utility) { () throws -> [FileItem] in
            try scanner.scan(root: root, locationID: locationID) { _, progress in
                onProgress?(progress.scannedItems)
            }
        }
        do {
            let items = try await withTaskCancellationHandler {
                try await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            await index.replaceItems(items, for: locationID)
            return IndexingOutcome(locationID: locationID, itemCount: items.count, duration: Date().timeIntervalSince(startDate), errorDescription: nil)
        } catch {
            Log.index.error("Indexing \(root.lastPathComponent) failed: \(error.localizedDescription)")
            return IndexingOutcome(locationID: locationID, itemCount: 0, duration: Date().timeIntervalSince(startDate), errorDescription: error.localizedDescription)
        }
    }
}
