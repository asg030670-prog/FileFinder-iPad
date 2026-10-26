import XCTest
@testable import FileFinderCore

final class FileScannerTests: XCTestCase {
    var tmp: TemporaryDirectory!

    override func setUpWithError() throws {
        tmp = try TemporaryDirectory()
        try tmp.createFile("a.txt", contents: "alpha")
        try tmp.createFile("Docs/report.pdf", contents: "pdf")
        try tmp.createFile("Docs/2024/Deep/nested.md", contents: "# nested")
        try tmp.createFile(".hidden/secret.txt", contents: "secret")
        try tmp.createFile(".dotfile", contents: "x")
        try tmp.createFile("node_modules/pkg/index.js", contents: "js")
    }

    override func tearDown() {
        tmp = nil
    }

    private func names(_ items: [FileItem]) -> Set<String> { Set(items.map(\.name)) }

    func testRecursiveScanSkipsHiddenAndExcluded() throws {
        let items = try FileScanner().scan(root: tmp.url, locationID: "loc")
        XCTAssertEqual(names(items), ["a.txt", "Docs", "report.pdf", "2024", "Deep", "nested.md"])
        XCTAssertTrue(items.allSatisfy { $0.locationID == "loc" })
        let nested = try XCTUnwrap(items.first { $0.name == "nested.md" })
        XCTAssertEqual(nested.size, 8)
        XCTAssertEqual(nested.parentPath, tmp.path("Docs/2024/Deep"))
        XCTAssertTrue(try XCTUnwrap(items.first { $0.name == "Docs" }).isDirectory)
    }

    func testIncludeHiddenFiles() throws {
        let scanner = FileScanner(options: ScanOptions(includeHiddenFiles: true, excludedDirectoryNames: []))
        let found = names(try scanner.scan(root: tmp.url))
        XCTAssertTrue(found.isSuperset(of: [".hidden", "secret.txt", ".dotfile", "node_modules", "index.js"]))
    }

    func testMaximumDepth() throws {
        let scanner = FileScanner(options: ScanOptions(maximumDepth: 1))
        XCTAssertEqual(names(try scanner.scan(root: tmp.url)), ["a.txt", "Docs"])
        let two = FileScanner(options: ScanOptions(maximumDepth: 2))
        XCTAssertEqual(names(try two.scan(root: tmp.url)), ["a.txt", "Docs", "report.pdf", "2024"])
    }

    func testBatchesReportProgress() throws {
        var batches: [[FileItem]] = []
        var lastProgress = ScanProgress()
        let scanner = FileScanner(options: ScanOptions(batchSize: 2))
        let items = try scanner.scan(root: tmp.url) { batch, progress in
            batches.append(batch)
            lastProgress = progress
        }
        XCTAssertEqual(batches.flatMap { $0 }.count, items.count)
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(lastProgress.scannedItems, items.count)
    }

    func testInvalidRoots() {
        XCTAssertThrowsError(try FileScanner().scan(root: tmp.url.appendingPathComponent("missing"))) { error in
            XCTAssertEqual(error as? FileFinderError, .fileNotFound(path: self.tmp.url.appendingPathComponent("missing").path))
        }
        XCTAssertThrowsError(try FileScanner().scan(root: tmp.url.appendingPathComponent("a.txt")))
    }

    func testCancellation() async throws {
        let root = tmp.url
        let task = Task { () throws -> [FileItem] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try FileScanner().scan(root: root)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? FileFinderError, .cancelled)
        }
    }
}

final class ContentSearcherTests: XCTestCase {
    func testSnippetRequiresAllTerms() {
        let searcher = ContentSearcher(snippetContext: 5)
        let text = "The quick brown fox jumps over the lazy dog"
        XCTAssertEqual(searcher.snippet(for: ["fox"], in: text), "…brown fox jumps…")
        XCTAssertNotNil(searcher.snippet(for: ["fox", "lazy"], in: text))
        XCTAssertNil(searcher.snippet(for: ["fox", "cat"], in: text))
        XCTAssertEqual(searcher.snippet(for: ["the"], in: text), "The quick…")
    }

    func testDiacriticInsensitiveContentMatch() {
        let searcher = ContentSearcher()
        XCTAssertNotNil(searcher.snippet(for: ["cancion"], in: "Mi CANCIÓN favorita"))
    }

    func testMatchReadsFiles() throws {
        let tmp = try TemporaryDirectory()
        let url = try tmp.createFile("notes.txt", contents: "Line one\nMeeting with Ana about the budget\nLine three")
        let item = try FileItem(url: url)
        let searcher = ContentSearcher()
        let snippet = try XCTUnwrap(searcher.match(terms: ["budget"], in: item))
        XCTAssertTrue(snippet.contains("budget"))
        XCTAssertFalse(snippet.contains("\n"))
        XCTAssertNil(searcher.match(terms: ["missing"], in: item))

        let binary = try FileItem(url: tmp.createFile("image.png", contents: "budget"))
        XCTAssertNil(searcher.match(terms: ["budget"], in: binary), "only text files are searched")

        let small = ContentSearcher(maximumFileSize: 5)
        XCTAssertNil(small.match(terms: ["budget"], in: item), "large files are skipped")
    }

    func testDecodeTruncatedUTF8() {
        let data = Data("añb".utf8)
        // Cut inside the two-byte "ñ".
        XCTAssertEqual(ContentSearcher.decode(data.prefix(2)), "a")
        XCTAssertEqual(ContentSearcher.decode(data), "añb")
    }
}
