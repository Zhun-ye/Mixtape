//
//  SearchCoordinatorView.swift
//  Mixtape
//
//  NavigationStack view for the Search tab.
//

import SwiftUI

struct SearchCoordinatorView: View {
    @Bindable var coordinator: SearchCoordinator
    @Binding var focusTrigger: Bool

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.root.view(focusTrigger: $focusTrigger)
                .navigationDestination(for: Destination.self) { destination in
                    destination.view()
                }
        }
    }
}
