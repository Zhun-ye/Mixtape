//
//  SettingsCoordinator.swift
//  Mixtape
//
//  Manages the Settings view and its view model.
//

import SwiftUI
import Observation
import SwiftUINavigation

@MainActor
@Observable
final class SettingsCoordinator: HashableObject {
    let settingsViewModel: SettingsViewModel

    init() {
        settingsViewModel = SettingsViewModel()
    }
}
