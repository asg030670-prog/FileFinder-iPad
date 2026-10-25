import Foundation
#if canImport(Combine)
import Combine
#endif

/// Manages the folders that are indexed and searched.
@MainActor
public final class LocationsViewModel: ObservableObject {
    @Published public var errorMessage: String?

    public let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var locations: [SearchLocation] { environment.locations }

    /// Adds a folder chosen with the system folder picker.
    public func addFolder(_ url: URL) {
        do {
            try environment.addLocation(url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            urls.forEach(addFolder)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    public func remove(_ location: SearchLocation) {
        environment.removeLocation(location)
    }

    public func setEnabled(_ enabled: Bool, for location: SearchLocation) {
        environment.setLocation(location, enabled: enabled)
    }

    public func reindexAll() {
        environment.startReindexing()
    }

    public func reindex(_ location: SearchLocation) async {
        await environment.reindex(location)
        await environment.index.save()
    }
}
