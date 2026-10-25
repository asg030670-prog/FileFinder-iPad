import Foundation

/// Where a search term was found.
public enum MatchKind: String, Codable, Hashable, Sendable {
    case fileName
    case fileExtension
    case content
    case filterOnly
}

/// A file matching a query, with ranking information.
public struct SearchResult: Identifiable, Hashable, Sendable {
    public let item: FileItem
    public let matchKind: MatchKind
    /// Higher is better.
    public let score: Double
    /// Excerpt around the first content match, if any.
    public let contentSnippet: String?

    public var id: String { item.id }

    public init(item: FileItem, matchKind: MatchKind, score: Double, contentSnippet: String? = nil) {
        self.item = item
        self.matchKind = matchKind
        self.score = score
        self.contentSnippet = contentSnippet
    }
}
