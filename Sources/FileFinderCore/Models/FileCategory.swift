import Foundation

/// High level grouping of files used for filtering and iconography.
public enum FileCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case document
    case spreadsheet
    case presentation
    case image
    case video
    case audio
    case archive
    case code
    case folder
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .document: return "Documents"
        case .spreadsheet: return "Spreadsheets"
        case .presentation: return "Presentations"
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .archive: return "Archives"
        case .code: return "Code"
        case .folder: return "Folders"
        case .other: return "Other"
        }
    }

    /// SF Symbol name used by the UI.
    public var systemImage: String {
        switch self {
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle.angled"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }

    /// Lower-cased file extensions belonging to the category.
    public var extensions: Set<String> {
        switch self {
        case .document:
            return ["pdf", "doc", "docx", "txt", "rtf", "rtfd", "md", "markdown", "pages", "odt", "epub", "tex", "log"]
        case .spreadsheet:
            return ["xls", "xlsx", "csv", "tsv", "numbers", "ods"]
        case .presentation:
            return ["ppt", "pptx", "key", "odp"]
        case .image:
            return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg", "raw", "dng", "cr2", "nef", "arw", "ico", "psd"]
        case .video:
            return ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp", "mpg", "mpeg"]
        case .audio:
            return ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma", "caf", "mid", "midi"]
        case .archive:
            return ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso"]
        case .code:
            return ["swift", "m", "h", "c", "cpp", "hpp", "cs", "java", "kt", "py", "rb", "js", "ts", "jsx", "tsx",
                    "html", "htm", "css", "scss", "json", "xml", "yml", "yaml", "toml", "sh", "go", "rs", "php", "sql", "plist"]
        case .folder, .other:
            return []
        }
    }

    private static let extensionLookup: [String: FileCategory] = {
        var lookup: [String: FileCategory] = [:]
        for category in FileCategory.allCases {
            for ext in category.extensions {
                lookup[ext] = category
            }
        }
        return lookup
    }()

    /// Determines the category of a file from its extension.
    public static func category(forExtension fileExtension: String, isDirectory: Bool = false) -> FileCategory {
        if isDirectory { return .folder }
        return extensionLookup[fileExtension.lowercased()] ?? .other
    }

    /// Extensions whose contents can be read as plain text (used for content search and text previews).
    public static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "log", "tex", "rtf",
        "swift", "m", "h", "c", "cpp", "hpp", "cs", "java", "kt", "py", "rb", "js", "ts", "jsx", "tsx",
        "html", "htm", "css", "scss", "json", "xml", "yml", "yaml", "toml", "sh", "go", "rs", "php", "sql",
        "ini", "cfg", "conf", "env", "srt", "vtt"
    ]

    public static func isTextExtension(_ fileExtension: String) -> Bool {
        textExtensions.contains(fileExtension.lowercased())
    }
}
