//
//  DiscoveryCoordinator.swift
//  Mixtape
//

import Combine
import SwiftUI
import SwiftUINavigation
import FactoryKit

@MainActor
@Observable
final class DiscoveryCoordinator: @MainActor Coordinatable {

    @ObservationIgnored
    @Injected(\.authService) private var authService

    var path: [Destination] = []
    var root: Destination = .none

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
                    setRoot(to: .discovery)
                } else if authState.isLoggedOut {
                    setRoot(to: .signInRedirector)
                } else {
                    setRoot(to: .loading)
                }
            }
            .store(in: &cancellables)
    }
}
