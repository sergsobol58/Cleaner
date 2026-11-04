import SwiftUI

@main
struct CleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = CleanerModel()
    @State private var system = SystemModel()
    @State private var settings = AppSettings()
    @State private var navigation = Navigation()

    var body: some Scene {
        WindowGroup("Cleaner", id: Self.mainWindowID) {
            ContentView(model: model, system: system, navigation: navigation)
                .task { settings.applyActivationPolicy() }
        }
        .windowResizability(.contentMinSize)
        .commands { menus }

        MenuBarExtra {
            MenuBarView(model: model, settings: settings)
        } label: {
            Image(systemName: "wand.and.sparkles")
        }
        .menuBarExtraStyle(.window)
    }

    /// Everything the app does, reachable without the mouse. A Mac app whose
    /// actions live only on buttons is one a keyboard user cannot drive, and
    /// the menu bar is where people look for a command before anywhere else.
    @CommandsBuilder
    private var menus: some Commands {
        CommandMenu("Cleaner") {
            Button("Scan Again") { Task { await model.scan() } }
                .keyboardShortcut("r")
                .disabled(model.phase == .scanning || model.phase == .removing)

            Button("Move to Trash…") { model.isConfirming = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canRemove)

            Divider()

            Button("Add a Folder…") { navigation.section = .files }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .toolbar) {
            Divider()
            ForEach(AppSection.allCases) { item in
                Button(item.title) { navigation.section = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }
        }
    }

    static let mainWindowID = "main"
}
