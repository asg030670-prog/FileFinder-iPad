import Foundation

/// Fields that the search text is compared against.
public struct SearchScope: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let fileName = SearchScope(rawValue: 1 << 0)
    public static let fileExtension = SearchScope(rawValue: 1 << 1)
    public static let content = SearchScope(rawValue: 1 << 2)

    public static let `default`: SearchScope = [.fileName, .fileExtension]
    public static let all: SearchScope = [.fileName, .fileExtension, .content]
}

/// How search results are ordered.
public enum SortField: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case relevance
    case name
    case modificationDate
    case size
    case kind

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .relevance: return "Relevance"
        case .name: return "Name"
        case .modificationDate: return "Date Modified"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }
}

public struct SortOption: Hashable, Codable, Sendable {
    public var field: SortField
    public var ascending: Bool

    public init(field: SortField = .relevance, ascending: Bool = false) {
        self.field = field
        self.ascending = ascending
    }

    public static let `default` = SortOption()
}

/// Full description of a search request. Hashable so it can be used as a cache key.
public struct SearchQuery: Hashable, Codable, Sendable {
    public var text: String
    public var scope: SearchScope
    public var filter: SearchFilter
    public var sort: SortOption
    /// Maximum number of results returned (keeps memory and UI work bounded).
    public var limit: Int

    public init(
        text: String = "",
        scope: SearchScope = .default,
        filter: SearchFilter = .none,
        sort: SortOption = .default,
        limit: Int = 2_000
    ) {
        self.text = text
        self.scope = scope
        self.filter = filter
        self.sort = sort
        self.limit = limit
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `true` when there is nothing to search for (no text and no filters).
    public var isEmpty: Bool { trimmedText.isEmpty && !filter.isActive }

    /// Parsed representation of the text.
    ///
    /// Supported syntax:
    /// - plain words: every word must appear in the name (or content when enabled)
    /// - `.pdf` or `ext:pdf`: restrict to an extension
    /// - `"exact phrase"`: phrase must appear as typed
    public var parsedTerms: ParsedSearchText { ParsedSearchText(trimmedText) }
}

/// Tokenized search text.
public struct ParsedSearchText: Hashable, Sendable {
    /// Normalized terms that must all match.
    public let terms: [String]
    /// Normalized extensions (without dot); an item must match one of them.
    public let extensions: [String]

    public init(_ text: String) {
        var terms: [String] = []
        var extensions: [String] = []

        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" {
                if inQuotes, !current.isEmpty { tokens.append(current) }
                if !inQuotes, !current.isEmpty { tokens.append(current) }
                current = ""
                inQuotes.toggle()
            } else if character.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        for token in tokens {
            let normalized = token.searchNormalized
            if normalized.hasPrefix("ext:") {
                let ext = String(normalized.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !ext.isEmpty { extensions.append(ext) }
            } else if normalized.hasPrefix("."), normalized.count > 1, !normalized.dropFirst().contains(".") {
                extensions.append(String(normalized.dropFirst()))
            } else {
                terms.append(normalized)
            }
        }
        self.terms = terms
        self.extensions = extensions
    }

    public var isEmpty: Bool { terms.isEmpty && extensions.isEmpty }
}
