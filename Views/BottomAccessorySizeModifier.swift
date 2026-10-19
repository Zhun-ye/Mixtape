//
//  BottomAccessorySizeModifier.swift
//  Mixtape
//
//  ViewModifier for constraining bottom accessory size on tablets.
//

import SwiftUI

// MARK: - BottomAccessorySizeModifier

#if os(iOS)
struct BottomAccessorySizeModifier: ViewModifier {
    let size = UIScreen.current?.bounds.size ?? .zero

    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            content
                .frame(maxWidth: min(size.width, size.height) * 0.7)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func bottomAccessorySizeConstrained() -> some View {
        modifier(BottomAccessorySizeModifier())
    }
}

extension UIWindow {
    static var current: UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window.isKeyWindow { return window }
            }
        }
        return nil
    }
}


extension UIScreen {
    static var current: UIScreen? {
        UIWindow.current?.screen
    }
}

#endif
