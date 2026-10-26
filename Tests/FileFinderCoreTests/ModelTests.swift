import XCTest
@testable import FileFinderCore

final class FileCategoryTests: XCTestCase {
    func testCategoryForKnownExtensions() {
        XCTAssertEqual(FileCategory.category(forExtension: "PDF"), .document)
        XCTAssertEqual(FileCategory.category(forExtension: "jpeg"), .image)
        XCTAssertEqual(FileCategory.category(forExtension: "mov"), .video)
        XCTAssertEqual(FileCategory.category(forExtension: "mp3"), .audio)
        XCTAssertEqual(FileCategory.category(forExtension: "zip"), .archive)
        XCTAssertEqual(FileCategory.category(forExtension: "swift"), .code)
        XCTAssertEqual(FileCategory.category(forExtension: "xlsx"), .spreadsheet)
        XCTAssertEqual(FileCategory.category(forExtension: "key"), .presentation)
    }

    func testUnknownExtensionAndFolders() {
        XCTAssertEqual(FileCategory.category(forExtension: "xyz"), .other)
        XCTAssertEqual(FileCategory.category(forExtension: ""), .other)
        XCTAssertEqual(FileCategory.category(forExtension: "pdf", isDirectory: true), .folder)
    }

    func testExtensionsAreUniqueAcrossCategories() {
        var seen: [String: FileCategory] = [:]
        for category in FileCategory.allCases {
            for ext in category.extensions {
                XCTAssertNil(seen[ext], "\(ext) belongs to \(seen[ext]!) and \(category)")
                seen[ext] = category
            }
        }
    }

    func testTextExtensions() {
        XCTAssertTrue(FileCategory.isTextExtension("TXT"))
        XCTAssertTrue(FileCategory.isTextExtension("json"))
        XCTAssertFalse(FileCategory.isTextExtension("pdf"))
    }
}

final class FileItemTests: XCTestCase {
    func testDerivedProperties() {
        let item = makeItem("/root/Docs/../Docs/Report Final.PDF", size: 1_500)
        XCTAssertEqual(item.path, "/root/Docs/Report Final.PDF")
        XCTAssertEqual(item.name, "Report Final.PDF")
        XCTAssertEqual(item.fileExtension, "pdf")
        XCTAssertEqual(item.category, .document)
        XCTAssertEqual(item.parentPath, "/root/Docs")
        XCTAssertEqual(item.parentName, "Docs")
        XCTAssertEqual(item.formattedSize, "1.5 KB")
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(item.id, item.path)
    }

    func testHiddenAndDirectory() {
        XCTAssertTrue(makeItem("/root/.secret").isHidden)
        let folder = makeItem("/root/Photos.v2", isDirectory: true)
        XCTAssertEqual(folder.fileExtension, "")
        XCTAssertEqual(folder.category, .folder)
    }

    func testIsContained() {
        let item = makeItem("/root/a/b/c.txt")
        XCTAssertTrue(item.isContained(in: "/root"))
        XCTAssertTrue(item.isContained(in: "/root/a/"))
        XCTAssertTrue(item.isContained(in: "/"))
        XCTAssertFalse(item.isContained(in: "/ro"))
        XCTAssertFalse(item.isContained(in: "/root/a/b/c.txt"))
    }

    func testReadsAttributesFromDisk() throws {
        let tmp = try TemporaryDirectory()
        let url = try tmp.createFile("notes.txt", contents: "hello")
        let item = try FileItem(url: url, locationID: "x")
        XCTAssertEqual(item.size, 5)
        XCTAssertEqual(item.locationID, "x")
        XCTAssertFalse(item.isDirectory)
        XCTAssertThrowsError(try FileItem(url: tmp.url.appendingPathComponent("missing")))
    }

    func testCodableRoundTrip() throws {
        let item = makeItem("/root/song.mp3", size: 42)
        let decoded = try JSONDecoder().decode(FileItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded, item)
    }
}

final class SearchFilterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testDefaultFilterMatchesVisibleItems() {
        let filter = SearchFilter.none
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.matches(makeItem("/r/a.txt"), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/.hidden"), now: now))
        var withHidden = filter
        withHidden.includeHiddenFiles = true
        XCTAssertTrue(withHidden.matches(makeItem("/r/.hidden"), now: now))
    }

