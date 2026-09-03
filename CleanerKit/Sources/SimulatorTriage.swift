import Foundation

/// What counts as unused.
///
/// Kept out of the interface so it can be tested: this decides what the app
/// offers to delete irreversibly.
public enum SimulatorTriage {
    /// A simulator untouched for longer than this is treated as forgotten.
    public static let staleAfterDays = 90

    public enum Reason: Equatable, Sendable {
        case runtimeMissing            // cannot be launched at all
        case untouched(days: Int)      // simply not needed for a long time
    }

    public static func unusedDevices(
        _ devices: [SimulatorDevice],
        now: Date = .now,
        staleAfterDays: Int = staleAfterDays
    ) -> [(device: SimulatorDevice, reason: Reason)] {
        devices.compactMap { device in
            // A running simulator is never suggested, whatever its age.
            guard !device.isBooted else { return nil }

            if device.isUnavailable { return (device, .runtimeMissing) }

            guard let lastUsed = device.lastUsed else { return nil }
            // Elapsed time rather than calendar days: Calendar loses a day
            // across a daylight-saving change and reports 119 instead of 120.
            let days = Int(now.timeIntervalSince(lastUsed) / 86_400)
            guard days >= staleAfterDays else { return nil }

            return (device, .untouched(days: days))
        }
    }

    /// A runtime with no devices at all is not worth keeping.
    public static func unusedRuntimes(_ runtimes: [SimulatorRuntime]) -> [SimulatorRuntime] {
        runtimes.filter { $0.deviceCount == 0 && $0.isDeletable }
    }
}
