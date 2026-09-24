import CleanerKit
import SwiftUI

/// Simulators are a deliberately separate section: removal here is
/// irreversible, and mixing it into the same list as reversible cleaning
/// would hide that.
struct SimulatorsView: View {
    @Bindable var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            if model.simulatorsLoaded {
                list
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Asking simctl…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task { if !model.simulatorsLoaded { await model.loadSimulators() } }
        .sheet(isPresented: $model.isConfirmingSimulators) { confirmation }
    }

    private var list: some View {
        List {
            Section("Simulators") {
                ForEach(model.devices) { device in
                    row(title: device.name,
                        note: model.note(for: device),
                        bytes: device.sizeBytes,
                        accent: model.isStale(device),
                        disabled: device.isBooted,
                        isOn: Binding(
                            get: { model.deviceSelection.contains(device.id) },
                            set: { on in
                                if on { model.deviceSelection.insert(device.id) }
                                else { model.deviceSelection.remove(device.id) }
                            }))
                }
            }

            Section("Runtime images") {
                ForEach(model.runtimes) { runtime in
                    row(title: runtime.name,
                        note: note(for: runtime),
                        bytes: runtime.sizeBytes,
                        accent: runtime.deviceCount == 0 && runtime.isDeletable,
                        disabled: !runtime.isDeletable,
                        isOn: Binding(
                            get: { model.runtimeSelection.contains(runtime.id) },
                            set: { on in
                                if on { model.runtimeSelection.insert(runtime.id) }
                                else { model.runtimeSelection.remove(runtime.id) }
                            }))
                }
            }

            if !model.simulatorFailures.isEmpty {
                Section("Failed") {
                    ForEach(model.simulatorFailures, id: \.self) { failure in
                        Text(failure).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func note(for runtime: SimulatorRuntime) -> String {
        if !runtime.isDeletable { return String(localized: "the system does not allow removing this") }
        if runtime.deviceCount == 0 { return String(localized: "not used by any device") }
        return runtime.deviceCount.devicesText
    }

    private func row(title: String, note: String, bytes: Int64,
                     accent: Bool, disabled: Bool, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(accent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Spacer()
                Text(bytes.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .disabled(disabled)
        .padding(.vertical, 2)
    }

    private var footer: some View {
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSimulatorBytes > 0
                     ? "Selected \(model.selectedSimulatorBytes.formattedBytes)"
                     : "Nothing selected")
                    .font(.headline)
                Text(model.selectedSimulatorBytes > 0
                     ? String(localized: "Removal here is irreversible — simctl does not use the Trash")
                     : model.unusedExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Select unused") { model.selectUnused() }
                .disabled(!model.hasUnused)
                .help(model.unusedExplanation)

            Button("Delete…") {
                model.acknowledgedIrreversible = false
                model.isConfirmingSimulators = true
            }
            .disabled(model.selectedSimulatorBytes == 0)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Delete permanently", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.selectedDevices) { device in
                    Text("• \(device.name) — \(device.sizeBytes.formattedBytes)").font(.callout)
                }
                ForEach(model.selectedRuntimes) { runtime in
                    Text("• \(runtime.name) — \(runtime.sizeBytes.formattedBytes)").font(.callout)
                }
            }

            Text("\(model.selectedSimulatorBytes.formattedBytes) in total.")
                .font(.callout.bold())

            Text("Xcode recreates a simulator in seconds, but the apps installed in it and their data are gone. A runtime image has to be downloaded again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("I understand this does not go to the Trash", isOn: $model.acknowledgedIrreversible)

            HStack {
                Spacer()
                Button("Cancel") { model.isConfirmingSimulators = false }
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    model.isConfirmingSimulators = false
                    Task { await model.deleteSelectedSimulators() }
                }
                .disabled(!model.canDeleteSimulators)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
