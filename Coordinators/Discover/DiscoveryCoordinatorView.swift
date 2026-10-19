//
//  DiscoverCoordinatorView.swift
//  Mixtape
//
//  Provides NavigationStack view for the Discovery coordinator.
//

import SwiftUI

struct DiscoveryCoordinatorView: View {
    @Bindable var coordinator: DiscoveryCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.root.view()
                .navigationDestination(for: Destination.self) { destination in
                    destination.view()
                }
        }
    }
}
