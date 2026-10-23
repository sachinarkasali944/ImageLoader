# Image Loader

> SwiftUI remote images with memory caching and request deduplication.

A focused image-loading sample that separates the cache, loading service, and SwiftUI presentation. Use it to study cache-aside loading and repeated requests from scrolling views.

## Highlights

- NSCache-backed memory storage.
- In-flight task reuse for the same image URL.
- Reusable CachedAsyncImage view.
- Injectable cache abstraction and an image-grid demo.

## Open and run

1. Clone this repository and open `ImageLoader/ImageLoader.xcodeproj` in Xcode.
2. Select the app scheme and a simulator compatible with the deployment target in **Build Settings → iOS Deployment Target**. Use an Xcode version with SDK support for that target.
3. Build and run with **⌘R**. For a physical device, select your development team.

```bash
git clone https://github.com/sachinarkasali944/ImageLoader.git
cd ImageLoader
open "ImageLoader/ImageLoader.xcodeproj"
```

## Demo scope

This project demonstrates a memory cache; persistent disk caching is a separate concern. Images require internet access on a cache miss.

## Explore the code

- [Xcode project](./ImageLoader/ImageLoader.xcodeproj)
- [Project files](./ImageLoader)

## Further reading

[Read the detailed implementation guide](./ImageLoader/README.md).
