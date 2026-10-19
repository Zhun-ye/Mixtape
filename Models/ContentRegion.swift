//
//  ContentRegion.swift
//  Mixtape
//

import SwiftUI

/// Supported regions for YouTube Music API.
enum ContentRegion: String, CaseIterable, Identifiable {
    case unitedStates = "US"
    case unitedKingdom = "GB"
    case canada = "CA"
    case australia = "AU"
    case germany = "DE"
    case france = "FR"
    case spain = "ES"
    case italy = "IT"
    case netherlands = "NL"
    case brazil = "BR"
    case mexico = "MX"
    case japan = "JP"
    case southKorea = "KR"
    case india = "IN"
    case russia = "RU"
    case turkey = "TR"
    case poland = "PL"
    case sweden = "SE"
    case norway = "NO"
    case denmark = "DK"
    case finland = "FI"
    case taiwan = "TW"
    case hongKong = "HK"
    case singapore = "SG"
    case indonesia = "ID"
    case malaysia = "MY"
    case philippines = "PH"
    case thailand = "TH"
    case vietnam = "VN"
    case saudiArabia = "SA"
    case unitedArabEmirates = "AE"
    case israel = "IL"
    case southAfrica = "ZA"
    case argentina = "AR"
    case chile = "CL"
    case colombia = "CO"

    var id: String { rawValue }

    /// Localization key for the region name.
    private var localizationKey: String {
        switch self {
        case .unitedStates: "United States"
        case .unitedKingdom: "United Kingdom"
        case .canada: "Canada"
        case .australia: "Australia"
        case .germany: "Germany"
        case .france: "France"
        case .spain: "Spain"
        case .italy: "Italy"
        case .netherlands: "Netherlands"
        case .brazil: "Brazil"
        case .mexico: "Mexico"
        case .japan: "Japan"
        case .southKorea: "South Korea"
        case .india: "India"
        case .russia: "Russia"
        case .turkey: "Turkey"
        case .poland: "Poland"
        case .sweden: "Sweden"
        case .norway: "Norway"
        case .denmark: "Denmark"
        case .finland: "Finland"
        case .taiwan: "Taiwan"
        case .hongKong: "Hong Kong"
        case .singapore: "Singapore"
        case .indonesia: "Indonesia"
        case .malaysia: "Malaysia"
        case .philippines: "Philippines"
        case .thailand: "Thailand"
        case .vietnam: "Vietnam"
        case .saudiArabia: "Saudi Arabia"
        case .unitedArabEmirates: "United Arab Emirates"
        case .israel: "Israel"
        case .southAfrica: "South Africa"
        case .argentina: "Argentina"
        case .chile: "Chile"
        case .colombia: "Colombia"
        }
    }

    var displayName: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }

    /// Localized display name as String for sorting.
    var localizedName: String {
        String(localized: String.LocalizationValue(localizationKey))
    }

    /// Returns the region matching the system locale, or United States if no match.
    static var systemDefault: ContentRegion {
        guard let regionCode = Locale.current.region?.identifier else {
            return .unitedStates
        }
        return ContentRegion(rawValue: regionCode) ?? .unitedStates
    }
}
