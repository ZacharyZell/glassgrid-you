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

    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadImage(for url: URL) async -> NSImage? {
        if let existing = cache.object(forKey: url as NSURL) {
            return existing
        }
        if let task = inFlight[url] {
            return await task.value
        }

        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            request.httpShouldHandleCookies = false
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight.removeValue(forKey: url)
        if let result {
            let cost = Int(result.size.width * result.size.height * 4)
            cache.setObject(result, forKey: url as NSURL, cost: max(1, cost))
        }
        return result
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
                            .font(.system(size: placeholderIconSize))
                            .foregroundStyle(.secondary.opacity(0.48))
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
}
