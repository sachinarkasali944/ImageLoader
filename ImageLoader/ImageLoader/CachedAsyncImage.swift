//
//  CachedAsyncImage.swift
//  ImageLoader
//
//  LLD Concept: Reusable SwiftUI component wrapping the loader service.
//  Similar to how Kingfisher exposes .kf.setImage() or KFImage view.
//
//  Usage:
//      CachedAsyncImage(url: someURLString)
//      CachedAsyncImage(url: someURLString, placeholder: Image("myPlaceholder"))
//

import SwiftUI
import Combine

// MARK: - CachedAsyncImage View
struct CachedAsyncImage: View {

    let url: String
    var placeholder: Image

    // Per-view ViewModel that drives the local load state
    @StateObject private var viewModel: CachedAsyncImageViewModel

    init(url: String, placeholder: Image = Image(systemName: "photo.fill")) {
        self.url = url
        self.placeholder = placeholder
        // Inject URL into the ViewModel at init time
        _viewModel = StateObject(wrappedValue: CachedAsyncImageViewModel(url: url))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ZStack {
                    Color(.systemGray6)
                    ProgressView()
                }

            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

            case .failed:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo.slash.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - ViewModel
// Keeps load state per image cell — isolated from other cells
@MainActor
final class CachedAsyncImageViewModel: ObservableObject {
    @Published private(set) var state: ImageLoadState = .idle

    private let url: String
    private let service: ImageLoaderService

    init(url: String) {
        self.url = url
        self.service = .shared
    }

    init(url: String, service: ImageLoaderService) {
        self.url = url
        self.service = service
    }

    func load() async {
        guard state == .idle else { return }  // already loading or loaded
        state = .loading
        if let image = await service.loadImage(from: url) {
            state = .loaded(image)
        } else {
            state = .failed("Could not load image")
        }
    }
}

// MARK: - Preview
#Preview {
    CachedAsyncImage(url: "https://picsum.photos/seed/preview/400/300")
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
}
