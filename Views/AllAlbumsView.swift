import SwiftUI

/// View displaying all albums for a section in a grid layout.
struct AllAlbumsView: View {
    @Bindable var viewModel: AllAlbumsViewModel

    private let columns = [
        GridItem(.adaptive(minimum: .adaptiveGridMinimum, maximum: .adaptiveGridMaximum), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(self.viewModel.albums) { album in
                    Button {
                        self.viewModel.delegate?.didSelectAlbum(album)
                    } label: {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.interactiveCard)
                    .hoverPlay {
                        Task {
                            await self.viewModel.playAlbum(album)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .scrollClipDisabled()
        }
        .navigationTitle(self.viewModel.title)
    }
}
