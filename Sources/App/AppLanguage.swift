import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ru
    case be

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ru: return "Русский"
        case .be: return "Беларуская"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system: return ""
        case .en: return "en"
        case .ru: return "ru"
        case .be: return "be"
        }
    }

    var bundle: Bundle {
        let languageCode = self == .system ? Locale.preferredLanguages.first ?? "en" : self.localeIdentifier
        if self == .system {
            return Bundle.main
        }
        let path = Bundle.main.path(forResource: languageCode, ofType: "lproj")
        return path.flatMap(Bundle.init(path:)) ?? Bundle.main
    }

    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.localeIdentifier], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    static func localized(_ key: String, fallback: String? = nil) -> String {
        let language = current
        let bundle: Bundle
        if language == .system {
            bundle = Bundle.main
        } else if let lproj = Bundle.main.path(forResource: language.localeIdentifier, ofType: "lproj") {
            bundle = Bundle(path: lproj) ?? Bundle.main
        } else {
            bundle = Bundle.main
        }
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: fallback ?? key, comment: "")
    }
}
