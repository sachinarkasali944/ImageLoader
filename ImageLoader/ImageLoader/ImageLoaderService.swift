//
//  ImageLoaderService.swift
//  ImageLoader
//
//  LLD Concept: Cache-aside pattern + request deduplication
//
//  Flow:
//  1. Check memory cache → return immediately if hit
//  2. Check in-flight tasks → reuse existing download Task if same URL is already being fetched
//  3. Otherwise start a new URLSession download, cache result, broadcast to all waiters
//

import UIKit
import Combine

// MARK: - Load State
// Represents the three states of an image load operation
enum ImageLoadState: Equatable {
    case idle
    case loading
    case loaded(UIImage)
    case failed(String)   // holds a human-readable error message
}

// MARK: - ImageLoaderService
// @MainActor ensures all state mutations happen on the main thread,
// keeping @Published properties safe to observe from SwiftUI views.
@MainActor
final class ImageLoaderService: ObservableObject {

    // Singleton — one shared cache for the whole app
    static let shared = ImageLoaderService()

    // Injected at init so we can swap in a mock during tests
    private let cache: ImageCacheProtocol

    // Deduplication table:
    // Maps URL string → an in-flight Task that resolves to UIImage?
    // If a second caller requests the same URL, we reuse the same Task.
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        self.cache = ImageMemoryCache()
    }

    init(cache: ImageCacheProtocol) {
        self.cache = cache
    }

    // MARK: - Public API

    /// Load an image from the given URL string.
    /// Returns cached image immediately or downloads it.
    func loadImage(from urlString: String) async -> UIImage? {

        // ── Step 1: Cache hit ─────────────────────────────────────────────
        if let cached = cache.get(forKey: urlString) {
            print("✅ Cache HIT  → \(urlString.suffix(40))")
            return cached
        }

        print("⬇️  Cache MISS → downloading \(urlString.suffix(40))")

        // ── Step 2: Deduplication — reuse in-flight task if it exists ─────
        if let existingTask = inFlightTasks[urlString] {
            print("♻️  Reusing in-flight task for \(urlString.suffix(40))")
            return await existingTask.value
        }

        // ── Step 3: Start a new download task ─────────────────────────────
        let task = Task<UIImage?, Never> {
            return await download(from: urlString)
        }

        inFlightTasks[urlString] = task

        let image = await task.value

        // Clean up in-flight entry regardless of success/failure
        inFlightTasks.removeValue(forKey: urlString)

        // Cache on success
        if let image {
            cache.set(image, forKey: urlString)
            print("💾 Cached image for \(urlString.suffix(40))")
        }

        return image
    }

    /// Remove a single entry from the cache (e.g. to force a refresh)
    func invalidate(urlString: String) {
        cache.remove(forKey: urlString)
    }

    /// Wipe the entire cache
    func clearCache() {
        cache.removeAll()
        print("🗑️  Cache cleared")
    }

    // MARK: - Private download helper

    private func download(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("❌ Bad HTTP response for \(urlString.suffix(40))")
                return nil
            }

            guard let image = UIImage(data: data) else {
                print("❌ Could not decode image data for \(urlString.suffix(40))")
                return nil
            }

            return image

        } catch {
            print("❌ Download error: \(error.localizedDescription)")
            return nil
        }
    }
}
