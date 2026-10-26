#if os(iOS)
import SwiftUI
import FileFinderCore

/// A single file in a result list: thumbnail, name, folder, size and date.
struct FileRowView: View {
    let item: FileItem
    var snippet: String?

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(item: item, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Label(item.parentName, systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    if !item.isDirectory {
                        Text("·")
                        Text(item.formattedSize)
                    }
                    Text("·")
                    Text(item.modificationDate, format: .dateTime.day().month().year())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
#endif
