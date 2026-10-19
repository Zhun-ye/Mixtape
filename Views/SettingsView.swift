//
//  SettingsView.swift
//  Mixtape
//
//  Settings view for app configuration.
//

import SwiftUI

// MARK: - SettingsView

/// Main settings view with tabbed navigation.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - General Section
                
                Section {
                    // Account status
                    HStack {
                        UserProfileView(imageSize: 24, showName: true)
                        Spacer()
                        if viewModel.isLoggedIn {
                            Button("Sign Out") {
                                Task {
                                    await viewModel.signOut()
                                }
                            }
                        } else {
                            Button("Sign In") {
                                viewModel.showLogin()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
#if os(macOS)
                    // Now Playing Notifications
                    Toggle("Show Now Playing Notifications", isOn: $viewModel.settings.showNowPlayingNotifications)
#endif
                } header: {
                    Text("General")
                }
                
                // MARK: - Content Section
                
                Section {
                    Picker("Language", selection: $viewModel.settings.contentLanguage) {
                        ForEach(ContentLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    
                    Picker("Region", selection: $viewModel.settings.contentRegion) {
                        ForEach(ContentRegion.allCases.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                } header: {
                    Text("Content")
                } footer: {
                    Text("Changes the language and region for music recommendations and content.")
                }
                
                // MARK: - Playback Section

                Section {
                    Picker("Audio Player", selection: Binding(
                        get: { viewModel.currentPlayerType },
                        set: { newValue in
                            Task {
                                await viewModel.switchPlayer(to: newValue)
                            }
                        }
                    )) {
                        ForEach(AudioPlayerType.availableCases) { player in
                            Text(player.localizedName).tag(player)
                        }
                    }
                    .disabled(viewModel.isSwitchingPlayer)
                } header: {
                    Text("Playback")
                } footer: {
                    Text(viewModel.playbackFooterText)
                }
                
                // MARK: - About Section
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(viewModel.appVersion)
                            .foregroundStyle(.secondary)
                    }
                    
                } header: {
                    Text("About")
                }
                
#if DEBUG
                // MARK: - Debug Section
                
                Section {
                    Button(role: .destructive) {
                        viewModel.resetDefaults()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Defaults")
                            Spacer()
                        }
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Resets all app settings, saved queue, and account info to defaults.")
                }
#endif
            }
            .formStyle(.grouped)
#if os(iOS)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
#endif
        }
        .sheet(isPresented: $viewModel.showLoginSheet) {
            LoginSheet()
        }
    }
}
