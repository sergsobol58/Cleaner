import SwiftUI

@main
struct CleanerApp: App {
    var body: some Scene {
        WindowGroup("Cleaner") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
