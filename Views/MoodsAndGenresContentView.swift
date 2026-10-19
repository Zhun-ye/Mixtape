//
//  MoodsAndGenresContentView.swift
//  Mixtape
//
//  Content view for Moods & Genres tab, used with DiscoverCoordinator.
//

import SwiftUI

struct MoodsAndGenresContentView: View {
    @Bindable var viewModel: MoodsAndGenresViewModel

    var body: some View {
        Group {
            if viewModel.sections.isEmpty {
                ContentUnavailableView(
                    "No Moods & Genres Available",
                    systemImage: "guitars",
                    description: Text("Content may not be available in your region.")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: .adaptiveGridMinimum, maximum: .adaptiveGridMaximum), spacing: .sectionItemSpacing)],
                        spacing: .sectionItemSpacing,
                        pinnedViews: .sectionHeaders
                    ) {
                        ForEach(viewModel.sections) { section in
                            Section(header: sectionHeader(section.title)) {
                                ForEach(section.items) { item in
                                    itemCard(item: item)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .contentMargins(.bottom, 60)
            }
        }
        .loading(viewModel.loadingState, message: "Loading moods & genres...") {
            viewModel.refresh()
        }
        .navigationTitle("Moods & Genres")
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func itemCard(item: HomeSectionItem) -> some View {
        switch item {
        case let .playlist(playlist):
            Button {
                self.viewModel.didSelectPlaylist(playlist)
            } label: {
                PlaylistCard(playlist: playlist)
            }
            .buttonStyle(.interactiveCard)
        default:
            EmptyView()
        }
    }
}
