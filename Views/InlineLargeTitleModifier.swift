//
//  InlineLargeTitleModifier.swift
//  Mixtape
//
//  Inline large navigation title that fades out on scroll (iOS).
//


#if os(iOS)
import SwiftUI

@available(iOS 17.0, *)
struct InlineLargeTitleModifier<TrailingContent: View>: ViewModifier {
    let title: LocalizedStringKey
    let trailingContent: TrailingContent
    @State private var initialOffset: CGFloat?
    @State private var scrollOffset: CGFloat = 0

    private var isHidden: Bool {
        guard let initialOffset else { return false }
        let offset = scrollOffset - initialOffset
        return offset > 4.5
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            ios18Body(content: content)
        } else {
            fallbackBody(content: content)
        }
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func ios18Body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                if initialOffset == nil, newValue != 0 {
                    initialOffset = newValue
                }
                scrollOffset = newValue
            }
            .navigationTitle(isHidden ? "" : title)
            .toolbar { toolbarContent(animated: true) }
            .toolbarTitleDisplayMode(.inlineLarge)
            .animation(.easeInOut(duration: 0.2), value: isHidden)
    }

    @ViewBuilder
    private func fallbackBody(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar { toolbarContent(animated: false) }
            .toolbarTitleDisplayMode(.inlineLarge)
    }

    @ToolbarContentBuilder
    private func toolbarContent(animated: Bool) -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                trailingView(animated: animated)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                trailingView(animated: animated)
            }
        }
    }

    @ViewBuilder
    private func trailingView(animated: Bool) -> some View {
        if animated {
            trailingContent
                .opacity(isHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: isHidden)
        } else {
            trailingContent
        }
    }
}

@available(iOS 17.0, *)
extension View {
    func inlineLargeTitle<TrailingContent: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: () -> TrailingContent
    ) -> some View {
        modifier(InlineLargeTitleModifier(
            title: title,
            trailingContent: trailing()
        ))
    }

    func inlineLargeTitle(_ title: LocalizedStringKey) -> some View {
        modifier(InlineLargeTitleModifier(
            title: title,
            trailingContent: Spacer()
        ))
    }
}
#endif
