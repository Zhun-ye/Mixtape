//
//  SectionGroup.swift
//  Mixtape
//
//  A complete section view with horizontal scrolling content.
//  Handles title, navigation chevron, and scroll detection internally.
//

import SwiftUI
import Kingfisher

/// A section view with title and horizontal scrolling content.
/// Automatically hides the chevron and disables navigation when content fits within the view.
/// Supports automatic image prefetching when a section is provided.
/// Card sizes are calculated adaptively based on container width.
struct SectionGroup<Content: View>: View {
    let section: HomeSection
    let onNavigate: () -> Void
    let itemContent: (HomeSectionItem) -> Content

    /// Active image prefetcher instance for cancellation support.
    @State private var imagePrefetcher: ImagePrefetcher?

    #if os(macOS)
    @State private var isHovering = false
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var canScrollLeft = false
    @State private var canScrollRight = false
    #endif

    private var hasMore: Bool {
        #if os(iOS)
        return section.items.count > 6
        #else
        return section.items.count > 10
        #endif
    }

    /// Whether the section contains mood/genre category playlists.
    /// These don't show bottom text labels, so no extra height needed.
    private var isMoodGenreSection: Bool {
        section.items.contains {
            if case let .playlist(playlist) = $0 {
                return playlist.isMoodOrGenreCategory
            }
            return false
        }
    }

    /// Height reserved for text labels below cards.
    private var textHeight: CGFloat {
        isMoodGenreSection ? 0 : 48
    }

    /// Horizontal padding for the section content.
    private var leadingPadding: CGFloat {
        #if os(macOS)
        24
        #else
        18
        #endif
    }

