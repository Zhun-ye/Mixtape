//
//  LibraryArtistsView.swift
//  Mixtape
//
//  Displays the user's library artists in a list or grid.
//

import SwiftUI

struct LibraryArtistsView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Group {
            switch viewModel.artistsDisplayMode {
            case .list:
                listView
            case .grid:
                gridView
            }
        }
        .loading(viewModel.loadingState, message: "Loading artists...") {
            viewModel.refresh()
        }
        .navigationTitle("Artists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    sortMenu
                    displayModeToggle
                }
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.artistsSortOrder = order
                    } label: {
                        HStack {
                            Text(order.displayName)
                            if viewModel.artistsSortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.artistsSortOrder.displayName)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.artistsDisplayMode = viewModel.artistsDisplayMode == .list ? .grid : .list
            }
        } label: {
            Image(systemName: viewModel.artistsDisplayMode == .list ? "square.grid.2x2" : "list.bullet")
        }
        .help(viewModel.artistsDisplayMode == .list ? "Switch to Grid" : "Switch to List")
    }

    // MARK: - List View

    private var listView: some View {
        List(viewModel.sortedArtists) { artist in
            Button {
                viewModel.didSelectArtist(artist)
            } label: {
                ArtistListRow(artist: artist)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: .adaptiveArtistGridMinimum, maximum: .adaptiveArtistGridMaximum), spacing: .sectionItemSpacing)
            ], spacing: .sectionItemSpacing) {
                ForEach(viewModel.sortedArtists) { artist in
                    Button {
                        viewModel.didSelectArtist(artist)
                    } label: {
                        ArtistGridCell(artist: artist)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Artist List Row

private struct ArtistListRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            Text(artist.name)
                .lineLimit(1)
            Spacer()
        }
        .hoverHighlight(cornerRadius: 6, padding: 8)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        Group {
            RemoteImage(url: artist.thumbnailURL?.cardThumbnailURL) {
                placeholderView
            }
            .aspectRatio(contentMode: .fill)
        }
        .frame(width: 44, height: 44)
        .clipShape(.circle)
    }

    private var placeholderView: some View {
        Circle()
            .fill(gradientForName(artist.name))
    }

    private func gradientForName(_ name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.1).truncatingRemainder(dividingBy: 1.0)

        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.5)
        let color2 = Color(hue: hue2, saturation: 0.7, brightness: 0.35)

        return LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Artist Grid Cell

private struct ArtistGridCell: View {
    let artist: Artist

    var body: some View {
        VStack(spacing: 8) {
            thumbnail
            Text(artist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .hoverHighlight(cornerRadius: 8, padding: 8)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        Group {
            RemoteImage(url: artist.thumbnailURL?.cardThumbnailURL) {
                placeholderView
            }
            .aspectRatio(contentMode: .fill)
        }
        .frame(width: 120, height: 120)
        .clipShape(.circle)
    }

    private var placeholderView: some View {
        Circle()
            .fill(gradientForName(artist.name))
    }

    private func gradientForName(_ name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.1).truncatingRemainder(dividingBy: 1.0)

        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.5)
        let color2 = Color(hue: hue2, saturation: 0.7, brightness: 0.35)

        return LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
