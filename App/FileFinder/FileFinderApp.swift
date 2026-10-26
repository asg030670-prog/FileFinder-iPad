import SwiftUI
import BackgroundTasks
import FileFinderCore
import FileFinderUI

@main
struct FileFinderApp: App {
    @StateObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let environment = AppEnvironment(configuration: AppConfiguration.load())
        _environment = StateObject(wrappedValue: environment)
        BackgroundIndexing.environment = environment
    }

    var body: some Scene {
        WindowGroup {
            FileFinderRootView(environment: environment)
                .task {
                    await environment.start()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                environment.refreshIfNeeded()
            case .background:
                BackgroundIndexing.scheduleRefresh()
                Task { await environment.index.save() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundIndexing.taskIdentifier)) {
            await BackgroundIndexing.performRefresh()
        }
    }
}

/// Keeps the index fresh while the app is in the background using `BGAppRefreshTask`.
enum BackgroundIndexing {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.filefinder.ipad.reindex"

    @MainActor static var environment: AppEnvironment?

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            Log.index.info("Scheduled background re-indexing")
        } catch {
            Log.index.warning("Could not schedule background re-indexing: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func performRefresh() async {
        scheduleRefresh()
        guard let environment else { return }
        Log.index.info("Background re-indexing started")
        await environment.reindexAll()
    }
}
