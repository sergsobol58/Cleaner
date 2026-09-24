import CleanerKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: CleanerModel
    @State private var section: Section = .files

    private enum Section: Hashable, CaseIterable {
        case files, simulators

        var title: LocalizedStringKey {
            switch self {
            case .files: "Files"
            case .simulators: "Simulators"
            }
        }
    }

    var body: some View {
        Group {
            switch section {
            case .files:
                VStack(spacing: 0) {
                    if model.isUnderReporting { PermissionBanner(model: model) }
                    content
                }
                .safeAreaInset(edge: .bottom) { footer }
            case .simulators:
                SimulatorsView(model: model)
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .task { await model.scanIfNeeded() }
        .sheet(isPresented: $model.isConfirming) { confirmation }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            centered {
                ProgressView()
                Text("Looking for space to reclaim…").foregroundStyle(.secondary)
            }
        case .removing:
            centered {
                ProgressView()
                Text("Moving to the Trash…").foregroundStyle(.secondary)
            }
        case .finished:
            ReportView(report: model.report,
                       trashBytes: model.trashBytes,
                       onOpenTrash: { model.openTrash() },
                       onRescan: { Task { await model.scan() } })
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

    /// A category with one root shows its files directly; with several it
    /// shows groups first, otherwise a name like "content-v2" means nothing.
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
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedBytes > 0
                     ? "Selected \(model.selectedBytes.formattedBytes) · \(model.selectedItems.count.itemsText)"
                     : "Nothing selected")
                    .font(.headline)
                Text("Found \(model.foundBytes.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Scan again") {
                Task { await model.scan() }
            }
            .disabled(model.phase == .scanning || model.phase == .removing)

            Button("Move to Trash…") {
                model.isConfirming = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canRemove)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move to the Trash?").font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.touchedScans) { scan in
                    HStack {
                        Text(scan.category.title)
                        Text("\(model.selectedCount(in: scan)) of \(scan.items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.selectedBytes(in: scan).formattedBytes)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Total: \(model.selectedBytes.formattedBytes) · \(model.selectedItems.count.itemsText)")
                .font(.callout)

            Label("Nothing is erased for good: the files go to the Trash, and Finder's Put Back brings them home. The space itself is freed once you empty the Trash.",
                  systemImage: "arrow.uturn.backward")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { model.isConfirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Move") {
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

/// The category checkbox carries a partial state: clicking a partly selected
/// category completes it rather than clearing it.
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
        case .none: "square"
        case .partial: "minus.square.fill"
        case .all: "checkmark.square.fill"
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
                Group {
                    if scan.items.isEmpty {
                        Text(scan.unreadableRoots.isEmpty ? "Empty" : "Could not be read")
                    } else {
                        Text("\(scan.category.consequence) · \(scan.items.count.itemsText)")
                    }
                }
                .font(.caption)
                .foregroundStyle(scan.unreadableRoots.isEmpty ? AnyShapeStyle(.secondary)
                                                              : AnyShapeStyle(.orange))
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
            Text(group.items.count.itemsText)
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
                if let hold = item.hold {
                    Text(hold.reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(model.describe(item))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(item.sizeBytes.formattedBytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
        .disabled(!item.isRemovable)
        .padding(.leading, indent)
    }
}

private struct ReportView: View {
    let report: RemovalReport?
    let trashBytes: Int64
    let onOpenTrash: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            let tint: Color = report?.isClean == true ? .green : .orange
            Image(systemName: report?.isClean == true ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .glassEffect(.regular.tint(tint.opacity(0.18)), in: .circle)

            Text("Moved \((report?.movedBytes ?? 0).formattedBytes) to the Trash")
                .font(.title3.bold())

            // The number above is not freed space, and saying so is the
            // difference between a report and a boast.
            VStack(spacing: 6) {
                Text("The space is freed once the Trash is emptied. It holds \(trashBytes.formattedBytes) now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open the Trash", action: onOpenTrash)
                    .buttonStyle(.link)
            }
            .frame(maxWidth: 380)

            if let failed = report?.failed, !failed.isEmpty {
                Text("Failed: \(failed.count)")
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failed, id: \.item.id) { outcome in
                            Text("\(outcome.item.url.lastPathComponent) — \(outcome.error ?? String(localized: "unknown reason"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            Button("Scan again", action: onRescan)
                .buttonStyle(.glass)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// Says out loud that the scan was partial.
///
/// An unreadable folder and an empty one look identical in a total, so
/// without this the app would report a tidy Mac that nobody actually looked at.
private struct PermissionBanner: View {
    let model: CleanerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("This scan is incomplete")
                    .font(.callout.weight(.medium))
                Text("Some folders refused to be read. Without Full Disk Access the totals below are a floor, not the whole picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Open Settings") { model.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
