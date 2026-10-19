//
//  CGFloat+Layout.swift
//  Mixtape
//

import SwiftUI

// MARK: - Layout Constants

extension CGFloat {
    /// Spacing between items in a section row.
    #if os(iOS)
    static let sectionItemSpacing: CGFloat = 12
    #else
    static let sectionItemSpacing: CGFloat = 22
    #endif

    /// Default card size for playlist items.
    #if os(iOS)
    static let defaultCardSize: CGFloat = 160
    #else
    static let defaultCardSize: CGFloat = 230
    #endif

    /// Minimum adaptive grid item size for standard cards.
    #if os(iOS)
    static let adaptiveGridMinimum: CGFloat = 140
    #else
    static let adaptiveGridMinimum: CGFloat = 180
    #endif

    /// Maximum adaptive grid item size for standard cards.
    #if os(iOS)
    static let adaptiveGridMaximum: CGFloat = 200
    #else
    static let adaptiveGridMaximum: CGFloat = 270
    #endif

    /// Minimum adaptive grid item size for artist cards (circular).
    #if os(iOS)
    static let adaptiveArtistGridMinimum: CGFloat = 140
    #else
    static let adaptiveArtistGridMinimum: CGFloat = 210
    #endif

    /// Maximum adaptive grid item size for artist cards (circular).
    #if os(iOS)
    static let adaptiveArtistGridMaximum: CGFloat = 180
    #else
    static let adaptiveArtistGridMaximum: CGFloat = 250
    #endif
}