    func testCategoryFilter() {
        let filter = SearchFilter(categories: [.image, .video])
        XCTAssertTrue(filter.matches(makeItem("/r/a.png"), now: now))
        XCTAssertTrue(filter.matches(makeItem("/r/a.mov"), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a.pdf"), now: now))
        XCTAssertEqual(filter.activeFilterCount, 1)
    }

    func testSizeFilter() {
        let filter = SearchFilter(sizeRange: SizeRange(minimumBytes: 1_000, maximumBytes: 2_000))
        XCTAssertFalse(filter.matches(makeItem("/r/a", size: 999), now: now))
        XCTAssertTrue(filter.matches(makeItem("/r/a", size: 1_000), now: now))
        XCTAssertTrue(filter.matches(makeItem("/r/a", size: 2_000), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a", size: 2_001), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/folder", isDirectory: true), now: now), "folders have no meaningful size")
        XCTAssertTrue(SizeRange.huge.contains(5_000_000_000))
        XCTAssertFalse(SizeRange.small.contains(5_000_000))
    }

    func testDateFilter() {
        let filter = SearchFilter(dateFilter: .lastDays(7))
        XCTAssertTrue(filter.matches(makeItem("/r/a", modified: now.addingTimeInterval(-3 * 86_400)), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a", modified: now.addingTimeInterval(-8 * 86_400)), now: now))

        let custom = SearchFilter(dateFilter: .custom(from: now.addingTimeInterval(-100), to: now.addingTimeInterval(100)))
        XCTAssertTrue(custom.matches(makeItem("/r/a", modified: now), now: now))
        XCTAssertFalse(custom.matches(makeItem("/r/a", modified: now.addingTimeInterval(200)), now: now))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = DateFilter.today
        XCTAssertTrue(today.contains(calendar.startOfDay(for: now), now: now, calendar: calendar))
        XCTAssertFalse(today.contains(calendar.startOfDay(for: now).addingTimeInterval(-1), now: now, calendar: calendar))
    }

    func testLocationAndFolderFilters() {
        let byLocation = SearchFilter(locationIDs: ["a"])
        XCTAssertTrue(byLocation.matches(makeItem("/r/x", locationID: "a"), now: now))
        XCTAssertFalse(byLocation.matches(makeItem("/r/x", locationID: "b"), now: now))
        XCTAssertFalse(byLocation.matches(makeItem("/r/x", locationID: nil), now: now))

        let byFolder = SearchFilter(folderPath: "/r/docs")
        XCTAssertTrue(byFolder.matches(makeItem("/r/docs/sub/x.txt"), now: now))
        XCTAssertFalse(byFolder.matches(makeItem("/r/docs2/x.txt"), now: now))
    }

    func testCombinedFilters() {
        let filter = SearchFilter(
            categories: [.document],
            sizeRange: SizeRange(maximumBytes: 1_000),
            dateFilter: .lastDays(30),
            locationIDs: ["loc"],
            includeFolders: false
        )
        XCTAssertEqual(filter.activeFilterCount, 5)
        XCTAssertTrue(filter.matches(makeItem("/r/a.pdf", size: 10, modified: now), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a.pdf", size: 10_000, modified: now), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a.png", size: 10, modified: now), now: now))
        XCTAssertFalse(filter.matches(makeItem("/r/a.pdf", size: 10, modified: now.addingTimeInterval(-40 * 86_400)), now: now))
    }

    func testFilterCodable() throws {
        let filter = SearchFilter(categories: [.audio], dateFilter: .custom(from: now, to: nil), folderPath: "/x")
        let decoded = try JSONDecoder().decode(SearchFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertEqual(decoded, filter)
    }
}

final class SearchQueryTests: XCTestCase {
    func testParsingTermsAndExtensions() {
        let parsed = ParsedSearchText("Informe  .PDF ext:docx Canción")
        XCTAssertEqual(parsed.terms, ["informe", "cancion"])
        XCTAssertEqual(parsed.extensions, ["pdf", "docx"])
    }

    func testQuotedPhrase() {
        let parsed = ParsedSearchText("\"annual report\" 2024")
        XCTAssertEqual(parsed.terms, ["annual report", "2024"])
    }

    func testDottedNameIsATerm() {
        XCTAssertEqual(ParsedSearchText(".config.json").terms, [".config.json"])
        XCTAssertEqual(ParsedSearchText(".").terms, ["."])
    }

    func testIsEmpty() {
        XCTAssertTrue(SearchQuery(text: "   ").isEmpty)
        XCTAssertFalse(SearchQuery(text: "a").isEmpty)
        XCTAssertFalse(SearchQuery(text: "", filter: SearchFilter(categories: [.image])).isEmpty)
    }
}

final class FormattingTests: XCTestCase {
    func testByteSizes() {
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 0), "0 bytes")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 1), "1 byte")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 999), "999 bytes")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 1_000), "1 KB")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 2_500_000), "2.5 MB")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 999_960), "1 MB")
        XCTAssertEqual(ByteSizeFormatter.string(fromBytes: 3_000_000_000), "3 GB")
    }

    func testNormalization() {
        XCTAssertEqual("Canción ÉXITO".searchNormalized, "cancion exito")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(FileFinderError.fileNotFound(path: "/a/b.txt").errorDescription, "The file “b.txt” could not be found.")
        let wrapped = FileFinderError.wrap(CocoaError(.fileNoSuchFile), operation: "Copy", path: "/a/b")
        XCTAssertEqual(wrapped, .fileNotFound(path: "/a/b"))
        XCTAssertEqual(FileFinderError.wrap(CancellationError(), operation: "x", path: "y"), .cancelled)
    }
}
