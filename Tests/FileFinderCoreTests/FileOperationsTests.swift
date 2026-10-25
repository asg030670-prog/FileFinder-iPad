import XCTest
@testable import FileFinderCore

final class FileOperationsTests: XCTestCase {
    var tmp: TemporaryDirectory!
    let operations = FileOperationsService()

    override func setUpWithError() throws {
        tmp = try TemporaryDirectory()
    }

    override func tearDown() {
        tmp = nil
    }

    func testCopyCreatesUniqueNames() throws {
        let source = try tmp.createFile("Report.pdf", contents: "data")
        let destination = try tmp.createFolder("Backup")
        let first = try operations.copy(source, into: destination)
        let second = try operations.copy(source, into: destination)
        XCTAssertEqual(first.lastPathComponent, "Report.pdf")
        XCTAssertEqual(second.lastPathComponent, "Report 2.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "data")

        let copyInPlace = try operations.copy(source, into: tmp.url)
        XCTAssertEqual(copyInPlace.lastPathComponent, "Report 2.pdf")
    }

    func testMove() throws {
        let source = try tmp.createFile("a.txt", contents: "x")
        let destination = try tmp.createFolder("Dest")
        let moved = try operations.move(source, into: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(try operations.move(moved, into: destination), moved, "moving into the same folder is a no-op")
    }

    func testMoveFolderIntoItselfFails() throws {
        let folder = try tmp.createFolder("Parent")
        let child = try tmp.createFolder("Parent/Child")
        XCTAssertThrowsError(try operations.move(folder, into: child)) { error in
            XCTAssertEqual(error as? FileFinderError, .invalidDestination(path: child.path))
        }
    }

    func testRename() throws {
        let source = try tmp.createFile("old.txt")
        try tmp.createFile("taken.txt")
        let renamed = try operations.rename(source, to: "  new.txt ")
        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertThrowsError(try operations.rename(renamed, to: "taken.txt")) { error in
            XCTAssertEqual(error as? FileFinderError, .destinationExists(path: self.tmp.url.appendingPathComponent("taken.txt").path))
        }
        XCTAssertThrowsError(try operations.rename(renamed, to: "bad/name")) { error in
            XCTAssertEqual(error as? FileFinderError, .invalidName("bad/name"))
        }
        XCTAssertThrowsError(try operations.rename(renamed, to: ".."))
    }

    func testDelete() throws {
        let file = try tmp.createFile("delete-me.txt")
        try operations.delete(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertThrowsError(try operations.delete(file)) { error in
            XCTAssertEqual(error as? FileFinderError, .fileNotFound(path: file.path))
        }
    }

    func testCreateFolderAndInvalidDestination() throws {
        let folder = try operations.createFolder(named: "New", in: tmp.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertThrowsError(try operations.createFolder(named: "New", in: tmp.url))
        let file = try tmp.createFile("file.txt")
        XCTAssertThrowsError(try operations.copy(file, into: file)) { error in
            XCTAssertEqual(error as? FileFinderError, .invalidDestination(path: file.path))
        }
    }

    func testValidFileNames() {
        XCTAssertTrue(FileOperationsService.isValidFileName("Report (final).pdf"))
        XCTAssertFalse(FileOperationsService.isValidFileName(""))
        XCTAssertFalse(FileOperationsService.isValidFileName("a:b"))
        XCTAssertFalse(FileOperationsService.isValidFileName(String(repeating: "a", count: 256)))
    }
}

final class FilePreviewServiceTests: XCTestCase {
    func testTextPreviewIsTruncated() throws {
        let tmp = try TemporaryDirectory()
        let item = try FileItem(url: tmp.createFile("long.txt", contents: String(repeating: "abc", count: 100)))
        let service = FilePreviewService(maximumPreviewCharacters: 10)
        XCTAssertEqual(try service.textPreview(for: item), "abcabcabca\n…")
        let image = try FileItem(url: tmp.createFile("pic.png"))
        XCTAssertThrowsError(try service.textPreview(for: image))
    }

    func testMetadata() throws {
        let tmp = try TemporaryDirectory()
        let item = try FileItem(url: tmp.createFile("doc.pdf", contents: "12345"))
        let entries = FilePreviewService().metadata(for: item, locationName: "iPad")
        let values = Dictionary(uniqueKeysWithValues: entries.map { ($0.label, $0.value) })
        XCTAssertEqual(values["Name"], "doc.pdf")
        XCTAssertEqual(values["Kind"], "PDF – Documents")
        XCTAssertEqual(values["Size"], "5 bytes (5 bytes)")
        XCTAssertEqual(values["Location"], "iPad")
        XCTAssertNotNil(values["Modified"])

        let folder = try FileItem(url: tmp.url)
        let folderValues = Dictionary(uniqueKeysWithValues: FilePreviewService().metadata(for: folder).map { ($0.label, $0.value) })
        XCTAssertEqual(folderValues["Items"], "1")
        XCTAssertEqual(folderValues["Kind"], "Folder")
    }
}
