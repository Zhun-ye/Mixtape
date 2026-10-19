//
//  SignInRedirectorView.swift
//  Mixtape
//
//  A simple prompt view that redirects users to sign in.
//

import SwiftUI

struct SignInRedirectorView: View {
    let viewModel: SignInRedirectorViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Sign In to YouTube Music")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                viewModel.getStarted()
            } label: {
                Text("Get Started")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SignInRedirectorView(viewModel: SignInRedirectorViewModel())
}
