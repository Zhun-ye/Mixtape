//
//  LibraryCoordinator.swift
//  Mixtape
//

import Combine
import SwiftUI
@preconcurrency import SwiftUINavigation
import FactoryKit

@MainActor
@Observable
final class LibraryCoordinator: @preconcurrency Coordinatable {

    @ObservationIgnored
    @Injected(\.authService) private var authService

    var path: [Destination] = []
    var root: Destination = .none

    /// Root view model for library content - stored for external access (sidebar, artists/albums views).
    let libraryViewModel = LibraryViewModel()

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    weak var delegate: AppCoordinatorDelegate?

    init() {
        libraryViewModel.delegate = self
        authService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                if authState.isLoggedIn {
                    root = .library(libraryViewModel)
                } else if authState.isLoggedOut {
                    setRoot(to: .signInRedirector)
                } else {
                    setRoot(to: .loading)
                }
            }
            .store(in: &cancellables)
    }

    func didSetRoot(_ playlist: Playlist) {
        root = .playlist(PlaylistDetailViewModel(playlist: playlist))
    }
}
