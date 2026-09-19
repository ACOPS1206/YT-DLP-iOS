import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, korean, english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "시스템 설정"
        case .korean: "한국어"
        case .english: "English"
        }
    }

    private var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "ko"
        return preferred.hasPrefix("en") ? .english : .korean
    }

    func text(_ korean: String, _ english: String) -> String {
        resolved == .english ? english : korean
    }
}

func appText(_ korean: String, _ english: String) -> String {
    let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
    return (AppLanguage(rawValue: raw) ?? .system).text(korean, english)
}
