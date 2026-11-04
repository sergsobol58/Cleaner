import CleanerKit
import SwiftUI

/// The half of the memory and processor sections that is the same in both:
/// the process list, what is selected, and asking it to quit.
///
/// There is no button here that frees memory or unloads the processor by
/// itself, because no such button can exist honestly. macOS hands cache back
/// the moment anything needs it, and the tools that claim to "free RAM"
/// either flush the disk cache — making the machine slower — or allocate a
/// block to push everything else into swap, which is worse. What frees a
/// resource is whatever is holding it letting go, so that is what this offers.
struct ProcessSection<Header: View>: View {
    @Bindable var model: SystemModel
    let sorting: SystemModel.Sorting
    @ViewBuilder var header: Header

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task { await model.watch() }
        .sheet(isPresented: $model.isConfirming) { ConfirmQuit(model: model) }
        .sheet(isPresented: Binding(get: { model.report != nil },
                                    set: { if !$0 { model.dismissReport() } })) {
            QuitOutcomeView(model: model)
        }
    }

    private var list: some View {
        List {
            ForEach(model.sorted(by: sorting)) { process in
                ProcessRow(process: process, model: model, sorting: sorting)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedBytes > 0
                     ? "Selected \(model.selectedBytes.formattedBytes) in \(model.selected.count.processesText)"
                     : "Nothing selected")
                    .font(.headline)
                Text("Quitting is what frees a resource; nothing else frees it honestly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit…") {
                model.acknowledged = false
                model.isConfirming = true
            }
            .disabled(model.selected.isEmpty)
        }
    }
}

/// The figure that matters for the section you are in comes first and in
/// full weight; the other is still there, because a process heavy on one is
/// often the reason you are looking at the other.
private struct ProcessRow: View {
    let process: RunningProcess
    let model: SystemModel
    let sorting: SystemModel.Sorting

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.isSelected(process) },
            set: { model.setSelected(process, $0) }
        )) {
            HStack(alignment: .firstTextBaseline) {
                Text(process.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: "\(process.pid)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer()

                if let protection = process.protection {
                    Text(protection.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                processorFigure
                    .frame(width: 60, alignment: .trailing)
                memoryFigure
                    .frame(width: 84, alignment: .trailing)
            }
        }
        .disabled(!process.canQuit)
        .padding(.vertical, 1)
    }

    private var processorFigure: some View {
        Text(process.cpuPercent, format: .number.precision(.fractionLength(1)))
            .monospacedDigit()
            .font(sorting == .processor ? .body : .caption)
            .foregroundStyle(tint(for: .processor))
    }

    private var memoryFigure: some View {
        Text(process.residentBytes.formattedBytes)
            .monospacedDigit()
            .font(sorting == .memory ? .body : .caption)
            .foregroundStyle(tint(for: .memory))
    }

    private func tint(for figure: SystemModel.Sorting) -> AnyShapeStyle {
        if figure == .processor, process.cpuPercent >= 50 { return AnyShapeStyle(.orange) }
        return sorting == figure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
}

private struct ConfirmQuit: View {
    @Bindable var model: SystemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ask these to quit", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.selected) { process in
                        HStack {
                            Text(verbatim: "• \(process.name)").font(.callout)
                            Spacer()
                            Text(process.residentBytes.formattedBytes)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)

            Text("\(model.selectedBytes.formattedBytes) held in total.")
                .font(.callout.bold())

            Text("Each one is asked to quit the same way the Quit menu asks, so an application with unsaved work can refuse and prompt you. Anything that does not ask first will lose what is open in it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("I understand unsaved work may be lost", isOn: $model.acknowledged)

            HStack {
                Spacer()
                Button("Cancel") { model.isConfirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Quit") {
                    model.isConfirming = false
                    Task { await model.quitSelected() }
                }
                .disabled(!model.canQuit)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct QuitOutcomeView: View {
    let model: SystemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asked \(model.report?.asked.count ?? 0, format: .number) to quit")
                .font(.title3.bold())

            Text("An application may take a moment, or stop to ask you about unsaved work.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let refused = model.report?.refused, !refused.isEmpty {
                Text("Refused: \(refused.count, format: .number)").font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(refused, id: \.process.id) { outcome in
                            Text(verbatim: "\(outcome.process.name) — \(outcome.error ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Spacer()
                Button("Done") { model.dismissReport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// The bar both sections put above their list: one row of coloured segments
/// over a shared total, with the numbers spelled out underneath.
struct ResourceBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let color: Color
        let fraction: Double
        let caption: String
    }

    let headline: Text
    let warning: String?
    let segments: [Segment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                headline.font(.headline)
                Spacer()
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        Rectangle().fill(segment.color)
                            .frame(width: max(0, geometry.size.width * segment.fraction))
                    }
                    Rectangle().fill(.quinary)
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.title).foregroundStyle(.secondary)
                        Text(segment.caption).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
