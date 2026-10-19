//
//  HomeCoordinatorView.swift
//  Mixtape
//

import SwiftUI

struct HomeCoordinatorView: View {
    @Bindable var coordinator: HomeCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.root.view()
                .navigationDestination(for: Destination.self) { destination in
                    destination.view()
                }
        }
    }
}
