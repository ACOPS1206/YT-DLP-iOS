import SwiftUI

@main
struct YTDLPGUIApp: App {
    @State private var model = DownloadModel()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("accentColor") private var accentColor = AccentColorChoice.monochrome.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .tint((AccentColorChoice(rawValue: accentColor) ?? .monochrome).color)
                .id(appLanguage)
        }
    }
}
