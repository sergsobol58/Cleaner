import SwiftUI

@main
struct CleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = CleanerModel()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup("Cleaner", id: Self.mainWindowID) {
            ContentView(model: model)
                .task { settings.applyActivationPolicy() }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(model: model, settings: settings)
        } label: {
            Image(systemName: "wand.and.sparkles")
        }
        .menuBarExtraStyle(.window)
    }

    static let mainWindowID = "main"
}
