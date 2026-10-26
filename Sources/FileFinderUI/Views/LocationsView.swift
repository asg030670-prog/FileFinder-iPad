#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import FileFinderCore

/// Manages the folders that are indexed. Because iPadOS sandboxes apps, the user grants
/// access to additional folders (On My iPad, iCloud Drive, USB drives, servers…) here.
struct LocationsView: View {
    @ObservedObject var viewModel: LocationsViewModel
    @ObservedObject var environment: AppEnvironment

    @State var isShowingFolderPicker = false

    var body: some View {
        List {
            Section {
                ForEach(environment.locations) { location in
                    LocationRow(
                        location: location,
                        isEnabled: Binding(
                            get: { location.isEnabled },
                            set: { viewModel.setEnabled($0, for: location) }
                        )
                    )
                    .swipeActions {
                        if location.kind == .userSelected {
                            Button(role: .destructive) {
                                viewModel.remove(location)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        Button {
                            Task { await viewModel.reindex(location) }
                        } label: {
                            Label("Re-index", systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("Indexed Locations")
            } footer: {
                Text("Tip: to search the whole iPad, tap “Add Folder” and choose “On My iPad”. Repeat for iCloud Drive and any external drive or server you want to include.")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Status") {
                IndexStatusView(environment: environment)
            }
        }
        .navigationTitle("Locations")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.reindexAll()
                } label: {
                    Label("Re-index All", systemImage: "arrow.clockwise")
                }
                .disabled(environment.isIndexing)
                Button {
                    isShowingFolderPicker = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handlePickerResult(result)
        }
    }
}

private struct LocationRow: View {
    let location: SearchLocation
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                    Group {
                        if let lastIndexed = location.lastIndexed {
                            Text("\(location.itemCount) items · indexed \(lastIndexed, style: .relative) ago")
                        } else {
                            Text("Not indexed yet")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(location.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } icon: {
                Image(systemName: location.systemImage)
            }
        }
    }
}
#endif
