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
        case .system: return Self.localized("Как в macOS")
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

    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
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
