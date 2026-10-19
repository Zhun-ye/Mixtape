//
//  MacOSPlayerBarModifier.swift
//  Mixtape
//
//  ViewModifier for displaying the PlayerBar on macOS.
//

import SwiftUI

// MARK: - Environment Key

private struct PlayerViewModelKey: EnvironmentKey {
    static let defaultValue: PlayerViewModel? = nil
}

extension EnvironmentValues {
    var playerViewModel: PlayerViewModel? {
        get { self[PlayerViewModelKey.self] }
        set { self[PlayerViewModelKey.self] = newValue }
    }
}

// MARK: - MacOSPlayerBarModifier

struct MacOSPlayerBarModifier: ViewModifier {
    @Environment(\.playerViewModel) private var playerViewModel

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                if let viewModel = playerViewModel {
                    PlayerBar(viewModel: viewModel)
                        .padding(20)
                }
            }
            #endif
    }
}

extension View {
    func macOSPlayerBar() -> some View {
        modifier(MacOSPlayerBarModifier())
    }

    func playerViewModel(_ viewModel: PlayerViewModel) -> some View {
        environment(\.playerViewModel, viewModel)
    }
}
