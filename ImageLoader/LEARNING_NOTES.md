# LLD Interview: Image Loader with Memory Caching
### "Design something similar to Kingfisher / SDWebImage"

---

## Table of Contents
1. [The Core Problem](#1-the-core-problem)
2. [Key Interview Questions & Answers](#2-key-interview-questions--answers)
3. [Architecture Diagram](#3-architecture-diagram)
4. [Component Breakdown](#4-component-breakdown)
5. [NSCache — The Right Tool](#5-nscache--the-right-tool)
6. [Deduplication — The Hidden Complexity](#6-deduplication--the-hidden-complexity)
7. [Concurrency Model](#7-concurrency-model)
8. [Cache-Aside Pattern](#8-cache-aside-pattern)
9. [How to Extend (Follow-up Questions)](#9-how-to-extend-follow-up-questions)
10. [Complexity Analysis](#10-complexity-analysis)
11. [Common Mistakes to Avoid](#11-common-mistakes-to-avoid)

---

## 1. The Core Problem

Every time a user scrolls a feed, 30+ image URLs need to be displayed.  
Without caching, **every scroll loads the same images over the network repeatedly**, causing:

- Wasted bandwidth
- Slow UI / bad UX
- High memory allocations
- Battery drain

**Goal:** Load each image once, cache it in memory, and serve subsequent requests instantly.

---

## 2. Key Interview Questions & Answers

### Q: "How would you prevent downloading the same image repeatedly?"
**Answer:**
- Maintain a `[String: UIImage]`-style **memory cache** keyed by URL string.
- Before any network call, check the cache. Return early if found — O(1) lookup.
- After a successful download, write to the cache.
- Use `NSCache` instead of a plain dictionary — it handles memory pressure automatically.

---

### Q: "What if 10 cells request the same image at the same time?"
**Answer (Deduplication):**
- Use a **deduplication table**: `[String: Task<UIImage?, Never>]`
- The first requester creates a `Task` and stores it in the table.
- Subsequent requesters find the existing `Task` and `await` its `.value`.
- All waiters receive the result from the **same single network call**.
- When the task completes, remove it from the table.

---

### Q: "How do you make the cache thread-safe?"
**Answer:**
- `NSCache` is **already thread-safe** — no locks needed.
- The loader is annotated `@MainActor`, so all reads/writes to `inFlightTasks` run on the main actor — no data races.
- Downloads happen in `Task` (cooperative thread pool) — the only shared mutable state is the cache (thread-safe) and the dedup table (main-actor-isolated).

---

### Q: "What eviction policy do you use?"
**Answer:**
- `NSCache` uses an **LRU-like** eviction policy managed by the OS.
- We add two hard limits:
  - `countLimit = 100` — max number of images
  - `totalCostLimit = 50 MB` — based on pixel byte cost (`width × height × 4`)
- On memory warnings, iOS automatically evicts entries from `NSCache`.

---

## 3. Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                     SwiftUI View                     │
│              CachedAsyncImage(url: "...")             │
└─────────────────────┬───────────────────────────────┘
                      │ loadImage(from:)
                      ▼
┌─────────────────────────────────────────────────────┐
│              ImageLoaderService (@MainActor)          │
│                                                      │
│  ┌─────────────────┐    ┌────────────────────────┐  │
│  │  ImageMemoryCache│    │  inFlightTasks [Dedup] │  │
│  │  (NSCache)       │    │  [URL: Task<UIImage?>] │  │
│  └────────┬─────────┘    └───────────┬────────────┘  │
│           │                          │               │
│     Cache HIT?                 Already in-flight?    │
│      ↓ YES                          ↓ YES            │
│   return image               await existing Task     │
│      ↓ NO                          ↓ NO              │
│           └──────────┬─────────────┘                 │
│                      ▼                               │
│              URLSession.shared.data(from:)           │
│                      │                               │
│              UIImage(data:) decode                   │
│                      │                               │
│              cache.set(image, forKey: url)           │
└─────────────────────────────────────────────────────┘
```

---

## 4. Component Breakdown

### `ImageCacheProtocol`
```swift
protocol ImageCacheProtocol {
    func set(_ image: UIImage, forKey key: String)
    func get(forKey key: String) -> UIImage?
    func remove(forKey key: String)
    func removeAll()
}
```
- **Why a protocol?** Enables swapping `NSCache` for a disk cache, a mock, or a combined cache without changing the loader.

---

### `ImageMemoryCache`
```swift
final class ImageMemoryCache: ImageCacheProtocol {
    private let cache = NSCache<NSString, UIImage>()
}
```
- Wraps `NSCache` with typed keys/values.
- Sets `countLimit` and `totalCostLimit`.
- Calculates pixel cost: `width × height × 4 bytes`.

---

### `ImageLoaderService`
```swift
@MainActor
final class ImageLoaderService: ObservableObject {
    static let shared = ImageLoaderService()
    private let cache: ImageCacheProtocol
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
}
```
- **Singleton** with injectable cache (testable).
- Implements the full Cache-Aside + Deduplication flow.

---

### `CachedAsyncImage` (View)
```swift
struct CachedAsyncImage: View {
    // Shows ProgressView while loading
    // Shows Image on success
    // Shows error icon on failure
}
```
- Uses `@StateObject` ViewModel per cell.
- Triggered by `.task {}` modifier (cancels automatically when view disappears).

---

## 5. NSCache — The Right Tool

| Feature | `Dictionary` | `NSCache` |
|---|---|---|
| Thread-safe | ❌ No | ✅ Yes |
| Memory pressure eviction | ❌ No | ✅ Yes (automatic) |
| Cost-based limits | ❌ No | ✅ Yes |
| Count limits | Manual | ✅ Built-in |
| Key type | `Hashable` | Must be `AnyObject` (use `NSString`) |

> **Interview tip:** Mentioning `NSCache` over `[String: UIImage]` immediately signals you know about thread safety and memory management.

---

## 6. Deduplication — The Hidden Complexity

This is what separates a junior answer from a senior one.

**The problem:**
```
Cell 1 requests "https://example.com/cat.jpg"   → starts download
Cell 2 requests "https://example.com/cat.jpg"   → also starts download  ← DUPLICATE!
Cell 3 requests "https://example.com/cat.jpg"   → also starts download  ← DUPLICATE!
```

**Without deduplication:** 3 identical network calls.

**The solution — in-flight task table:**
```swift
private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

// On new request:
if let existing = inFlightTasks[url] {
    return await existing.value  // all 3 callers await the SAME task
}
let task = Task { await download(url) }
inFlightTasks[url] = task
let result = await task.value
inFlightTasks.removeValue(forKey: url)
```

**Result:** 1 network call. All 3 cells get the image simultaneously when it arrives.

---

## 7. Concurrency Model

```
Main Actor (UI thread)
│
├── Read cache         → O(1), synchronous
├── Check inFlightTasks → O(1), synchronous
├── Create Task        → schedules on cooperative thread pool
└── await task.value   → suspends main actor (non-blocking)

Cooperative Thread Pool (background)
└── URLSession.shared.data(from:)  → network I/O
    └── UIImage(data:)             → decode on background thread
```

**Key points for the interview:**
- `@MainActor` does NOT block the main thread during `await` — it suspends and yields.
- `URLSession` manages its own thread pool for network I/O.
- `NSCache` is safe to call from any thread.

---

## 8. Cache-Aside Pattern

This is the design pattern being implemented:

```
┌─────────┐     1. read(key)     ┌─────────┐
│   App   │ ──────────────────►  │  Cache  │
│         │ ◄────────────────── │         │
└─────────┘   2a. return data    └─────────┘
     │          (cache HIT)
     │
     │       2b. cache MISS
     ▼
┌─────────┐
│ Network │  (load from source)
└────┬────┘
     │
     │  3. write(key, value) back to cache
     ▼
┌─────────┐
│  Cache  │  (populate for next time)
└─────────┘
```

The application code is responsible for populating the cache — the cache does not fetch data itself. This is called **Cache-Aside** (also known as **Lazy Loading**).

---

## 9. How to Extend (Follow-up Questions)

### "Add disk caching"
- Create `DiskCache: ImageCacheProtocol` that writes `UIImage` as JPEG/PNG to the app's Caches directory.
- Create `TieredCache` that checks memory first, then disk, then network.
- File names = `SHA256(url)` to avoid path traversal issues.

### "Add cache expiry / TTL"
- Wrap cached values: `struct CacheEntry { let image: UIImage; let expiresAt: Date }`.
- On `get()`, check if `expiresAt < Date.now`. If expired, return `nil` and evict.

### "Add image resizing / thumbnail support"
- The cache key becomes `"\(url)_\(width)x\(height)"`.
- Resize after decoding using `UIGraphicsImageRenderer`.

### "How would you handle authentication (headers)?"
- Accept a `URLRequest` instead of a `URL` in the API.
- The cache key is still the URL string portion of the request.

### "Prefetching"
- Add `prefetch(urls: [String])` that fires `Task { await loadImage(from: url) }` for each URL without returning a value — the cache gets populated proactively.

---

## 10. Complexity Analysis

| Operation | Time | Space |
|---|---|---|
| Cache lookup | O(1) | — |
| Cache write | O(1) | O(n) images |
| Download (first time) | O(network latency) | O(image size) |
| Dedup table lookup | O(1) | O(concurrent requests) |

**Memory worst case:** `countLimit × avg_image_size` — bounded by `NSCache` limits.

---

## 11. Common Mistakes to Avoid

| Mistake | Why It's Wrong | Fix |
|---|---|---|
| Using `[String: UIImage]` directly | Not thread-safe, no memory pressure eviction | Use `NSCache` |
| No deduplication | Same URL downloads N times simultaneously | `inFlightTasks` table |
| Storing images in `UserDefaults` | Not designed for binary data, slow | Use `NSCache` or file system |
| Creating a new `URLSession` per request | Wastes sockets, ignores HTTP keep-alive | Use `URLSession.shared` |
| Using `DispatchQueue` locks for thread safety when using `@MainActor` | Over-engineering, `@MainActor` already serializes access | Just use `@MainActor` |
| Not cleaning up in-flight tasks on cancellation | Memory leak | Remove from table in `defer` or after `await` |
