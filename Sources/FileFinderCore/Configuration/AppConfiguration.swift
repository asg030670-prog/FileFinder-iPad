import Foundation

/// Tunable settings of the app. Defaults are compiled in and can be overridden by a
/// `FileFinderConfig.json` file bundled with the app (see `Config/FileFinderConfig.example.json`).
public struct AppConfiguration: Codable, Hashable, Sendable {
    /// Delay between the last keystroke and the search being executed.
    public var searchDebounceMilliseconds: Int
    /// Maximum results returned for a query.
    public var maximumResults: Int
    /// Number of cached queries.
    public var searchCacheCapacity: Int
    /// Number of search history entries kept.
    public var maximumHistoryEntries: Int
    /// Text files larger than this are not searched by content.
    public var maximumContentSearchFileSize: Int64
    /// Maximum files read per content search.
    public var maximumContentSearchFiles: Int
    /// Search file contents by default.
    public var contentSearchEnabledByDefault: Bool
    /// Include hidden files while indexing.
    public var indexHiddenFiles: Bool
    /// Folder names that are never indexed.
    public var excludedDirectoryNames: [String]
    /// Minimum time between automatic re-indexing runs.
    public var reindexIntervalMinutes: Int
    /// Number of characters shown in text previews.
    public var maximumPreviewCharacters: Int

    public init(
        searchDebounceMilliseconds: Int = 250,
        maximumResults: Int = 2_000,
        searchCacheCapacity: Int = 50,
        maximumHistoryEntries: Int = 30,
        maximumContentSearchFileSize: Int64 = 10_000_000,
        maximumContentSearchFiles: Int = 5_000,
        contentSearchEnabledByDefault: Bool = false,
        indexHiddenFiles: Bool = false,
        excludedDirectoryNames: [String] = Array(ScanOptions.defaultExcludedDirectoryNames).sorted(),
        reindexIntervalMinutes: Int = 15,
        maximumPreviewCharacters: Int = 5_000
    ) {
        self.searchDebounceMilliseconds = searchDebounceMilliseconds
        self.maximumResults = maximumResults
        self.searchCacheCapacity = searchCacheCapacity
        self.maximumHistoryEntries = maximumHistoryEntries
        self.maximumContentSearchFileSize = maximumContentSearchFileSize
        self.maximumContentSearchFiles = maximumContentSearchFiles
        self.contentSearchEnabledByDefault = contentSearchEnabledByDefault
        self.indexHiddenFiles = indexHiddenFiles
        self.excludedDirectoryNames = excludedDirectoryNames
        self.reindexIntervalMinutes = reindexIntervalMinutes
        self.maximumPreviewCharacters = maximumPreviewCharacters
    }

    public static let `default` = AppConfiguration()

    private enum CodingKeys: String, CodingKey {
        case searchDebounceMilliseconds, maximumResults, searchCacheCapacity, maximumHistoryEntries,
             maximumContentSearchFileSize, maximumContentSearchFiles, contentSearchEnabledByDefault,
             indexHiddenFiles, excludedDirectoryNames, reindexIntervalMinutes, maximumPreviewCharacters
    }

    /// Decodes a configuration; missing keys fall back to defaults so partial files are valid.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfiguration()
        searchDebounceMilliseconds = try container.decodeIfPresent(Int.self, forKey: .searchDebounceMilliseconds) ?? defaults.searchDebounceMilliseconds
        maximumResults = try container.decodeIfPresent(Int.self, forKey: .maximumResults) ?? defaults.maximumResults
        searchCacheCapacity = try container.decodeIfPresent(Int.self, forKey: .searchCacheCapacity) ?? defaults.searchCacheCapacity
        maximumHistoryEntries = try container.decodeIfPresent(Int.self, forKey: .maximumHistoryEntries) ?? defaults.maximumHistoryEntries
        maximumContentSearchFileSize = try container.decodeIfPresent(Int64.self, forKey: .maximumContentSearchFileSize) ?? defaults.maximumContentSearchFileSize
        maximumContentSearchFiles = try container.decodeIfPresent(Int.self, forKey: .maximumContentSearchFiles) ?? defaults.maximumContentSearchFiles
        contentSearchEnabledByDefault = try container.decodeIfPresent(Bool.self, forKey: .contentSearchEnabledByDefault) ?? defaults.contentSearchEnabledByDefault
        indexHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .indexHiddenFiles) ?? defaults.indexHiddenFiles
        excludedDirectoryNames = try container.decodeIfPresent([String].self, forKey: .excludedDirectoryNames) ?? defaults.excludedDirectoryNames
        reindexIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .reindexIntervalMinutes) ?? defaults.reindexIntervalMinutes
        maximumPreviewCharacters = try container.decodeIfPresent(Int.self, forKey: .maximumPreviewCharacters) ?? defaults.maximumPreviewCharacters
    }

    public static func load(from data: Data) throws -> AppConfiguration {
        try JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    /// Loads `FileFinderConfig.json` from `bundle`, falling back to defaults.
    public static func load(bundle: Bundle = .main, resourceName: String = "FileFinderConfig") -> AppConfiguration {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else { return .default }
        do {
            let configuration = try load(from: Data(contentsOf: url))
            Log.persistence.info("Loaded configuration from \(url.lastPathComponent)")
            return configuration
        } catch {
            Log.persistence.error("Invalid configuration file, using defaults: \(error.localizedDescription)")
            return .default
        }
    }

    public var scanOptions: ScanOptions {
        ScanOptions(includeHiddenFiles: indexHiddenFiles, excludedDirectoryNames: Set(excludedDirectoryNames))
    }
}
