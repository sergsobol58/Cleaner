import Observation
import SwiftUI

/// Which section is showing.
///
/// Lifted out of the view because the menu bar needs it. A command that
/// cannot reach the selection cannot move it, and a Mac app whose sections
/// are unreachable from the keyboard is one the guidelines call broken.
@MainActor
@Observable
final class Navigation {
    var section: AppSection = .overview
}

/// Grouped rather than listed flat: four peers in a row gave no hint that two
/// of them are about the disk and two about what is running.
enum AppSection: Int, Hashable, CaseIterable, Identifiable {
    case overview = 1, files, simulators, memory, processor

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .files: "Files"
        case .simulators: "Simulators"
        case .memory: "Memory"
        case .processor: "Processor"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .files: "internaldrive"
        case .simulators: "iphone"
        case .memory: "memorychip"
        case .processor: "cpu"
        }
    }

    /// Cmd-1 through Cmd-5, in the order the sidebar lists them.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character("\(rawValue)"))
    }

    static let disk: [AppSection] = [.files, .simulators]
    static let system: [AppSection] = [.memory, .processor]
}
