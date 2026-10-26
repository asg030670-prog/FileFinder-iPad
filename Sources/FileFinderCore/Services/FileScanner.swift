import Foundation

/// Options controlling a directory traversal.
public struct ScanOptions: Sendable, Hashable {
    public var includeHiddenFiles: Bool
    /// Maximum folder depth below the root (`nil` = unlimited).
    public var maximumDepth: Int?
    /// Folder names that are never descended into (e.g. `.Trash`, `node_modules`).
    public var excludedDirectoryNames: Set<String>
    /// Treat packages (e.g. `.pages`, `.rtfd`) as single files.
    public var skipPackageContents: Bool
    /// Number of items delivered per progress callback.
    public var batchSize: Int

    public init(
        includeHiddenFiles: Bool = false,
        maximumDepth: Int? = nil,
        excludedDirectoryNames: Set<String> = ScanOptions.defaultExcludedDirectoryNames,
        skipPackageContents: Bool = true,
        batchSize: Int = 500
    ) {
        self.includeHiddenFiles = includeHiddenFiles
        self.maximumDepth = maximumDepth
        self.excludedDirectoryNames = excludedDirectoryNames
        self.skipPackageContents = skipPackageContents
        self.batchSize = max(1, batchSize)
    }

    public static let defaultExcludedDirectoryNames: Set<String> = [".Trash", ".git", "node_modules", ".build", "DerivedData"]
}

/// Progress information reported while scanning.
public struct ScanProgress: Sendable, Hashable {
    public var scannedItems: Int
    public var skippedItems: Int
    public var currentPath: String?

    public init(scannedItems: Int = 0, skippedItems: Int = 0, currentPath: String? = nil) {
        self.scannedItems = scannedItems
        self.skippedItems = skippedItems
        self.currentPath = currentPath
    }
}

/// Recursively walks folders using `FileManager` and produces `FileItem`s.
///
/// The scanner is cancellation aware (checks `Task.isCancelled`) and never throws for
/// individual unreadable entries; those are logged and counted as skipped instead.
public struct FileScanner: Sendable {
    public var options: ScanOptions

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    static let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey, .isHiddenKey, .isPackageKey
    ]

    /// Scans `root` recursively.
    /// - Parameters:
    ///   - root: Folder to traverse.
    ///   - locationID: Identifier stored in every produced item.
    ///   - onBatch: Called with batches of discovered items (useful for incremental UI updates).
    /// - Returns: All discovered items.
    @discardableResult
    public func scan(
        root: URL,
        locationID: String? = nil,
        onBatch: (([FileItem], ScanProgress) -> Void)? = nil
    ) throws -> [FileItem] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw FileFinderError.fileNotFound(path: root.path)
        }
        guard isDirectory.boolValue else {
            throw FileFinderError.invalidDestination(path: root.path)
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            throw FileFinderError.accessDenied(path: root.path)
        }

        var enumeratorOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHiddenFiles { enumeratorOptions.insert(.skipsHiddenFiles) }
        if options.skipPackageContents { enumeratorOptions.insert(.skipsPackageDescendants) }

        let skippedCounter = Counter()
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: FileScanner.resourceKeys,
            options: enumeratorOptions,
            errorHandler: { url, error in
                Log.scanner.warning("Skipping \(url.lastPathComponent): \(error.localizedDescription)")
                skippedCounter.increment()
                return true
            }
        ) else {
            throw FileFinderError.accessDenied(path: root.path)
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count
        var items: [FileItem] = []
        var batch: [FileItem] = []
        batch.reserveCapacity(options.batchSize)
        let startDate = Date()

        Log.scanner.info("Scanning \(root.lastPathComponent)")

        var locallySkipped = 0

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                Log.scanner.notice("Scan of \(root.lastPathComponent) cancelled after \(items.count) items")
                throw FileFinderError.cancelled
            }

            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(FileScanner.resourceKeys))
            } catch {
                locallySkipped += 1
                Log.scanner.debug("Cannot read attributes of \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            let name = url.lastPathComponent
            let isDir = values.isDirectory ?? false
            let isHidden = values.isHidden ?? name.hasPrefix(".")

            if !options.includeHiddenFiles && isHidden {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir && options.excludedDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            if let maximumDepth = options.maximumDepth, isDir, depth >= maximumDepth {
                enumerator.skipDescendants()
            }
            if options.skipPackageContents, values.isPackage == true {
                enumerator.skipDescendants()
            }

            let treatAsFile = isDir && options.skipPackageContents && values.isPackage == true
            let item = FileItem(
                path: url.path,
                name: name,
                size: Int64(values.fileSize ?? 0),
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                isDirectory: isDir && !treatAsFile,
                isHidden: isHidden,
                locationID: locationID
            )
            items.append(item)

            if let onBatch {
                batch.append(item)
                if batch.count >= options.batchSize {
                    onBatch(batch, ScanProgress(scannedItems: items.count, skippedItems: skippedCounter.value + locallySkipped, currentPath: item.parentPath))
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }

        if let onBatch, !batch.isEmpty {
            onBatch(batch, ScanProgress(scannedItems: items.count, skippedItems: skippedCounter.value + locallySkipped, currentPath: nil))
        }

        let elapsed = Date().timeIntervalSince(startDate)
        Log.scanner.info("Scanned \(items.count) items in \(root.lastPathComponent) (\(skippedCounter.value + locallySkipped) skipped) in \(String(format: "%.2f", elapsed))s")
        return items
    }
}

/// Thread-safe counter used by the enumerator error handler.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock(); _value += 1; lock.unlock()
    }
}
