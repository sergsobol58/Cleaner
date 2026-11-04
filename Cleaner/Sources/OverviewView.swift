import CleanerKit
import SwiftUI

/// Where the app opens: the three numbers worth knowing, in the size they
/// deserve.
///
/// The headline figure used to live in twelve-point text at the bottom of a
/// list — the most important number on screen set in the smallest type on
/// screen. Everything here is a summary of work done elsewhere; nothing can
/// be deleted from this screen, which is why it is safe to lead with.
struct OverviewView: View {
    let model: CleanerModel
    let system: SystemModel
    let goTo: (AppSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headline
                disk
                memory
                processor
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .task { await system.watch() }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.foundBytes.formattedBytes)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if model.phase == .scanning {
                Text("Looking for space to reclaim…").foregroundStyle(.secondary)
            } else {
                Text("can be moved to the Trash").foregroundStyle(.secondary)
            }

            Button("Review and clean…") { goTo(.files) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.foundBytes == 0)
                .padding(.top, 6)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var disk: some View {
        if let volume = model.volume {
            Card(title: "Disk", symbol: "internaldrive", action: { goTo(.files) }) {
                ResourceBar(
                    headline: Text("\(volume.free.formattedBytes) free of \(volume.total.formattedBytes)"),
                    warning: volume.free < 10_737_418_240
                        ? String(localized: "Running low") : nil,
                    segments: [
                        .init(title: "In use", color: .accentColor,
                              fraction: fraction(volume.total - volume.free, volume.total),
                              caption: (volume.total - volume.free).formattedBytes),
                        .init(title: "Purgeable", color: .orange,
                              fraction: fraction(volume.purgeable, volume.total),
                              caption: volume.purgeable.formattedBytes),
                    ])
            }
        }
    }

    @ViewBuilder
    private var memory: some View {
        if let snapshot = system.memory {
            Card(title: "Memory", symbol: "memorychip", action: { goTo(.memory) }) {
                ResourceBar(
                    headline: Text("\(snapshot.used.formattedBytes) of \(snapshot.total.formattedBytes) in use"),
                    warning: snapshot.swapUsed > 1_073_741_824
                        ? String(localized: "\(snapshot.swapUsed.formattedBytes) swapped to disk") : nil,
                    segments: [
                        .init(title: "Applications", color: .accentColor,
                              fraction: fraction(snapshot.app, snapshot.total),
                              caption: snapshot.app.formattedBytes),
                        .init(title: "Compressed", color: .orange,
                              fraction: fraction(snapshot.compressed, snapshot.total),
                              caption: snapshot.compressed.formattedBytes),
                        .init(title: "Wired", color: .gray,
                              fraction: fraction(snapshot.wired, snapshot.total),
                              caption: snapshot.wired.formattedBytes),
                        .init(title: "Cached files", color: .secondary.opacity(0.4),
                              fraction: fraction(snapshot.cached, snapshot.total),
                              caption: snapshot.cached.formattedBytes),
                    ])
            }
        }
    }

    @ViewBuilder
    private var processor: some View {
        if let snapshot = system.processor {
            Card(title: "Processor", symbol: "cpu", action: { goTo(.processor) }) {
                ResourceBar(
                    headline: Text("\(percent(snapshot.busyPercent)) of \(snapshot.coreCount, format: .number) cores busy"),
                    warning: nil,
                    segments: [
                        .init(title: "Applications", color: .accentColor,
                              fraction: snapshot.userPercent / 100,
                              caption: percent(snapshot.userPercent)),
                        .init(title: "System", color: .orange,
                              fraction: snapshot.systemPercent / 100,
                              caption: percent(snapshot.systemPercent)),
                    ])
            }
        }
    }

    private func fraction(_ part: Int64, _ whole: Int64) -> Double {
        whole > 0 ? Double(max(0, part)) / Double(whole) : 0
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// A titled block that leads somewhere.
///
/// The heading lives inside the surface it titles. It used to sit above it,
/// because the bar brought a background of its own and the card drew a second
/// one around it — leaving the title stranded outside the box it named and
/// the chevron floating past the card's right edge.
private struct Card<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            content
        }
        .cardSurface()
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint.opacity(isHovered ? 0.5 : 0), lineWidth: 1)
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}
