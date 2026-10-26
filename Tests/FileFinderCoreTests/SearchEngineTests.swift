import XCTest
@testable import FileFinderCore

final class SearchEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(_ items: [FileItem], cache: SearchCache = SearchCache()) async -> SearchEngine {
        let index = FileIndex()
        await index.replaceItems(items, for: "loc")
        return SearchEngine(index: index, cache: cache)
    }

    private var sampleItems: [FileItem] {
        [
            makeItem("/r/Report.pdf", size: 5_000, modified: now.addingTimeInterval(-86_400)),
            makeItem("/r/Annual report 2024.docx", size: 20_000, modified: now),
            makeItem("/r/Photos/holiday.jpg", size: 2_000_000, modified: now.addingTimeInterval(-40 * 86_400)),
            makeItem("/r/Music/Canción.mp3", size: 4_000_000, modified: now),
            makeItem("/r/Reports", isDirectory: true),
            makeItem("/r/notes.txt", size: 10, modified: now)
        ]
    }

    func testEmptyQueryReturnsNothing() async throws {
        let engine = await makeEngine(sampleItems)
        let results = try await engine.search(SearchQuery(text: "  "), now: now)
        XCTAssertTrue(results.isEmpty)
    }

    func testNameSearchIsCaseAndDiacriticInsensitive() async throws {
        let engine = await makeEngine(sampleItems)
        let results = try await engine.search(SearchQuery(text: "CANCION"), now: now)
        XCTAssertEqual(results.map(\.item.name), ["Canción.mp3"])
        XCTAssertEqual(results.first?.matchKind, .fileName)
    }

    func testRelevanceRanking() async throws {
        let engine = await makeEngine(sampleItems)
        let results = try await engine.search(SearchQuery(text: "report"), now: now)
        XCTAssertEqual(results.map(\.item.name), ["Report.pdf", "Reports", "Annual report 2024.docx"])
    }

    func testMultipleTermsMustAllMatch() async throws {
        let engine = await makeEngine(sampleItems)
        let results = try await engine.search(SearchQuery(text: "report 2024"), now: now)
        XCTAssertEqual(results.map(\.item.name), ["Annual report 2024.docx"])
    }

    func testExtensionSearch() async throws {
        let engine = await makeEngine(sampleItems)
        let byDot = try await engine.search(SearchQuery(text: ".pdf"), now: now)
        XCTAssertEqual(byDot.map(\.item.name), ["Report.pdf"])
        XCTAssertEqual(byDot.first?.matchKind, .fileExtension)

        let byPrefix = try await engine.search(SearchQuery(text: "ext:mp3"), now: now)
        XCTAssertEqual(byPrefix.map(\.item.name), ["Canción.mp3"])

        let bareWord = try await engine.search(SearchQuery(text: "jpg"), now: now)
        XCTAssertEqual(bareWord.map(\.item.name), ["holiday.jpg"])

        let combined = try await engine.search(SearchQuery(text: "report .docx"), now: now)
        XCTAssertEqual(combined.map(\.item.name), ["Annual report 2024.docx"])
    }

    func testFiltersOnlyQuery() async throws {
        let engine = await makeEngine(sampleItems)
        let query = SearchQuery(filter: SearchFilter(categories: [.image, .audio]), sort: SortOption(field: .name, ascending: true))
        let results = try await engine.search(query, now: now)
        XCTAssertEqual(results.map(\.item.name), ["Canción.mp3", "holiday.jpg"])
        XCTAssertTrue(results.allSatisfy { $0.matchKind == .filterOnly })
    }

    func testTextWithCombinedFilters() async throws {
        let engine = await makeEngine(sampleItems)
        let filter = SearchFilter(sizeRange: SizeRange(maximumBytes: 10_000), dateFilter: .lastDays(7))
        let results = try await engine.search(SearchQuery(text: "r", filter: filter), now: now)
        XCTAssertEqual(Set(results.map(\.item.name)), ["Report.pdf"])
    }

    func testContentSearch() async throws {
        let tmp = try TemporaryDirectory()
        let items = [
            try FileItem(url: tmp.createFile("meeting.txt", contents: "Discuss the Budget for Q3"), locationID: "loc"),
            try FileItem(url: tmp.createFile("other.txt", contents: "Nothing here"), locationID: "loc"),
            try FileItem(url: tmp.createFile("budget.md", contents: "irrelevant"), locationID: "loc")
        ]
        let engine = await makeEngine(items)

        let nameOnly = try await engine.search(SearchQuery(text: "budget"))
        XCTAssertEqual(nameOnly.map(\.item.name), ["budget.md"])

        let withContent = try await engine.search(SearchQuery(text: "budget", scope: .all))
        XCTAssertEqual(withContent.map(\.item.name), ["budget.md", "meeting.txt"])
        let contentMatch = try XCTUnwrap(withContent.last)
        XCTAssertEqual(contentMatch.matchKind, .content)
        XCTAssertEqual(contentMatch.contentSnippet, "Discuss the Budget for Q3")
    }

    func testSortingOptions() async throws {
        let engine = await makeEngine(sampleItems)
        let filter = SearchFilter(includeFolders: false)
        func names(_ sort: SortOption) async throws -> [String] {
            try await engine.search(SearchQuery(text: "o", filter: filter, sort: sort), now: now).map(\.item.name)
        }
        let bySizeDescending = try await names(SortOption(field: .size, ascending: false))
        XCTAssertEqual(bySizeDescending, ["Canción.mp3", "holiday.jpg", "Annual report 2024.docx", "Report.pdf", "notes.txt"])
        let byNameAscending = try await names(SortOption(field: .name, ascending: true))
        XCTAssertEqual(byNameAscending, ["Annual report 2024.docx", "Canción.mp3", "holiday.jpg", "notes.txt", "Report.pdf"])
        let byDateAscending = try await names(SortOption(field: .modificationDate, ascending: true))
        XCTAssertEqual(byDateAscending.first, "holiday.jpg")
        let byKind = try await names(SortOption(field: .kind, ascending: true))
        XCTAssertEqual(byKind.first, "Canción.mp3") // "Audio" sorts first
    }

    func testLimit() async throws {
        let items = (0..<50).map { makeItem("/r/file\($0).txt") }
        let engine = await makeEngine(items)
        let results = try await engine.search(SearchQuery(text: "file", limit: 10), now: now)
        XCTAssertEqual(results.count, 10)
    }

    func testCacheIsUsedAndInvalidatedByIndexChanges() async throws {
        let cache = SearchCache()
        let engine = await makeEngine(sampleItems, cache: cache)
        let query = SearchQuery(text: "notes")
        _ = try await engine.search(query, now: now)
        XCTAssertEqual(cache.misses, 1)
        _ = try await engine.search(query, now: now)
        XCTAssertEqual(cache.hits, 1)

        await engine.index.upsert(makeItem("/r/notes2.txt"))
        let results = try await engine.search(query, now: now)
        XCTAssertEqual(cache.misses, 2)
        XCTAssertEqual(results.count, 2)
    }

    func testCancelledSearchThrows() async throws {
        let items = (0..<5_000).map { makeItem("/r/file\($0).txt") }
        let engine = await makeEngine(items)
        let task = Task { () throws -> [SearchResult] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.search(SearchQuery(text: "file"))
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

final class ResultGroupingTests: XCTestCase {
    func testGroupingByCategoryLocationAndFolder() {
        let results = [
            SearchResult(item: makeItem("/a/x.pdf", locationID: "1"), matchKind: .fileName, score: 1),
            SearchResult(item: makeItem("/b/y.png", locationID: "2"), matchKind: .fileName, score: 1),
            SearchResult(item: makeItem("/a/z.png", locationID: "1"), matchKind: .fileName, score: 1)
        ]
        let byCategory = ResultSection.group(results, by: .category)
        XCTAssertEqual(byCategory.map(\.title), ["Documents", "Images"])
        XCTAssertEqual(byCategory[1].results.map(\.item.name), ["y.png", "z.png"])

        let byLocation = ResultSection.group(results, by: .location, locationNames: ["1": "iPad", "2": "iCloud"])
        XCTAssertEqual(byLocation.map(\.title), ["iPad", "iCloud"])
        XCTAssertEqual(byLocation[0].results.count, 2)

        let byFolder = ResultSection.group(results, by: .folder)
        XCTAssertEqual(byFolder.map(\.title), ["a", "b"])

        XCTAssertEqual(ResultSection.group(results, by: .none).first?.results.count, 3)
        XCTAssertTrue(ResultSection.group([], by: .none).isEmpty)
    }
}

final class SearchCacheTests: XCTestCase {
    func testLRUEviction() {
        let cache = SearchCache(capacity: 2)
        let keyA = SearchCache.Key(query: SearchQuery(text: "a"), generation: 0)
        let keyB = SearchCache.Key(query: SearchQuery(text: "b"), generation: 0)
        let keyC = SearchCache.Key(query: SearchQuery(text: "c"), generation: 0)
        cache.store([], for: keyA)
        cache.store([], for: keyB)
        XCTAssertNotNil(cache.results(for: keyA)) // A becomes most recently used
        cache.store([], for: keyC)               // evicts B
        XCTAssertNotNil(cache.results(for: keyA))
        XCTAssertNil(cache.results(for: keyB))
        XCTAssertNotNil(cache.results(for: keyC))
        XCTAssertEqual(cache.count, 2)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
    }

    func testGenerationIsPartOfKey() {
        let cache = SearchCache()
        cache.store([], for: SearchCache.Key(query: SearchQuery(text: "a"), generation: 1))
        XCTAssertNil(cache.results(for: SearchCache.Key(query: SearchQuery(text: "a"), generation: 2)))
    }
}

final class FileIndexTests: XCTestCase {
    func testMutationsBumpGeneration() async {
        let index = FileIndex()
        await index.replaceItems([makeItem("/r/a"), makeItem("/r/dir", isDirectory: true), makeItem("/r/dir/b")], for: "loc")
        let generationAfterReplace = await index.generation
        XCTAssertEqual(generationAfterReplace, 1)
        let count = await index.count
        XCTAssertEqual(count, 3)

        await index.upsert(makeItem("/r/a", size: 999))
        let updated = await index.items(in: "loc").first { $0.path == "/r/a" }
        XCTAssertEqual(updated?.size, 999)

        await index.remove(path: "/r/dir")
        let remaining = await index.allItems.map(\.path)
        XCTAssertEqual(remaining, ["/r/a"])

        await index.removeLocation("loc")
        let isEmpty = await index.allItems.isEmpty
        XCTAssertTrue(isEmpty)
        let generation = await index.generation
        XCTAssertEqual(generation, 4)
    }

    func testPersistenceRoundTrip() async throws {
        let tmp = try TemporaryDirectory()
        let persistence = IndexPersistence(fileURL: tmp.url.appendingPathComponent("cache/index.plist"))
        let index = FileIndex(persistence: persistence)
        await index.replaceItems([makeItem("/r/a.txt"), makeItem("/r/b.png")], for: "loc", date: Date(timeIntervalSince1970: 100))
        await index.save()

        let restored = FileIndex(persistence: persistence)
        let loaded = await restored.load()
        XCTAssertTrue(loaded)
        let paths = await restored.items(in: "loc").map(\.path)
        XCTAssertEqual(paths, ["/r/a.txt", "/r/b.png"])
        let lastIndexed = await restored.lastIndexed(locationID: "loc")
        XCTAssertEqual(lastIndexed, Date(timeIntervalSince1970: 100))

        try persistence.delete()
        let missing = await FileIndex(persistence: persistence).load()
        XCTAssertFalse(missing)
    }

    func testIndexingServiceScansIntoIndex() async throws {
        let tmp = try TemporaryDirectory()
        try tmp.createFile("one.txt")
        try tmp.createFile("sub/two.txt")
        let index = FileIndex()
        let service = IndexingService(index: index)
        let outcome = await service.indexLocation(id: "loc", root: tmp.url)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.itemCount, 3)
        let count = await index.count
        XCTAssertEqual(count, 3)

        let failure = await service.indexLocation(id: "bad", root: tmp.url.appendingPathComponent("missing"))
        XCTAssertFalse(failure.succeeded)
    }
}
