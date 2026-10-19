//
//  LoadingModifier.swift
//  Mixtape
//
//  View modifier that handles loading/error states.
//

import SwiftUI

// MARK: - LoadingModifier

struct LoadingModifier: ViewModifier {
    let state: LoadingState
    let message: String
    let onRetry: (() async -> Void)?

    func body(content: Content) -> some View {
        switch state {
        case .idle, .loading:
            LoadingView(message)
        case .loaded, .loadingMore:
            content
        case let .error(error):
            content
                .overlay(
                    Group {
                        if error.isOffline {
                            ContentUnavailableView {
                                Label("You're Offline", systemImage: "wifi.slash")
                            } description: {
                                Text("Connect to the internet to load content.")
                            } actions: {
                                Button("Try Again") {
                                    if let onRetry {
                                        Task { await onRetry() }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            ErrorView(title: error.title, message: error.message) {
                                if let onRetry {
                                    Task { await onRetry() }
                                }
                            }
                        }
                    }
                )
        }
    }
}

// MARK: - View Extension

extension View {
    func loading(
        _ state: LoadingState,
        message: String = "",
        onRetry: (() async -> Void)? = nil
    ) -> some View {
        modifier(LoadingModifier(state: state, message: message, onRetry: onRetry))
    }
}
