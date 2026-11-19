import CoreText
import SwiftUI

@main
struct OdysseyApp: App {
    @State private var model = GameModel()

    init() {
        let fonts = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}

extension Font {
    static func blackletter(_ size: CGFloat) -> Font { .custom("UnifrakturCook-Bold", size: size) }
    static func fell(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "IM_FELL_English_Italic" : "IM_FELL_English_Roman", size: size)
    }
}

extension Color {
    static let parchment = Color(red: 0.95, green: 0.90, blue: 0.78)
    static let ink = Color(red: 0.20, green: 0.13, blue: 0.08)
}
