#if os(iOS)
import SwiftUI
import QuickLookThumbnailing
import UIKit
import FileFinderCore

/// Shows a QuickLook thumbnail for a file, falling back to a category icon.
/// Thumbnails are generated lazily (only for visible rows) and cached in memory.
struct FileThumbnailView: View {
    let item: FileItem
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: item.category.systemImage)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            guard !item.isDirectory else { return }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item, size: size, scale: displayScale)
        }
    }
}

/// Memory-bounded thumbnail cache backed by `QLThumbnailGenerator`.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func thumbnail(for item: FileItem, size: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = "\(item.path)|\(item.modificationDate.timeIntervalSince1970)|\(Int(size * scale))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = representation.uiImage
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: key, cost: cost)
            return image
        } catch {
            return nil
        }
    }
}
#endif
