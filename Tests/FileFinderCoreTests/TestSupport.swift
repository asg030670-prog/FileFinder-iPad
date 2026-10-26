import Foundation
import XCTest
@testable import FileFinderCore

/// Creates an isolated temporary folder tree for file system tests.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileFinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func createFile(_ relativePath: String, contents: String = "", modificationDate: Date? = nil) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
        if let modificationDate {
            try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: fileURL.path)
        }
        return fileURL
    }

    @discardableResult
    func createFolder(_ relativePath: String) throws -> URL {
        let folderURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    func path(_ relativePath: String) -> String {
        url.appendingPathComponent(relativePath).standardizedFileURL.path
    }
}

func makeItem(
    _ path: String,
    size: Int64 = 100,
    modified: Date = Date(timeIntervalSince1970: 1_700_000_000),
    isDirectory: Bool = false,
    locationID: String? = "loc"
) -> FileItem {
    FileItem(path: path, size: size, modificationDate: modified, isDirectory: isDirectory, locationID: locationID)
}
