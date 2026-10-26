import Foundation

/// A labelled metadata value shown in the detail view.
public struct MetadataEntry: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Produces text previews and metadata for files. Thumbnails are produced by the UI layer
/// using QuickLook, which is only available on Apple platforms.
public struct FilePreviewService: Sendable {
    public var maximumPreviewCharacters: Int
    private let contentSearcher: ContentSearcher

    public init(maximumPreviewCharacters: Int = 5_000, contentSearcher: ContentSearcher = ContentSearcher()) {
        self.maximumPreviewCharacters = maximumPreviewCharacters
        self.contentSearcher = contentSearcher
    }

    public func canPreviewText(_ item: FileItem) -> Bool {
        item.isTextReadable
    }

    /// First `maximumPreviewCharacters` characters of a text file.
    public func textPreview(for item: FileItem) throws -> String {
        guard canPreviewText(item) else { throw FileFinderError.unreadableContent(path: item.path) }
        // UTF-8 uses at most 4 bytes per character.
        let text = try contentSearcher.readText(at: item.url, maximumBytes: maximumPreviewCharacters * 4)
        if text.count > maximumPreviewCharacters {
            return String(text.prefix(maximumPreviewCharacters)) + "\n…"
        }
        return text
    }

    /// Human readable metadata for the item.
    public func metadata(for item: FileItem, locationName: String? = nil, dateFormatter: DateFormatter = FilePreviewService.defaultDateFormatter) -> [MetadataEntry] {
        var entries: [MetadataEntry] = [
            MetadataEntry(label: "Name", value: item.name),
            MetadataEntry(label: "Kind", value: item.isDirectory ? "Folder" : kindDescription(for: item))
        ]
        if item.isDirectory {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: item.path).count) ?? 0
            entries.append(MetadataEntry(label: "Items", value: "\(count)"))
        } else {
            entries.append(MetadataEntry(label: "Size", value: "\(item.formattedSize) (\(item.size) bytes)"))
        }
        if let creationDate = item.creationDate {
            entries.append(MetadataEntry(label: "Created", value: dateFormatter.string(from: creationDate)))
        }
        entries.append(MetadataEntry(label: "Modified", value: dateFormatter.string(from: item.modificationDate)))
        if let locationName {
            entries.append(MetadataEntry(label: "Location", value: locationName))
        }
        entries.append(MetadataEntry(label: "Folder", value: item.parentPath))
        if let attributes = try? FileManager.default.attributesOfItem(atPath: item.path),
           let permissions = attributes[.posixPermissions] as? NSNumber {
            entries.append(MetadataEntry(label: "Permissions", value: String(permissions.intValue, radix: 8)))
        }
        return entries
    }

    public func kindDescription(for item: FileItem) -> String {
        if item.fileExtension.isEmpty { return item.category.displayName }
        return "\(item.fileExtension.uppercased()) – \(item.category.displayName)"
    }

    public static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
