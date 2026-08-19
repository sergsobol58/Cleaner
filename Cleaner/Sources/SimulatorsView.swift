import CleanerKit
import SwiftUI

/// Раздел симуляторов вынесен отдельно намеренно: здесь удаление необратимо,
/// и смешивать его с обратимой чисткой в один список нельзя.
struct SimulatorsView: View {
    @Bindable var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            if model.simulatorsLoaded {
                list
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Опрашиваем simctl…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .task { if !model.simulatorsLoaded { await model.loadSimulators() } }
        .sheet(isPresented: $model.isConfirmingSimulators) { confirmation }
    }

    private var list: some View {
        List {
            Section("Симуляторы") {
                ForEach(model.devices) { device in
                    row(title: device.name,
                        note: device.isBooted ? "запущен — удалить нельзя"
                            : device.isUnavailable ? "runtime не установлен, запустить нельзя"
                            : device.runtime,
                        bytes: device.sizeBytes,
                        accent: device.isUnavailable,
                        disabled: device.isBooted,
                        isOn: Binding(
                            get: { model.deviceSelection.contains(device.id) },
                            set: { on in
                                if on { model.deviceSelection.insert(device.id) }
                                else { model.deviceSelection.remove(device.id) }
                            }))
                }
            }

            Section("Runtime-образы") {
                ForEach(model.runtimes) { runtime in
                    row(title: runtime.name,
                        note: !runtime.isDeletable ? "система не разрешает удаление"
                            : runtime.deviceCount == 0 ? "ни одного устройства не использует"
                            : "устройств: \(runtime.deviceCount)",
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
                Section("Не удалось") {
                    ForEach(model.simulatorFailures, id: \.self) { failure in
                        Text(failure).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSimulatorBytes > 0
                     ? "Выбрано \(model.selectedSimulatorBytes.formattedBytes)"
                     : "Ничего не выбрано")
                    .font(.headline)
                Text("Удаление здесь необратимо — Корзину simctl не использует")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Отметить неиспользуемые") { model.selectUnused() }
                .disabled(model.unusedDevices.isEmpty && model.unusedRuntimes.isEmpty)

            Button("Удалить…") {
                model.acknowledgedIrreversible = false
                model.isConfirmingSimulators = true
            }
            .disabled(model.selectedSimulatorBytes == 0)
        }
        .padding(12)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Удалить безвозвратно", systemImage: "exclamationmark.triangle.fill")
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

            Text("Всего \(model.selectedSimulatorBytes.formattedBytes).")
                .font(.callout.bold())

            Text("Симулятор Xcode пересоздаст за секунды, но установленные в нём приложения и их данные пропадут. Runtime-образ придётся качать заново.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Понимаю, что в Корзину это не попадёт", isOn: $model.acknowledgedIrreversible)

            HStack {
                Spacer()
                Button("Отмена") { model.isConfirmingSimulators = false }
                    .keyboardShortcut(.cancelAction)
                Button("Удалить") {
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
