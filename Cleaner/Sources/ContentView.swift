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
                if scan.items.isEmpty {
                    CategoryHeader(scan: scan, model: model)
                } else {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { model.isExpanded(scan) },
                            set: { model.setExpanded(scan, $0) }
                        )
                    ) {
                        detail(of: scan)
                    } label: {
                        CategoryHeader(scan: scan, model: model)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    /// Категория с одним корнем показывает файлы сразу; с несколькими —
    /// сперва группы, иначе имена вроде "content-v2" ничего не значат.
    @ViewBuilder
    private func detail(of scan: CategoryScan) -> some View {
        let groups = scan.groups
        if groups.count == 1 {
            ForEach(groups[0].items) { item in
                ItemRow(item: item, model: model)
            }
        } else {
            ForEach(groups) { group in
                GroupRow(group: group, model: model)
                ForEach(group.items) { item in
                    ItemRow(item: item, model: model, indent: 32)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedBytes > 0
                     ? "Выбрано \(model.selectedBytes.formattedBytes) · объектов: \(model.selectedItems.count)"
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
                ForEach(model.touchedScans) { scan in
                    HStack {
                        Text(scan.category.title)
                        Text("\(model.selectedCount(in: scan)) из \(scan.items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.selectedBytes(in: scan).formattedBytes)
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

/// Галочка категории умеет промежуточное состояние: нажатие по частично
/// выбранной категории добирает остаток.
private struct TriStateBox: View {
    let coverage: Coverage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(coverage == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .imageScale(.large)
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch coverage {
        case .none:    "square"
        case .partial: "minus.square.fill"
        case .all:     "checkmark.square.fill"
        }
    }
}

private struct CategoryHeader: View {
    let scan: CategoryScan
    let model: CleanerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TriStateBox(coverage: model.coverage(of: scan.items)) {
                model.toggleAll(scan.items)
            }
            .disabled(scan.items.isEmpty)

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.category.title)
                Text(scan.items.isEmpty
                     ? "Пусто"
                     : "\(scan.category.consequence) · объектов: \(scan.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(scan.totalBytes.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(scan.items.isEmpty ? .tertiary : .primary)
        }
        .padding(.vertical, 4)
    }
}

private struct GroupRow: View {
    let group: ScanGroup
    let model: CleanerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TriStateBox(coverage: model.coverage(of: group.items)) {
                model.toggleAll(group.items)
            }
            Text(model.title(for: group.root))
                .font(.callout.weight(.medium))
            Text("объектов: \(group.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(group.totalBytes.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.vertical, 2)
    }
}

private struct ItemRow: View {
    let item: ScanItem
    let model: CleanerModel
    var indent: CGFloat = 12

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.isSelected(item) },
            set: { model.setSelected(item, $0) }
        )) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(model.describe(item))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(item.sizeBytes.formattedBytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
        .padding(.leading, indent)
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
