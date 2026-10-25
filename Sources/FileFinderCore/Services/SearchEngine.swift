import Foundation

/// Executes `SearchQuery`s against the `FileIndex`.
///
/// Matching rules:
/// - every term must be found in the file name (case and diacritic insensitive), or in the
///   file contents when `SearchScope.content` is enabled;
/// - `.ext` / `ext:ext` tokens restrict results to those extensions;
/// - a term equal to the file extension also matches when `SearchScope.fileExtension` is set;
/// - all filters of `SearchQuery.filter` must match.
public final class SearchEngine: Sendable {
    public let index: FileIndex
    public let cache: SearchCache
    public let contentSearcher: ContentSearcher
    /// Upper bound of files whose contents are read per query.
    public let maximumContentSearchFiles: Int

    public init(
        index: FileIndex,
        cache: SearchCache = SearchCache(),
        contentSearcher: ContentSearcher = ContentSearcher(),
        maximumContentSearchFiles: Int = 5_000
    ) {
        self.index = index
        self.cache = cache
        self.contentSearcher = contentSearcher
        self.maximumContentSearchFiles = maximumContentSearchFiles
    }

    public func search(_ query: SearchQuery, now: Date = Date()) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let generation = await index.generation
        let cacheKey = SearchCache.Key(query: query, generation: generation)
        if let cached = cache.results(for: cacheKey) {
            Log.search.debug("Cache hit for “\(query.trimmedText)” (\(cached.count) results)")
            return cached
        }

        let startDate = Date()
        let items = await index.allItems
        let parsed = query.parsedTerms
        var results: [SearchResult] = []
        var contentCandidates: [FileItem] = []

        for (offset, item) in items.enumerated() {
            if offset % 1_000 == 0 { try Task.checkCancellation() }
            guard query.filter.matches(item, now: now) else { continue }

            if !parsed.extensions.isEmpty && !parsed.extensions.contains(item.fileExtension) {
                continue
            }
            if parsed.terms.isEmpty {
                let kind: MatchKind = parsed.extensions.isEmpty ? .filterOnly : .fileExtension
                results.append(SearchResult(item: item, matchKind: kind, score: 1))
                continue
            }
            if let (kind, score) = SearchEngine.nameMatch(terms: parsed.terms, item: item, scope: query.scope) {
                results.append(SearchResult(item: item, matchKind: kind, score: score))
            } else if query.scope.contains(.content), contentSearcher.canSearch(item) {
                contentCandidates.append(item)
            }
        }

        if !contentCandidates.isEmpty {
            if contentCandidates.count > maximumContentSearchFiles {
                Log.search.notice("Content search limited to \(maximumContentSearchFiles) of \(contentCandidates.count) files")
                contentCandidates.sort { $0.modificationDate > $1.modificationDate }
                contentCandidates = Array(contentCandidates.prefix(maximumContentSearchFiles))
            }
            results += try await searchContents(of: contentCandidates, terms: parsed.terms)
        }

        let sorted = SearchEngine.sort(results, by: query.sort)
        let limited = Array(sorted.prefix(max(0, query.limit)))
        cache.store(limited, for: cacheKey)

