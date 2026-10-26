import Foundation

/// Immutable snapshot of a file system item discovered by the scanner.
///
/// Kept intentionally small (no thumbnails or contents) so that indexes with
/// hundreds of thousands of entries stay memory efficient.
public struct FileItem: Identifiable, Hashable, Codable, Sendable {
    /// Standardized absolute path; unique per item.
    public let path: String
    public let name: String
    public let fileExtension: String
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date
    public let isDirectory: Bool
    public let isHidden: Bool
    public let category: FileCategory
    /// Identifier of the `SearchLocation` the item was found in.
    public let locationID: String?

    public var id: String { path }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    /// Path of the folder that contains the item.
    public var parentPath: String { (path as NSString).deletingLastPathComponent }

    /// Name of the folder that contains the item.
    public var parentName: String { (parentPath as NSString).lastPathComponent }

    public var formattedSize: String { ByteSizeFormatter.string(fromBytes: size) }

    /// Pre-computed normalized name used by the search engine.
    public var normalizedName: String { name.searchNormalized }

    public var isTextReadable: Bool { !isDirectory && FileCategory.isTextExtension(fileExtension) }

    public init(
        path: String,
        name: String? = nil,
        size: Int64,
        creationDate: Date? = nil,
        modificationDate: Date,
        isDirectory: Bool = false,
        isHidden: Bool? = nil,
        locationID: String? = nil
    ) {
        let standardized = (path as NSString).standardizingPath
        let resolvedName = name ?? (standardized as NSString).lastPathComponent
        self.path = standardized
        self.name = resolvedName
        self.fileExtension = isDirectory ? "" : (resolvedName as NSString).pathExtension.lowercased()
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.isHidden = isHidden ?? resolvedName.hasPrefix(".")
        self.category = FileCategory.category(forExtension: self.fileExtension, isDirectory: isDirectory)
        self.locationID = locationID
    }

    /// Reads the attributes of the file at `url` from disk.
    public init(url: URL, locationID: String? = nil) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey, .isHiddenKey]
        let values = try url.resourceValues(forKeys: keys)
        self.init(
            path: url.path,
            size: Int64(values.fileSize ?? 0),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
            isDirectory: values.isDirectory ?? false,
            isHidden: values.isHidden,
            locationID: locationID
        )
    }

    /// Returns `true` when the item is located inside `folderPath` (at any depth).
    public func isContained(in folderPath: String) -> Bool {
        let folder = (folderPath as NSString).standardizingPath
        if folder == "/" { return true }
        return path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
