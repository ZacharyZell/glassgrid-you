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

private struct ThumbnailCacheKey: Hashable {
    let primary: URL?
    let fallback: URL?
}

/// Drop-in cached SwiftUI thumbnail view with zero flicker on Home re-entry and automatic fallback URL recovery.
struct CachedThumbnailImage: View {
    let url: URL?
    public let fallbackURL: URL?
    var placeholderIconSize: CGFloat = 20

    @State private var loadedImage: NSImage?
    @State private var loadedKey: ThumbnailCacheKey?

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        placeholderIconSize: CGFloat = 20
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.placeholderIconSize = placeholderIconSize
    }

    private var cacheKey: ThumbnailCacheKey {
        ThumbnailCacheKey(primary: url, fallback: fallbackURL)
    }

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
        .task(id: cacheKey) {
            let key = cacheKey
            loadedImage = nil
            loadedKey = nil

            if let primaryURL = key.primary {
                if let cached = ThumbnailImageCache.shared.cachedImage(for: primaryURL) {
                    loadedKey = key
                    loadedImage = cached
                    return
                }
                if let fetched = await ThumbnailImageCache.shared.loadImage(for: primaryURL) {
                    guard !Task.isCancelled else { return }
                    loadedKey = key
                    loadedImage = fetched
                    return
                }
            }

            guard !Task.isCancelled,
                  let fallback = key.fallback,
                  fallback != key.primary else {
                return
            }

            if let cachedFallback = ThumbnailImageCache.shared.cachedImage(for: fallback) {
                loadedKey = key
                loadedImage = cachedFallback
                return
            }
            let fetchedFallback = await ThumbnailImageCache.shared.loadImage(for: fallback)
            guard !Task.isCancelled else { return }
            loadedKey = key
            loadedImage = fetchedFallback
        }
    }

    private var displayedImage: NSImage? {
        if let loadedImage, loadedKey == cacheKey {
            return loadedImage
        }
        if let url, let cached = ThumbnailImageCache.shared.cachedImage(for: url) {
            return cached
        }
        if url == nil, let fallbackURL, let cachedFallback = ThumbnailImageCache.shared.cachedImage(for: fallbackURL) {
            return cachedFallback
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
