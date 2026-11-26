import AppKit
import SwiftUI

/// Lightweight in-memory thumbnail cache preventing `AsyncImage` reload flicker when navigating to/from Home.
@MainActor
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 120
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    private var inFlight: [URL: Task<Data?, Never>] = [:]

    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadImage(for url: URL) async -> NSImage? {
        if let existing = cache.object(forKey: url as NSURL) {
            return existing
        }
        if let task = inFlight[url] {
            let data = await task.value
            if let existing = cache.object(forKey: url as NSURL) {
                return existing
            }
            return decodeAndCache(data, for: url)
        }

        let task = Task<Data?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            request.httpShouldHandleCookies = false
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                return nil
            }
            return data
        }
        inFlight[url] = task
        let data = await task.value
        inFlight.removeValue(forKey: url)
        if let existing = cache.object(forKey: url as NSURL) {
            return existing
        }
        return decodeAndCache(data, for: url)
    }

    private func decodeAndCache(_ data: Data?, for url: URL) -> NSImage? {
        guard let data, let image = NSImage(data: data) else {
            return nil
        }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: max(1, cost))
        return image
    }
}

/// Drop-in cached SwiftUI thumbnail view with zero flicker on Home re-entry.
struct CachedThumbnailImage: View {
    let url: URL?
    var placeholderIconSize: CGFloat = 20

    @State private var loadedImage: NSImage?

    var body: some View {
        Group {
            if let image = displayedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(resolvedPlaceholderIconFont)
                            .foregroundStyle(AppleTheme.textMuted)
                    )
            }
        }
        .task(id: url) {
            guard let url else {
                loadedImage = nil
                return
            }
            if let cached = ThumbnailImageCache.shared.cachedImage(for: url) {
                loadedImage = cached
                return
            }
            loadedImage = await ThumbnailImageCache.shared.loadImage(for: url)
        }
    }

    private var displayedImage: NSImage? {
        if let loadedImage {
            return loadedImage
        }
        if let url {
            return ThumbnailImageCache.shared.cachedImage(for: url)
        }
        return nil
    }

    private var resolvedPlaceholderIconFont: Font {
        switch placeholderIconSize {
        case 22...: return AppIconFont.hero
        case 18...: return AppIconFont.xl
        case 15...: return AppIconFont.lg
        case 13...: return AppIconFont.toolbar
        default: return AppIconFont.md
        }
    }
}
