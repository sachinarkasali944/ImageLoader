//
//  ContentView.swift
//  ImageLoader
//
//  Demo: Scrollable grid of images loaded via CachedAsyncImage.
//  Watch the Xcode console — on first scroll you'll see "Cache MISS",
//  then scroll back up and you'll see "Cache HIT" (no re-download).
//

import SwiftUI

// MARK: - Sample Data
// Using Lorem Picsum — each seed produces a stable, unique image URL
private let sampleImages: [ImageItem] = (1...30).map { seed in
    ImageItem(
        id: seed,
        url: "https://picsum.photos/seed/\(seed)/400/300",
        title: "Photo #\(seed)"
    )
}

struct ImageItem: Identifiable {
    let id: Int
    let url: String
    let title: String
}

// MARK: - ContentView
struct ContentView: View {

    @StateObject private var service = ImageLoaderService.shared

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sampleImages) { item in
                        ImageCard(item: item)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Image Loader")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear Cache") {
                        service.clearCache()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - ImageCard
struct ImageCard: View {

    let item: ImageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: item.url)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )

            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
