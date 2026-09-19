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

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case monochrome, blue, purple, pink, orange, green, yellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome: "모노크롬"
        case .blue: "블루"
        case .purple: "퍼플"
        case .pink: "핑크"
        case .orange: "오렌지"
        case .green: "그린"
        case .yellow: "옐로"
        }
    }

    var color: Color {
        switch self {
        case .monochrome: .primary
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .yellow: .yellow
        }
    }
}

func appText(_ korean: String, _ english: String) -> String {
    let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
    return (AppLanguage(rawValue: raw) ?? .system).text(korean, english)
}
