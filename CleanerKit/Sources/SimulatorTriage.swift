import Foundation

/// Что считать неиспользуемым.
///
/// Логика вынесена из интерфейса, чтобы её можно было проверить тестами:
/// от неё зависит, что приложение предложит удалить необратимо.
public enum SimulatorTriage {
    /// Симулятор, которого не касались дольше этого срока, считаем забытым.
    public static let staleAfterDays = 90

    public enum Reason: Equatable, Sendable {
        case runtimeMissing            // запустить невозможно в принципе
        case untouched(days: Int)      // просто давно не нужен
    }

    public static func unusedDevices(
        _ devices: [SimulatorDevice],
        now: Date = .now,
        staleAfterDays: Int = staleAfterDays
    ) -> [(device: SimulatorDevice, reason: Reason)] {
        devices.compactMap { device in
            // Запущенный не трогаем ни при каких условиях.
            guard !device.isBooted else { return nil }

            if device.isUnavailable { return (device, .runtimeMissing) }

            guard let lastUsed = device.lastUsed else { return nil }
            // Истекшее время, а не календарные сутки: Calendar на переходе
            // летнего времени теряет день и даёт 119 вместо 120.
            let days = Int(now.timeIntervalSince(lastUsed) / 86_400)
            guard days >= staleAfterDays else { return nil }

            return (device, .untouched(days: days))
        }
    }

    /// Runtime без единого устройства — держать его незачем.
    public static func unusedRuntimes(_ runtimes: [SimulatorRuntime]) -> [SimulatorRuntime] {
        runtimes.filter { $0.deviceCount == 0 && $0.isDeletable }
    }
}
