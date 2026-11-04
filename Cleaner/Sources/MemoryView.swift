import CleanerKit
import SwiftUI

/// What is holding memory, and what can be asked to let go of it.
struct MemoryView: View {
    @Bindable var model: SystemModel

    var body: some View {
        ProcessSection(model: model, sorting: .memory) {
            if let memory = model.memory { bar(memory) }
        }
    }

    private func bar(_ memory: MemorySnapshot) -> some View {
        ResourceBar(
            headline: Text("\(memory.used.formattedBytes) of \(memory.total.formattedBytes) in use"),
            warning: warning(memory),
            segments: [
                .init(title: "Applications", color: .accentColor,
                      fraction: share(memory.app, of: memory.total),
                      caption: memory.app.formattedBytes),
                .init(title: "Compressed", color: .orange,
                      fraction: share(memory.compressed, of: memory.total),
                      caption: memory.compressed.formattedBytes),
                .init(title: "Wired", color: .gray,
                      fraction: share(memory.wired, of: memory.total),
                      caption: memory.wired.formattedBytes),
                .init(title: "Cached files", color: .secondary.opacity(0.4),
                      fraction: share(memory.cached, of: memory.total),
                      caption: memory.cached.formattedBytes),
            ])
    }

    /// Swap is named outright because the pressure level hides it: the kernel
    /// reports normal while writing gigabytes to disk, because it is coping —
    /// by making everything slower.
    private func warning(_ memory: MemorySnapshot) -> String? {
        guard memory.isStrained else { return nil }
        return memory.swapUsed > 1_073_741_824
            ? String(localized: "\(memory.swapUsed.formattedBytes) swapped to disk")
            : String(localized: "Memory is under pressure")
    }

    private func share(_ part: Int64, of whole: Int64) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }
}
