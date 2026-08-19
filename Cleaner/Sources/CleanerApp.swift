import SwiftUI

@main
struct CleanerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Cleaner")
                .frame(width: 560, height: 360)
        }
        .windowResizability(.contentSize)
    }
}
