import Foundation

/// A previously executed search.
public struct SearchHistoryEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: String { text.searchNormalized }
    public let text: String
    public let date: Date
    public let resultCount: Int

    public init(text: String, date: Date = Date(), resultCount: Int = 0) {
        self.text = text
        self.date = date
        self.resultCount = resultCount
    }
}

/// Persists recent searches (most recent first, de-duplicated case-insensitively).
public final class SearchHistoryStore {
    public static let storageKey = "FileFinder.searchHistory"

    private let store: KeyValueStore
    public let maximumEntries: Int
    public private(set) var entries: [SearchHistoryEntry]

    public init(store: KeyValueStore, maximumEntries: Int = 30) {
        self.store = store
        self.maximumEntries = max(1, maximumEntries)
        self.entries = store.decode([SearchHistoryEntry].self, forKey: SearchHistoryStore.storageKey) ?? []
    }

    /// Records a search. Blank text is ignored.
    public func record(_ text: String, resultCount: Int = 0, date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = SearchHistoryEntry(text: trimmed, date: date, resultCount: resultCount)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }
        save()
    }

    public func remove(_ entry: SearchHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    /// History entries starting with / containing `prefix`, used for search suggestions.
    public func suggestions(matching prefix: String, limit: Int = 8) -> [SearchHistoryEntry] {
        let normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines).searchNormalized
        guard !normalized.isEmpty else { return Array(entries.prefix(limit)) }
        return Array(entries.filter { $0.id.contains(normalized) && $0.id != normalized }.prefix(limit))
    }

    private func save() {
        store.encode(entries, forKey: SearchHistoryStore.storageKey)
    }
}
