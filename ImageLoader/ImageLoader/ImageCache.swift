//
//  ImageCache.swift
//  ImageLoader
//
//  LLD Concept: Thread-safe memory cache using NSCache
//  NSCache automatically evicts entries under memory pressure (OS-managed)
//  and is thread-safe by default — no manual locking needed.
//

import UIKit

// MARK: - Cache Protocol
// Using a protocol makes the cache swappable (e.g. swap NSCache for DiskCache in tests)
protocol ImageCacheProtocol {
    func set(_ image: UIImage, forKey key: String)
    func get(forKey key: String) -> UIImage?
    func remove(forKey key: String)
    func removeAll()
}

// MARK: - Memory Cache (NSCache wrapper)
final class ImageMemoryCache: ImageCacheProtocol {

    // NSCache<KeyType, ObjectType>
    // Key MUST be a class (NSString, not String)
    // Value MUST be a class (UIImage conforms to AnyObject)
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Limit: max 100 images in memory
        cache.countLimit = 100
        // Limit: ~50 MB of memory (approximate — NSCache uses cost if set)
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    func set(_ image: UIImage, forKey key: String) {
        // Cost = uncompressed bytes of the image (width * height * 4 bytes per pixel)
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func get(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
