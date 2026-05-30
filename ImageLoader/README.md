# ImageLoader

A from-scratch **Image Loader with Memory Caching** built in Swift + SwiftUI — a common **Low-Level Design (LLD)** interview topic, inspired by [Kingfisher](https://github.com/onevcat/Kingfisher) and [SDWebImage](https://github.com/SDWebImage/SDWebImage).

> Built as a learning project to understand the internals of image caching libraries before iOS interviews.

---

## Demo

| First load (cache miss) | Scroll back up (cache hit) | Clear cache |
|:---:|:---:|:---:|
| Images download with spinner | Images appear instantly | Force re-download |

The Xcode console shows live cache events:
```
⬇️  Cache MISS → downloading .../seed/1/400/300
💾 Cached image for .../seed/1/400/300
✅ Cache HIT  → .../seed/1/400/300     ← second visit, instant
♻️  Reusing in-flight task for ...     ← deduplication in action
```

---

## Architecture

```
CachedAsyncImage (SwiftUI View)
       │
       │  loadImage(from: url)
       ▼
ImageLoaderService  (@MainActor singleton)
  ├── ImageMemoryCache  (NSCache wrapper)   ← O(1) read/write, thread-safe
  └── inFlightTasks     ([URL: Task])       ← deduplication table
             │
             ▼ (on cache miss)
     URLSession.shared.data(from:)
             │
             ▼
      UIImage(data:) decode
             │
             ▼
     cache.set(image, forKey: url)
```

### Core Design Patterns

| Pattern | Where | Why |
|---|---|---|
| **Cache-Aside** | `ImageLoaderService` | App controls cache population; lazy load on demand |
| **Deduplication** | `inFlightTasks` dictionary | Prevents N network calls for the same URL hit at once |
| **Protocol-oriented** | `ImageCacheProtocol` | Swap `NSCache` for disk cache or mock in tests |
| **Singleton + DI** | `ImageLoaderService.shared` + `init(cache:)` | Shared state in app, injectable in tests |

---

## File Structure

```
ImageLoader/
├── ImageCache.swift          # NSCache wrapper with memory limits
├── ImageLoaderService.swift  # Core loader: cache-aside + deduplication
├── CachedAsyncImage.swift    # SwiftUI view component (like KFImage)
├── ContentView.swift         # Demo: LazyVGrid of 30 images
│
├── LEARNING_NOTES.md         # Deep-dive interview prep notes
└── README.md                 # This file
```

---

## Key Concepts Covered

### 1. `NSCache` over plain `Dictionary`

```swift
let cache = NSCache<NSString, UIImage>()
cache.countLimit = 100          // max 100 images
cache.totalCostLimit = 50 * 1024 * 1024  // ~50 MB
```

- **Thread-safe** by default — no `DispatchQueue` or `NSLock` needed
- **Automatically evicts** entries when the system is under memory pressure
- **Cost-aware** — we pass `width × height × 4 bytes` as cost per image

### 2. Request Deduplication

```swift
private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

// Second caller finds existing task and awaits the same result
if let existing = inFlightTasks[url] {
    return await existing.value
}
```

If 10 list cells request the same image simultaneously, only **one** network call fires. All 10 cells receive the image when that single download completes.

### 3. `@MainActor` for Safe State Access

```swift
@MainActor
final class ImageLoaderService: ObservableObject { ... }
```

All mutations to `inFlightTasks` are serialized on the main actor — no data races, no manual locking.

### 4. `.task {}` for Automatic Cancellation

```swift
.task {
    await viewModel.load()
}
```

When a cell scrolls off screen, SwiftUI cancels the `Task` automatically — no memory leaks or stale updates.

---

## How to Run

1. Clone the repo
2. Open `ImageLoader.xcodeproj` in Xcode 15+
3. Select an iOS 17+ simulator
4. Run (`⌘R`)

Watch the console for cache hit/miss/dedup logs as you scroll.

---

## Extending This Project

| Feature | Approach |
|---|---|
| **Disk cache** | Add `DiskCache: ImageCacheProtocol`, write JPEG to `Caches/` directory, key = `SHA256(url)` |
| **Cache TTL / expiry** | Wrap values: `struct CacheEntry { image, expiresAt: Date }` |
| **Prefetching** | `prefetch(urls:)` fires fire-and-forget `Task` per URL |
| **Image resizing** | Cache key = `"\(url)_\(width)x\(height)"`, resize with `UIGraphicsImageRenderer` |
| **Auth headers** | Accept `URLRequest` instead of `URL` string |
| **Unit tests** | Inject `MockCache: ImageCacheProtocol` + `MockURLSession` at init |

---

## Interview Cheat Sheet

**Q: How do you prevent duplicate downloads?**  
→ `inFlightTasks: [String: Task]` — new callers `await` the existing task.

**Q: Why NSCache over Dictionary?**  
→ Thread-safe + automatic memory-pressure eviction + cost-based limits.

**Q: How is this thread-safe without locks?**  
→ `@MainActor` serializes access to all mutable state; `NSCache` handles its own thread safety.

**Q: What design pattern is this?**  
→ Cache-Aside (lazy loading) — the application populates the cache, not the cache itself.

---

## Requirements

- iOS 17+
- Xcode 15+
- Swift 5.9+
- No third-party dependencies

---

## License

MIT — free to use for learning and interview prep.
