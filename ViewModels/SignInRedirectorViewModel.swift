//
//  SignInRedirectorViewModel.swift
//  Mixtape
//

import Foundation
import SwiftUINavigation

protocol SignInRedirectorViewModelDelegate: AnyObject {
    func didRequestSignIn()
}

@MainActor
@Observable
final class SignInRedirectorViewModel: HashableObject {
    weak var delegate: SignInRedirectorViewModelDelegate?

    func getStarted() {
        delegate?.didRequestSignIn()
    }
}