        let elapsed = Date().timeIntervalSince(startDate)
        Log.search.info("Search “\(query.trimmedText)” matched \(results.count) of \(items.count) items in \(String(format: "%.3f", elapsed))s")
        return limited
    }

    /// Reads candidate files concurrently (bounded parallelism) looking for all terms.
    private func searchContents(of candidates: [FileItem], terms: [String]) async throws -> [SearchResult] {
        let searcher = contentSearcher
        let parallelism = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
        var results: [SearchResult] = []
        try await withThrowingTaskGroup(of: SearchResult?.self) { group in
            var iterator = candidates.makeIterator()
            func addNext() -> Bool {
                guard let item = iterator.next() else { return false }
                group.addTask(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let snippet = searcher.match(terms: terms, in: item) else { return nil }
                    return SearchResult(item: item, matchKind: .content, score: 20, contentSnippet: snippet)
                }
                return true
            }
            for _ in 0..<parallelism where !addNext() { break }
            while let result = try await group.next() {
                if let result { results.append(result) }
                _ = addNext()
            }
        }
        return results
    }

    // MARK: - Matching & ranking

    /// Returns the match kind and score if every term matches the item's name or extension.
    static func nameMatch(terms: [String], item: FileItem, scope: SearchScope) -> (MatchKind, Double)? {
        let name = item.normalizedName
        let baseName = (name as NSString).deletingPathExtension
        var total = 0.0
        var kind = MatchKind.fileName

        for term in terms {
            if scope.contains(.fileName), let score = score(term: term, name: name, baseName: baseName) {
                total += score
            } else if scope.contains(.fileExtension), !item.fileExtension.isEmpty, term == item.fileExtension {
                total += 30
                if terms.count == 1 { kind = .fileExtension }
            } else {
                return nil
            }
        }
        // Prefer shorter names (more specific matches) and files over folders slightly.
        let lengthPenalty = min(Double(name.count) / 10, 10)
        return (kind, total / Double(terms.count) - lengthPenalty)
    }

    static func score(term: String, name: String, baseName: String) -> Double? {
        if baseName == term || name == term { return 100 }
        guard let range = name.range(of: term) else { return nil }
        if range.lowerBound == name.startIndex { return 80 }
        let previous = name[name.index(before: range.lowerBound)]
        if !previous.isLetter && !previous.isNumber { return 60 }
        return 40
    }

    public static func sort(_ results: [SearchResult], by option: SortOption) -> [SearchResult] {
        func nameOrder(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
            let comparison = lhs.item.name.compare(rhs.item.name, options: [.caseInsensitive, .numeric, .diacriticInsensitive])
            if comparison == .orderedSame { return lhs.item.path < rhs.item.path }
            return comparison == .orderedAscending
        }

        switch option.field {
        case .relevance:
            return results.sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return option.ascending ? lhs.score < rhs.score : lhs.score > rhs.score
                }
                if lhs.item.modificationDate != rhs.item.modificationDate {
                    return lhs.item.modificationDate > rhs.item.modificationDate
                }
                return nameOrder(lhs, rhs)
            }
        case .name:
            return results.sorted { option.ascending ? nameOrder($0, $1) : nameOrder($1, $0) }
        case .modificationDate:
            return results.sorted { lhs, rhs in
                if lhs.item.modificationDate == rhs.item.modificationDate { return nameOrder(lhs, rhs) }
                return option.ascending
                    ? lhs.item.modificationDate < rhs.item.modificationDate
                    : lhs.item.modificationDate > rhs.item.modificationDate
            }
        case .size:
            return results.sorted { lhs, rhs in
                if lhs.item.size == rhs.item.size { return nameOrder(lhs, rhs) }
                return option.ascending ? lhs.item.size < rhs.item.size : lhs.item.size > rhs.item.size
            }
        case .kind:
            return results.sorted { lhs, rhs in
                let lhsKey = (lhs.item.category.displayName, lhs.item.fileExtension)
                let rhsKey = (rhs.item.category.displayName, rhs.item.fileExtension)
                if lhsKey == rhsKey { return nameOrder(lhs, rhs) }
                return option.ascending ? lhsKey < rhsKey : lhsKey > rhsKey
            }
        }
    }
}

/// How results are grouped in the UI ("organize search results").
public enum ResultGrouping: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case none
    case category
    case location
    case folder

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .category: return "Kind"
        case .location: return "Location"
        case .folder: return "Folder"
        }
    }
}

/// A titled group of results.
public struct ResultSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let results: [SearchResult]

    public init(id: String, title: String, results: [SearchResult]) {
        self.id = id
        self.title = title
        self.results = results
    }

    /// Groups already-sorted results, preserving their order inside every section.
    public static func group(
        _ results: [SearchResult],
        by grouping: ResultGrouping,
        locationNames: [String: String] = [:]
    ) -> [ResultSection] {
        guard grouping != .none else {
            return results.isEmpty ? [] : [ResultSection(id: "all", title: "Results", results: results)]
        }
        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [SearchResult]] = [:]
        for result in results {
            let key: String
            let title: String
            switch grouping {
            case .category:
                key = result.item.category.rawValue
                title = result.item.category.displayName
            case .location:
                key = result.item.locationID ?? "unknown"
                title = locationNames[key] ?? "Other"
            case .folder:
                key = result.item.parentPath
                title = result.item.parentName
            case .none:
                key = "all"
                title = "Results"
            }
            if buckets[key] == nil {
                order.append(key)
                titles[key] = title
            }
            buckets[key, default: []].append(result)
        }
        if grouping == .category {
            let rank = Dictionary(uniqueKeysWithValues: FileCategory.allCases.enumerated().map { ($1.rawValue, $0) })
            order.sort { (rank[$0] ?? .max) < (rank[$1] ?? .max) }
        }
        return order.map { ResultSection(id: $0, title: titles[$0] ?? $0, results: buckets[$0] ?? []) }
    }
}
