import CleanerKit
import SwiftUI

struct ContentView: View {
    @State private var model = CleanerModel()
    @State private var section: Section = .files

    private enum Section: String, CaseIterable {
        case files = "Файлы"
        case simulators = "Симуляторы"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            switch section {
            case .files:
                VStack(spacing: 0) {
                    content
                    Divider()
                    footer
                }
            case .simulators:
                SimulatorsView(model: model)
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .task { await model.scan() }
        .sheet(isPresented: $model.isConfirming) { confirmation }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            centered {
                ProgressView()
                Text("Ищем, что можно освободить…").foregroundStyle(.secondary)
            }
        case .removing:
            centered {
                ProgressView()
                Text("Перемещаем в Корзину…").foregroundStyle(.secondary)
            }
        case .finished:
            ReportView(report: model.report) { Task { await model.scan() } }
        case .results:
            categoryList
        }
    }

    private var categoryList: some View {
        List {
            ForEach(model.scans) { scan in
                CategoryRow(
                    scan: scan,
                    isOn: Binding(
                        get: { model.binding(for: scan) },
                        set: { model.toggle(scan, on: $0) }
                    )
                )
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedBytes > 0
                     ? "Выбрано \(model.selectedBytes.formattedBytes)"
                     : "Ничего не выбрано")
                    .font(.headline)
                Text("Найдено \(model.foundBytes.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Сканировать заново") {
                Task { await model.scan() }
            }
            .disabled(model.phase == .scanning || model.phase == .removing)

            Button("Переместить в Корзину…") {
                model.isConfirming = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canRemove)
        }
        .padding(12)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Переместить в Корзину?").font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.selectedScans) { scan in
                    HStack {
                        Text(scan.category.title)
                        Spacer()
                        Text(scan.totalBytes.formattedBytes)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Всего \(model.selectedBytes.formattedBytes) в \(model.selectedItems.count) объектах.")
                .font(.callout)

            Label("Ничего не стирается насовсем: файлы уедут в Корзину, откуда их вернёт кнопка «Положить обратно».",
                  systemImage: "arrow.uturn.backward")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Отмена") { model.isConfirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Переместить") {
                    model.isConfirming = false
                    Task { await model.removeSelected() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CategoryRow: View {
    let scan: CategoryScan
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.category.title)
                    Text(scan.items.isEmpty ? "Пусто" : scan.category.consequence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(scan.totalBytes.formattedBytes)
                    .monospacedDigit()
                    .foregroundStyle(scan.items.isEmpty ? .tertiary : .primary)
            }
        }
        .disabled(scan.items.isEmpty)
        .padding(.vertical, 4)
    }
}

private struct ReportView: View {
    let report: RemovalReport?
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: report?.isClean == true ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(report?.isClean == true ? .green : .orange)

            Text("Перемещено \((report?.movedBytes ?? 0).formattedBytes)")
                .font(.title3.bold())

            if let failed = report?.failed, !failed.isEmpty {
                Text("Не удалось: \(failed.count)")
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failed, id: \.item.id) { outcome in
                            Text("\(outcome.item.url.lastPathComponent) — \(outcome.error ?? "неизвестно")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            Button("Сканировать заново", action: onRescan)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