    init(
        section: HomeSection,
        onNavigate: @escaping () -> Void = {},
        @ViewBuilder itemContent: @escaping (HomeSectionItem) -> Content
    ) {
        self.section = section
        self.onNavigate = onNavigate
        self.itemContent = itemContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView.padding(.leading, leadingPadding)
            AdaptiveWidthReader { width in
                let effectiveWidth = width - 2 * leadingPadding
                let cardSize = Self.calculateCardSize(for: effectiveWidth)
                #if os(macOS)
                desktopScrollView(cardSize: cardSize, containerWidth: effectiveWidth)
                    .contentMargins(.horizontal, leadingPadding)
                    .onHover { isHovering = $0 }
                #else
                mobileScrollView(cardSize: cardSize)
                    .contentMargins(.horizontal, leadingPadding)
                #endif
            }
        }
        .task(id: section.id) {
            await prefetchImagesAsync(for: section)
        }
        .onDisappear {
            // Cancel prefetching when section scrolls out of view
            imagePrefetcher?.stop()
            imagePrefetcher = nil
        }
    }

    // MARK: - Header

    private var headerView: some View {
        Button {
            if hasMore {
                onNavigate()
            }
        } label: {
            HStack {
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if hasMore {
                    chevronImage
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var chevronImage: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Mobile Scroll View

    #if os(iOS)
    @ViewBuilder
    private func mobileScrollView(cardSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: .sectionItemSpacing) {
                ForEach(section.items) { item in
                    itemContent(item)
                        .cardSize(cardSize)
                }
            }
            .scrollTargetLayout()
        }
        .cardSize(cardSize)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
    }
    #endif

    // MARK: - Desktop Scroll View

    #if os(macOS)
    @ViewBuilder
    private func desktopScrollView(cardSize: CGFloat, containerWidth: CGFloat) -> some View {
        let itemsPerPage = max(1, Int(containerWidth / (cardSize + .sectionItemSpacing)))

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: .sectionItemSpacing) {
                ForEach(section.items) { item in
                    itemContent(item)
                        .cardSize(cardSize)
                }
            }
            .scrollTargetLayout()
        }
        .cardSize(cardSize)
        .scrollPosition($scrollPosition)
        .onScrollTargetVisibilityChange(idType: HomeSectionItem.ID.self) { visibleIDs in
            if let firstID = section.items.first?.id {
                canScrollLeft = !visibleIDs.contains(firstID)
            }
            if let lastID = section.items.last?.id {
                canScrollRight = !visibleIDs.contains(lastID)
            }
        }
        .overlay(
            Group {
                if isHovering {
                    scrollNavigationOverlay(itemsPerPage: itemsPerPage)
                        .padding(.bottom, textHeight)
                }
            }
        )
    }

    @ViewBuilder
    private func scrollNavigationOverlay(itemsPerPage: Int) -> some View {
        HStack {
            if canScrollLeft {
                scrollNavigationButton(direction: .left) {
                    scrollByPage(itemsPerPage: itemsPerPage, direction: .left)
                }
            }
            Spacer()
            if canScrollRight {
                scrollNavigationButton(direction: .right) {
                    scrollByPage(itemsPerPage: itemsPerPage, direction: .right)
                }
            }
        }
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.2), value: canScrollLeft)
        .animation(.easeInOut(duration: 0.2), value: canScrollRight)
    }

    @ViewBuilder
    private func scrollNavigationButton(direction: ScrollDirection, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 54)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private var leadingItemID: HomeSectionItem.ID? {
        scrollPosition.viewID(type: HomeSectionItem.ID.self)
    }

    private func scrollByPage(itemsPerPage: Int, direction: ScrollDirection) {
        // If no position tracked yet, assume we're at index 0
        let currentIndex: Int
        if let leadingID = leadingItemID,
           let index = section.items.firstIndex(where: { $0.id == leadingID }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }

        let targetIndex: Int
        switch direction {
        case .left:
            targetIndex = max(0, currentIndex - itemsPerPage)
        case .right:
            targetIndex = min(section.items.count - 1, currentIndex + itemsPerPage)
        }

        let targetItem = section.items[targetIndex]
        withAnimation(.easeInOut(duration: 0.3)) {
            scrollPosition.scrollTo(id: targetItem.id, anchor: .leading)
        }
    }

    private enum ScrollDirection {
        case left, right
    }
    #endif

    // MARK: - Image Prefetching

    /// Prefetches images for a section to improve scrolling performance.
    /// Only prefetches the first page of items to limit memory usage.
    private func prefetchImagesAsync(for section: HomeSection) async {
        // Cancel any existing prefetcher
        imagePrefetcher?.stop()

        // Only prefetch first 10 items (roughly 1 page + buffer) to limit memory usage
        let itemsToFetch = section.items.prefix(10)
        let urls = itemsToFetch.compactMap { $0.thumbnailURL?.cardThumbnailURL }
        guard !urls.isEmpty else { return }

        // Prefetch to disk only - skip memory cache to reduce RAM usage
        let prefetcher = ImagePrefetcher(urls: urls, options: [.memoryCacheExpiration(.expired)])
        imagePrefetcher = prefetcher
        prefetcher.start()
    }

    /// Calculates optimal card size with a peek effect for horizontal scrolling.
    static func calculateCardSize(for width: CGFloat) -> CGFloat {
        let spacing = CGFloat.sectionItemSpacing
        let peekFraction: CGFloat = 0.15

        // macOS: Adaptive columns based on min/max size constraints
        let minSize = CGFloat.adaptiveGridMinimum
        let maxSize = CGFloat.adaptiveGridMaximum

        guard width > minSize else { return minSize }

        let targetSize = (minSize + maxSize) / 2
        let naturalColumns = (width + spacing) / (targetSize + spacing)
        var columns = max(1, Int(round(naturalColumns)))

        // Formula: columns * cardSize + (columns - 1) * spacing + peek * cardSize = width
        var cardSize = (width - spacing * CGFloat(columns - 1)) / (CGFloat(columns) + peekFraction)

        if cardSize > maxSize {
            columns += 1
            cardSize = (width - spacing * CGFloat(columns - 1)) / (CGFloat(columns) + peekFraction)
        } else if cardSize < minSize && columns > 1 {
            columns -= 1
            cardSize = (width - spacing * CGFloat(columns - 1)) / (CGFloat(columns) + peekFraction)
        }

        return min(maxSize, max(minSize, cardSize))
    }
}


// MARK: - Adaptive Width Reader

/// Reads container width using onGeometryChange modifier on macOS,
/// or screen width on iOS for better performance.
private struct AdaptiveWidthReader<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    #if os(macOS)
    @State private var width: CGFloat = .defaultCardSize
    #else
    private var screenWidth: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .defaultCardSize
        }
        return windowScene.screen.bounds.width
    }
    #endif

    var body: some View {
        #if os(iOS)
        content(screenWidth)
        #else
        content(width)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
        #endif
    }
}

