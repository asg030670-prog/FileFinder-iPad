import Foundation

/// File size bounds in bytes (inclusive). `nil` means unbounded.
public struct SizeRange: Hashable, Codable, Sendable {
    public var minimumBytes: Int64?
    public var maximumBytes: Int64?

    public init(minimumBytes: Int64? = nil, maximumBytes: Int64? = nil) {
        self.minimumBytes = minimumBytes
        self.maximumBytes = maximumBytes
    }

    public static let any = SizeRange()
    public static let small = SizeRange(maximumBytes: 1_000_000)                       // < 1 MB
    public static let medium = SizeRange(minimumBytes: 1_000_000, maximumBytes: 100_000_000) // 1–100 MB
    public static let large = SizeRange(minimumBytes: 100_000_000, maximumBytes: 1_000_000_000) // 100 MB–1 GB
    public static let huge = SizeRange(minimumBytes: 1_000_000_000)                    // > 1 GB

    /// Presets offered by the UI.
    public static let presets: [(name: String, range: SizeRange)] = [
        ("Any size", .any),
        ("Small (< 1 MB)", .small),
        ("Medium (1–100 MB)", .medium),
        ("Large (100 MB–1 GB)", .large),
        ("Huge (> 1 GB)", .huge)
    ]

    public var isUnbounded: Bool { minimumBytes == nil && maximumBytes == nil }

    public func contains(_ size: Int64) -> Bool {
        if let minimumBytes, size < minimumBytes { return false }
        if let maximumBytes, size > maximumBytes { return false }
        return true
    }
}

/// Modification date constraint.
public enum DateFilter: Hashable, Codable, Sendable {
    case any
    case today
    case lastDays(Int)
    case custom(from: Date?, to: Date?)

    public static let presets: [(name: String, filter: DateFilter)] = [
        ("Any time", .any),
        ("Today", .today),
        ("Last 7 days", .lastDays(7)),
        ("Last 30 days", .lastDays(30)),
        ("Last year", .lastDays(365))
    ]

    /// Returns the concrete interval represented by the filter relative to `now`.
    public func interval(relativeTo now: Date, calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        switch self {
        case .any:
            return (nil, nil)
        case .today:
            return (calendar.startOfDay(for: now), nil)
        case .lastDays(let days):
            return (calendar.date(byAdding: .day, value: -days, to: now), nil)
        case .custom(let from, let to):
            return (from, to)
        }
    }

    public func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let bounds = interval(relativeTo: now, calendar: calendar)
        if let start = bounds.start, date < start { return false }
        if let end = bounds.end, date > end { return false }
        return true
    }
}

/// Combination of all filters applied to search results. Every active filter must match.
public struct SearchFilter: Hashable, Codable, Sendable {
    /// Allowed categories; empty means all categories.
    public var categories: Set<FileCategory>
    public var sizeRange: SizeRange
    public var dateFilter: DateFilter
    /// Allowed `SearchLocation` identifiers; empty means every location.
    public var locationIDs: Set<String>
    /// Optional folder path; when set only items inside it (at any depth) match.
    public var folderPath: String?
    public var includeHiddenFiles: Bool
    public var includeFolders: Bool

    public init(
        categories: Set<FileCategory> = [],
        sizeRange: SizeRange = .any,
        dateFilter: DateFilter = .any,
        locationIDs: Set<String> = [],
        folderPath: String? = nil,
        includeHiddenFiles: Bool = false,
        includeFolders: Bool = true
    ) {
        self.categories = categories
        self.sizeRange = sizeRange
        self.dateFilter = dateFilter
        self.locationIDs = locationIDs
        self.folderPath = folderPath
        self.includeHiddenFiles = includeHiddenFiles
        self.includeFolders = includeFolders
    }

    public static let none = SearchFilter()

    /// Number of active (non-default) filters, used for badges in the UI.
    public var activeFilterCount: Int {
        var count = 0
        if !categories.isEmpty { count += 1 }
        if !sizeRange.isUnbounded { count += 1 }
        if dateFilter != .any { count += 1 }
        if !locationIDs.isEmpty { count += 1 }
        if folderPath != nil { count += 1 }
        if includeHiddenFiles { count += 1 }
        if !includeFolders { count += 1 }
        return count
    }

    public var isActive: Bool { activeFilterCount > 0 }

    public func matches(_ item: FileItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if item.isHidden && !includeHiddenFiles { return false }
        if item.isDirectory && !includeFolders { return false }
        if !categories.isEmpty && !categories.contains(item.category) { return false }
        if !item.isDirectory && !sizeRange.contains(item.size) { return false }
        if !sizeRange.isUnbounded && item.isDirectory { return false }
        if !dateFilter.contains(item.modificationDate, now: now, calendar: calendar) { return false }
        if !locationIDs.isEmpty {
            guard let locationID = item.locationID, locationIDs.contains(locationID) else { return false }
        }
        if let folderPath, !item.isContained(in: folderPath) { return false }
        return true
    }
}
