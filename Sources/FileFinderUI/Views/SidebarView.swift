#if os(iOS)
import SwiftUI
import FileFinderCore

struct SidebarView: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: SidebarItem.search) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                NavigationLink(value: SidebarItem.recent) {
                    Label("Recent", systemImage: "clock")
                }
                NavigationLink(value: SidebarItem.favorites) {
                    Label("Favorites", systemImage: "star")
                }
                NavigationLink(value: SidebarItem.history) {
                    Label("Search History", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("Kinds") {
                ForEach(FileCategory.allCases.filter { $0 != .other }) { category in
                    NavigationLink(value: SidebarItem.category(category)) {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            }

            Section("Locations") {
                ForEach(environment.locations.filter(\.isEnabled)) { location in
                    NavigationLink(value: SidebarItem.location(location.id)) {
                        Label(location.name, systemImage: location.systemImage)
                    }
                }
                NavigationLink(value: SidebarItem.manageLocations) {
                    Label("Manage Locations", systemImage: "folder.badge.gearshape")
                }
            }

            Section {
                NavigationLink(value: SidebarItem.activityLog) {
                    Label("Activity Log", systemImage: "list.bullet.rectangle")
                }
            } footer: {
                IndexStatusView(environment: environment)
                    .padding(.top, 8)
            }
        }
        .listStyle(.sidebar)
    }
}

/// Compact indexing status shown under the sidebar.
struct IndexStatusView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if environment.isIndexing {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(environment.indexingStatus)
                        .lineLimit(1)
                }
            } else {
                Text("\(environment.indexedItemCount) items indexed")
                if let date = environment.lastFullIndexDate {
                    Text("Updated \(date, style: .relative) ago")
                }
            }
            ForEach(environment.lastIndexingErrors, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
#endif
