import Foundation

/// Errors surfaced by FileFinder services. All cases provide user-facing descriptions.
public enum FileFinderError: LocalizedError, Equatable {
    case fileNotFound(path: String)
    case accessDenied(path: String)
    case destinationExists(path: String)
    case invalidName(String)
    case invalidDestination(path: String)
    case operationFailed(operation: String, reason: String)
    case locationUnavailable(name: String)
    case bookmarkResolutionFailed(name: String)
    case unreadableContent(path: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "The file “\((path as NSString).lastPathComponent)” could not be found."
        case .accessDenied(let path):
            return "FileFinder does not have permission to access “\((path as NSString).lastPathComponent)”."
        case .destinationExists(let path):
            return "An item named “\((path as NSString).lastPathComponent)” already exists in the destination."
        case .invalidName(let name):
            return "“\(name)” is not a valid file name."
        case .invalidDestination(let path):
            return "“\((path as NSString).lastPathComponent)” is not a valid destination folder."
        case .operationFailed(let operation, let reason):
            return "\(operation) failed: \(reason)"
        case .locationUnavailable(let name):
            return "The location “\(name)” is not available."
        case .bookmarkResolutionFailed(let name):
            return "Access to “\(name)” has expired. Please add the folder again."
        case .unreadableContent(let path):
            return "The contents of “\((path as NSString).lastPathComponent)” cannot be read."
        case .cancelled:
            return "The operation was cancelled."
        }
    }

    /// Maps arbitrary errors (usually `CocoaError`) to a `FileFinderError`.
    public static func wrap(_ error: Error, operation: String, path: String) -> FileFinderError {
        if let error = error as? FileFinderError { return error }
        if error is CancellationError { return .cancelled }
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return .fileNotFound(path: path)
            case .fileReadNoPermission, .fileWriteNoPermission:
                return .accessDenied(path: path)
            case .fileWriteFileExists:
                return .destinationExists(path: path)
            case .fileWriteInvalidFileName:
                return .invalidName((path as NSString).lastPathComponent)
            default:
                break
            }
        }
        return .operationFailed(operation: operation, reason: error.localizedDescription)
    }
}
