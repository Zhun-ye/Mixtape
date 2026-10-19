//
//  ContentLanguage.swift
//  Mixtape
//

import Foundation

/// Supported languages for YouTube Music API.
enum ContentLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case arabic = "ar"
    case hindi = "hi"
    case turkish = "tr"
    case polish = "pl"
    case swedish = "sv"
    case norwegian = "no"
    case danish = "da"
    case finnish = "fi"
    case czech = "cs"
    case greek = "el"
    case hebrew = "he"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case malay = "ms"

    var id: String { rawValue }

    /// Language code for YouTube Music API (hl parameter).
    var apiLanguageCode: String {
        switch self {
        case .chineseSimplified: "zh"
        case .chineseTraditional: "zh"
        default: rawValue
        }
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        case .russian: "Русский"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .arabic: "العربية"
        case .hindi: "हिन्दी"
        case .turkish: "Türkçe"
        case .polish: "Polski"
        case .swedish: "Svenska"
        case .norwegian: "Norsk"
        case .danish: "Dansk"
        case .finnish: "Suomi"
        case .czech: "Čeština"
        case .greek: "Ελληνικά"
        case .hebrew: "עברית"
        case .thai: "ไทย"
        case .vietnamese: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
        case .malay: "Bahasa Melayu"
        }
    }

    /// Returns the language matching the system locale, or English if no match.
    static var systemDefault: ContentLanguage {
        let locale = Locale.current
        guard let languageCode = locale.language.languageCode?.identifier else {
            return .english
        }

        // Handle Chinese script variants
        if languageCode == "zh" {
            let script = locale.language.script?.identifier
            if script == "Hant" {
                return .chineseTraditional
            }
            return .chineseSimplified
        }

        return ContentLanguage(rawValue: languageCode) ?? .english
    }
}
