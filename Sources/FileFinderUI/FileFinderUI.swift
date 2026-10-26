// The FileFinder user interface is iPad-only (SwiftUI + UIKit + QuickLook).
// On other platforms this module is intentionally empty so the package still builds and
// the platform-independent `FileFinderCore` tests can run anywhere (e.g. Linux CI).
#if os(iOS)
import SwiftUI
@_exported import FileFinderCore
#endif
