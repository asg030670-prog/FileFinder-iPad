import Foundation

/// A root folder that is scanned and indexed.
///
/// iPadOS sandboxes every app, so FileFinder can only see its own container plus folders the
/// user explicitly grants access to through the Files picker (On My iPad, iCloud Drive,
/// external drives, network shares, third-party providers…). Granted folders are persisted as
/// bookmarks so access survives app relaunches.
public struct SearchLocation: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The app's own Documents folder (visible in Files › On My iPad › FileFinder).
        case appDocuments
        /// A folder the user picked; requires a security-scoped bookmark.
        case userSelected
    }

    public let id: String
    public var name: String
    public var path: String
    public var kind: Kind
    public var bookmarkData: Data?
    public var isEnabled: Bool
    public var lastIndexed: Date?
    public var itemCount: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        kind: Kind,
        bookmarkData: Data? = nil,
        isEnabled: Bool = true,
        lastIndexed: Date? = nil,
        itemCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.path = (path as NSString).standardizingPath
        self.kind = kind
        self.bookmarkData = bookmarkData
        self.isEnabled = isEnabled
        self.lastIndexed = lastIndexed
        self.itemCount = itemCount
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public var systemImage: String {
        switch kind {
        case .appDocuments: return "ipad"
        case .userSelected: return "folder.badge.person.crop"
        }
    }
}
