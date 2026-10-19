//
//  SearchCoordinator.swift
//  Mixtape
//

import Combine
import SwiftUI
@preconcurrency import SwiftUINavigation
import FactoryKit

@MainActor
@Observable
final class SearchCoordinator: @preconcurrency Coordinatable {

    @ObservationIgnored
    @Injected(\.authService) private var authService

    let searchViewModel: SearchViewModel

    var path: [Destination] = []
    var root: Destination = .none

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    weak var delegate: AppCoordinatorDelegate?

    init() {
        searchViewModel = SearchViewModel()

        authService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                if authState.isLoggedIn {
                    searchViewModel.delegate = self
                    root = .search(searchViewModel)
                } else if authState.isLoggedOut {
                    setRoot(to: .signInRedirector)
                } else {
                    setRoot(to: .loading)
                }
            }
            .store(in: &cancellables)
    }
}

