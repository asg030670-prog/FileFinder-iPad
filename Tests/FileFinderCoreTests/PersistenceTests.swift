import XCTest
@testable import FileFinderCore

final class SearchHistoryStoreTests: XCTestCase {
    func testRecordDeduplicatesAndLimits() {
        let backing = InMemoryKeyValueStore()
        let history = SearchHistoryStore(store: backing, maximumEntries: 3)
        history.record("Report")
        history.record("photos")
        history.record("  ")
        history.record("report", resultCount: 4)
        XCTAssertEqual(history.entries.map(\.text), ["report", "photos"])
        XCTAssertEqual(history.entries.first?.resultCount, 4)

        history.record("a")
        history.record("b")
        XCTAssertEqual(history.entries.map(\.text), ["b", "a", "report"])

        let reloaded = SearchHistoryStore(store: backing, maximumEntries: 3)
        XCTAssertEqual(reloaded.entries.map(\.text), ["b", "a", "report"])
    }

    func testSuggestionsAndRemoval() {
        let history = SearchHistoryStore(store: InMemoryKeyValueStore())
        history.record("invoice 2023")
        history.record("invoice 2024")
        history.record("vacation")
        XCTAssertEqual(history.suggestions(matching: "INV").map(\.text), ["invoice 2024", "invoice 2023"])
        XCTAssertEqual(history.suggestions(matching: "").count, 3)
        XCTAssertTrue(history.suggestions(matching: "vacation").isEmpty, "exact match is not suggested")

        history.remove(history.entries[0])
        XCTAssertEqual(history.entries.map(\.text), ["invoice 2024", "invoice 2023"])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }
}

final class FavoritesStoreTests: XCTestCase {
    func testToggleAndPersistence() {
        let backing = InMemoryKeyValueStore()
        let favorites = FavoritesStore(store: backing)
        let item = makeItem("/r/a.pdf")
        XCTAssertTrue(favorites.toggle(item))
        XCTAssertTrue(favorites.isFavorite(path: "/r/./a.pdf"))
        favorites.add(item)
        XCTAssertEqual(favorites.favorites.count, 1)

        XCTAssertEqual(FavoritesStore(store: backing).favorites.map(\.path), ["/r/a.pdf"])

        favorites.updatePath(from: "/r/a.pdf", to: makeItem("/r/b.pdf"))
        XCTAssertEqual(favorites.favorites.map(\.name), ["b.pdf"])

        XCTAssertFalse(favorites.toggle(makeItem("/r/b.pdf")))
        XCTAssertTrue(favorites.favorites.isEmpty)
    }

    func testPruneMissing() throws {
        let tmp = try TemporaryDirectory()
        let existing = try FileItem(url: tmp.createFile("keep.txt"))
        let favorites = FavoritesStore(store: InMemoryKeyValueStore())
        favorites.add(existing)
        favorites.add(makeItem(tmp.path("gone.txt")))
        XCTAssertEqual(favorites.pruneMissing(), 1)
        XCTAssertEqual(favorites.favorites.map(\.name), ["keep.txt"])
    }
}

final class LocationStoreTests: XCTestCase {
    func testDocumentsLocationIsAlwaysPresent() throws {
        let tmp = try TemporaryDirectory()
        let backing = InMemoryKeyValueStore()
        let store = LocationStore(store: backing, documentsURL: tmp.url)
        XCTAssertEqual(store.locations.count, 1)
        XCTAssertEqual(store.locations[0].id, LocationStore.appDocumentsID)
        XCTAssertEqual(store.locations[0].kind, .appDocuments)

        store.remove(store.locations[0])
        XCTAssertEqual(store.locations.count, 1, "app documents can't be removed")
    }

    func testAddFolderEnableAndContainment() throws {
        let tmp = try TemporaryDirectory()
        let documents = try tmp.createFolder("Documents")
        let external = try tmp.createFolder("External")
        let backing = InMemoryKeyValueStore()
        let store = LocationStore(store: backing, documentsURL: documents)

        let added = try store.addFolder(external)
        XCTAssertEqual(added.name, "External")
        XCTAssertEqual(try store.addFolder(external).id, added.id, "adding twice returns the existing location")
        XCTAssertEqual(store.locations.count, 2)

        store.setEnabled(false, for: added)
        XCTAssertEqual(store.enabledLocations.map(\.id), [LocationStore.appDocumentsID])

        store.markIndexed(added.id, itemCount: 12, date: Date(timeIntervalSince1970: 5))
        let reloaded = LocationStore(store: backing, documentsURL: documents)
        let restored = try XCTUnwrap(reloaded.location(withID: added.id))
        XCTAssertEqual(restored.itemCount, 12)
        XCTAssertFalse(restored.isEnabled)

        XCTAssertEqual(reloaded.location(containing: external.appendingPathComponent("x/y.txt").path)?.id, added.id)
        XCTAssertEqual(reloaded.location(containing: documents.appendingPathComponent("a.txt").path)?.id, LocationStore.appDocumentsID)
        XCTAssertNil(reloaded.location(containing: "/elsewhere/file"))
        XCTAssertEqual(try reloaded.beginAccessing(restored).path, external.standardizedFileURL.path)

        reloaded.remove(restored)
        XCTAssertNil(reloaded.location(withID: added.id))
    }
}

final class AppConfigurationTests: XCTestCase {
    func testPartialConfigurationUsesDefaults() throws {
        let json = #"{ "maximumResults": 100, "contentSearchEnabledByDefault": true }"#
        let configuration = try AppConfiguration.load(from: Data(json.utf8))
        XCTAssertEqual(configuration.maximumResults, 100)
        XCTAssertTrue(configuration.contentSearchEnabledByDefault)
        XCTAssertEqual(configuration.searchDebounceMilliseconds, AppConfiguration.default.searchDebounceMilliseconds)
    }

    func testExampleConfigurationFileIsValid() throws {
        let exampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/FileFinderConfig.example.json")
        let configuration = try AppConfiguration.load(from: Data(contentsOf: exampleURL))
        XCTAssertGreaterThan(configuration.maximumResults, 0)
        XCTAssertTrue(configuration.scanOptions.excludedDirectoryNames.contains(".Trash"))
    }

    func testRoundTrip() throws {
        let configuration = AppConfiguration(searchDebounceMilliseconds: 10, excludedDirectoryNames: ["x"])
        let decoded = try AppConfiguration.load(from: JSONEncoder().encode(configuration))
        XCTAssertEqual(decoded, configuration)
    }
}

final class LoggingTests: XCTestCase {
    func testEntriesAreCapturedAndFiltered() {
        let store = LogStore.shared
        let previousLevel = store.minimumLevel
        defer { store.minimumLevel = previousLevel }
        store.clear()
        store.minimumLevel = .info
        let logger = FFLogger(category: "Test")
        logger.debug("hidden")
        logger.warning("visible")
        let entries = store.recentEntries().filter { $0.category == "Test" }
        XCTAssertEqual(entries.map(\.message), ["visible"])
        XCTAssertEqual(entries.first?.level, .warning)
    }

    func testRingBufferCapacity() {
        let store = LogStore(capacity: 3)
        for i in 0..<5 {
            store.append(LogEntry(date: Date(), level: .info, category: "c", message: "\(i)"))
        }
        XCTAssertEqual(store.recentEntries().map(\.message), ["2", "3", "4"])
    }
}
