#if os(iOS)
import Foundation
import FileFinderCore

/// Entries of the sidebar (first column of the split view).
enum SidebarItem: Hashable {
    case search
    case recent
    case favorites
    case history
    case category(FileCategory)
    case location(String)
    case manageLocations
    case activityLog

    /// `true` for entries whose content column shows search results.
    var showsResults: Bool {
        switch self {
        case .search, .recent, .category, .location: return true
        case .favorites, .history, .manageLocations, .activityLog: return false
        }
    }
}
#endif
