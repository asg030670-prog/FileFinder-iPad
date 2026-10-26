import Foundation

/// Copy / move / rename / delete operations built on `FileManager`.
///
/// All methods validate their input, never overwrite existing files silently (a unique name
/// such as “Report 2.pdf” is generated instead) and convert errors to `FileFinderError`.
public struct FileOperationsService: Sendable {
    public init() {}

    private var fileManager: FileManager { FileManager.default }

    /// Copies an item into `folder`, returning the URL of the copy.
    @discardableResult
    public func copy(_ source: URL, into folder: URL) throws -> URL {
        try validateSource(source)
        try validateDestinationFolder(folder)
        let destination = uniqueDestination(for: source.lastPathComponent, in: folder)
        do {
            try fileManager.copyItem(at: source, to: destination)
            Log.operations.info("Copied \(source.lastPathComponent) to \(folder.lastPathComponent)")
            return destination
        } catch {
            Log.operations.error("Copy of \(source.lastPathComponent) failed: \(error.localizedDescription)")
            throw FileFinderError.wrap(error, operation: "Copy", path: source.path)
        }
    }

    /// Moves an item into `folder`, returning its new URL.
    @discardableResult
    public func move(_ source: URL, into folder: URL) throws -> URL {
        try validateSource(source)
        try validateDestinationFolder(folder)
        let sourceFolder = source.deletingLastPathComponent().standardizedFileURL.path
        if sourceFolder == folder.standardizedFileURL.path {
            return source
        }
        if folder.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") {
            throw FileFinderError.invalidDestination(path: folder.path)
        }
        let destination = uniqueDestination(for: source.lastPathComponent, in: folder)
        do {
            try fileManager.moveItem(at: source, to: destination)
            Log.operations.info("Moved \(source.lastPathComponent) to \(folder.lastPathComponent)")
            return destination
        } catch {
            Log.operations.error("Move of \(source.lastPathComponent) failed: \(error.localizedDescription)")
            throw FileFinderError.wrap(error, operation: "Move", path: source.path)
        }
    }

    /// Renames an item in place, returning its new URL.
    @discardableResult
    public func rename(_ source: URL, to newName: String) throws -> URL {
        try validateSource(source)
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileOperationsService.isValidFileName(trimmed) else {
            throw FileFinderError.invalidName(newName)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        if destination.standardizedFileURL.path == source.standardizedFileURL.path {
            return source
        }
        // Allow case-only renames on case-insensitive file systems.
        let caseOnlyRename = destination.path.lowercased() == source.path.lowercased()
        if !caseOnlyRename && fileManager.fileExists(atPath: destination.path) {
            throw FileFinderError.destinationExists(path: destination.path)
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
            Log.operations.info("Renamed \(source.lastPathComponent) to \(trimmed)")
            return destination
        } catch {
            throw FileFinderError.wrap(error, operation: "Rename", path: source.path)
        }
    }

    /// Permanently deletes an item.
    public func delete(_ url: URL) throws {
        try validateSource(url)
        do {
            try fileManager.removeItem(at: url)
            Log.operations.notice("Deleted \(url.lastPathComponent)")
        } catch {
            Log.operations.error("Delete of \(url.lastPathComponent) failed: \(error.localizedDescription)")
            throw FileFinderError.wrap(error, operation: "Delete", path: url.path)
        }
    }

    /// Creates a folder inside `parent`.
    @discardableResult
    public func createFolder(named name: String, in parent: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileOperationsService.isValidFileName(trimmed) else { throw FileFinderError.invalidName(name) }
        try validateDestinationFolder(parent)
        let destination = parent.appendingPathComponent(trimmed, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileFinderError.destinationExists(path: destination.path)
        }
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            return destination
        } catch {
            throw FileFinderError.wrap(error, operation: "Create folder", path: destination.path)
        }
    }

    // MARK: - Helpers

    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", name.count <= 255 else { return false }
        return !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }

    /// Returns `folder/name`, or `folder/name 2.ext`, `folder/name 3.ext`… if taken.
    public func uniqueDestination(for name: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func validateSource(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileFinderError.fileNotFound(path: url.path)
        }
    }

    private func validateDestinationFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileFinderError.invalidDestination(path: folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else {
            throw FileFinderError.accessDenied(path: folder.path)
        }
    }
}
