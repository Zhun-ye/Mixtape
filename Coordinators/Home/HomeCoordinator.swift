//
//  HomeCoordinator.swift
//  Mixtape
//

import Combine
import SwiftUI
import SwiftUINavigation
import FactoryKit

@MainActor
@Observable
final class HomeCoordinator: @MainActor Coordinatable {

    @ObservationIgnored
    @Injected(\.authService) private var authService

    var root: Destination = .loading
    var path: [Destination] = []

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    weak var delegate: AppCoordinatorDelegate?

    init() {
        authService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                if authState.isLoggedIn {
                    setRoot(to: .home)
                } else if authState == .loggedOut {
                    setRoot(to: .signIn)
                } else {
                    setRoot(to: .loading)
                }
            }
            .store(in: &cancellables)
    }
}

