import CleanerKit
import SwiftUI

/// What is using the processor, in the same shape as the memory section: one
/// bar over a shared total, then the list that explains it.
struct ProcessorView: View {
    @Bindable var model: SystemModel

    var body: some View {
        ProcessSection(model: model, sorting: .processor) {
            if let processor = model.processor { bar(processor) }
        }
    }

    private func bar(_ processor: ProcessorSnapshot) -> some View {
        ResourceBar(
            headline: Text("\(percent(processor.busyPercent)) of \(processor.coreCount, format: .number) cores busy"),
            warning: warning(processor),
            segments: [
                // User work is what you asked for; system work is the kernel
                // doing it. Separating them says whether a busy machine is
                // busy with your work or with its own overhead.
                .init(title: "Applications", color: .accentColor,
                      fraction: processor.userPercent / 100,
                      caption: percent(processor.userPercent)),
                .init(title: "System", color: .orange,
                      fraction: processor.systemPercent / 100,
                      caption: percent(processor.systemPercent)),
                .init(title: "Idle", color: .secondary.opacity(0.4),
                      fraction: processor.idlePercent / 100,
                      caption: percent(processor.idlePercent)),
            ])
    }

    /// A load average above the core count means work is queueing: more
    /// processes want a core than there are cores to give.
    private func warning(_ processor: ProcessorSnapshot) -> String? {
        guard processor.isQueueing, let oneMinute = processor.loadAverage.first else {
            return nil
        }
        return String(localized: "Load \(oneMinute, format: .number.precision(.fractionLength(2))) on \(processor.coreCount, format: .number) cores")
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
