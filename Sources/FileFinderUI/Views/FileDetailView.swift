#if os(iOS)
import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import FileFinderCore

/// Detail column: large preview, metadata and quick actions for one file.
struct FileDetailView: View {
    private enum FolderAction {
        case copy
        case move
    }

    @StateObject private var viewModel: FileDetailViewModel
    @ObservedObject private var environment: AppEnvironment
    private let onChange: (String, FileItem?) -> Void

    @State private var quickLookURL: URL?
    @State private var pendingFolderAction: FolderAction?
    @State private var isShowingFolderPicker = false
    @State private var isConfirmingDelete = false
    @State private var isRenaming = false
    @State private var newName = ""

    init(item: FileItem, environment: AppEnvironment, onChange: @escaping (String, FileItem?) -> Void) {
        _viewModel = StateObject(wrappedValue: FileDetailViewModel(item: item, environment: environment))
        self.environment = environment
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionBar
                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let message = viewModel.statusMessage, viewModel.errorMessage == nil {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                metadataSection
                if let preview = viewModel.textPreview {
                    textPreviewSection(preview)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Label(viewModel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: viewModel.isFavorite ? "star.fill" : "star")
                }
                if !viewModel.item.isDirectory && !viewModel.isDeleted {
                    ShareLink(item: viewModel.item.url)
                }
            }
        }
        .task {
            viewModel.onItemChanged = onChange
            await viewModel.load()
        }
        .quickLookPreview($quickLookURL)
        .fileImporter(isPresented: $isShowingFolderPicker, allowedContentTypes: [.folder]) { result in
            handleFolderPicked(result)
        }
        .confirmationDialog(
            "Delete “\(viewModel.item.name)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.delete() }
            }
        } message: {
            Text("This permanently deletes the item. This action can't be undone.")
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") {
                let name = newName
                Task { await viewModel.rename(to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            FileThumbnailView(item: viewModel.item, size: 160)
                .onTapGesture { openQuickLook() }
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.item.name)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(environment.previewService.kindDescription(for: viewModel.item))
                    .foregroundStyle(.secondary)
                if !viewModel.item.isDirectory {
                    Text(viewModel.item.formattedSize)
                        .foregroundStyle(.secondary)
                }
                if viewModel.isDeleted {
                    Label("Deleted", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton("Open", systemImage: "eye") { openQuickLook() }
                    .disabled(viewModel.item.isDirectory)
                actionButton("Copy to…", systemImage: "doc.on.doc") {
                    pendingFolderAction = .copy
                    isShowingFolderPicker = true
                }
                actionButton("Move to…", systemImage: "folder") {
                    pendingFolderAction = .move
                    isShowingFolderPicker = true
                }
                actionButton("Rename", systemImage: "pencil") {
                    newName = viewModel.item.name
                    isRenaming = true
                }
                actionButton("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .disabled(viewModel.isDeleted)
    }

    private func actionButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(viewModel.metadata) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(entry.value)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    Divider()
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func textPreviewSection(_ preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
            Text(preview)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Actions

    private func openQuickLook() {
        guard !viewModel.item.isDirectory, !viewModel.isDeleted else { return }
        quickLookURL = viewModel.item.url
    }

    private func handleFolderPicked(_ result: Result<URL, Error>) {
        guard let action = pendingFolderAction else { return }
        pendingFolderAction = nil
        switch result {
        case .success(let folder):
            Task {
                switch action {
                case .copy: await viewModel.copy(to: folder)
                case .move: await viewModel.move(to: folder)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
#endif
