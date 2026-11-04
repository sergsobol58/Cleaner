import AppKit
import CleanerKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: CleanerModel
    @Bindable var system: SystemModel
    @Bindable var navigation: Navigation
    @State private var refusal: FolderRejection?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle(navigation.section.title)
        }
        .frame(minWidth: 820, minHeight: 520)
        // Declared on the window, not on the detail. Hanging it off a view
        // that is replaced on every section switch takes the whole toolbar
        // out of the window and back in, and the sidebar loses the inset
        // that keeps its first row clear of the window controls.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let folder = chooseFolder() { refusal = model.addFolder(folder) }
                } label: {
                    Label("Add a folder…", systemImage: "folder.badge.plus")
                }
                .help("Watch a folder of your own")
                .disabled(navigation.section != .files)
            }
        }
        .alert("That folder cannot be added", isPresented: Binding(
            get: { refusal != nil }, set: { if !$0 { refusal = nil } }
        ), presenting: refusal) { _ in
            Button("OK") { refusal = nil }
        } message: { rejection in
            Text(rejection.reason)
        }
        .task { await model.scanIfNeeded() }
        .sheet(isPresented: $model.isConfirming) { confirmation }
    }

    private var sidebar: some View {
        List(selection: $navigation.section) {
            SwiftUI.Section {
                Label(AppSection.overview.title, systemImage: AppSection.overview.symbol)
                    .tag(AppSection.overview)
            }

            SwiftUI.Section("Disk") {
                ForEach(AppSection.disk) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }

            SwiftUI.Section("System") {
                ForEach(AppSection.system) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .overview:
            OverviewView(model: model, system: system) { navigation.section = $0 }
        case .files:
            VStack(spacing: 0) {
                if model.isUnderReporting { PermissionBanner(model: model) }
                if let problem = model.userCatalogProblem {
                    CatalogProblemBanner(problem: problem, model: model)
                }
                content
            }
            .safeAreaInset(edge: .bottom) { footer }
            .searchable(text: $model.query, placement: .toolbar,
                        prompt: Text("Search categories and files"))
        case .memory:
            MemoryView(model: system)
        case .processor:
            ProcessorView(model: system)
        case .simulators:
            SimulatorsView(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where model.wasStopped:
            centered {
                Image(systemName: "stop.circle")
                    .accessibilityHidden(true)
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Scan stopped").font(.headline)
                Text("Nothing was measured, so there is nothing to show yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Scan again") { Task { await model.scan() } }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
            }
        case .idle, .scanning:
            centered {
                if let progress = model.scanProgress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                    Text("Looking for space to reclaim…").foregroundStyle(.secondary)
                    Text(progress.finished)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    ProgressView()
                    Text("Looking for space to reclaim…").foregroundStyle(.secondary)
                }
                Button("Stop") { model.cancelScan() }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
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
        case .results where model.foundBytes == 0:
            centered {
                Image(systemName: "checkmark.seal")
                    .accessibilityHidden(true)
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                    .frame(width: 88, height: 88)
                    .glassEffect(.regular.tint(.green.opacity(0.18)), in: .circle)
                Text("Nothing to clean").font(.title3.bold())
                Text("Every category came back empty. There is no junk here to move.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Scan again") { Task { await model.scan() } }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
            }
        case .results:
            categoryList
        }
    }

    private var categoryList: some View {
        List {
            ForEach(model.visibleScans) { scan in
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
                Text(model.summaryLine)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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

    /// The panel is the only way a folder enters the catalog through the
    /// interface: the user points at it themselves, and it is validated
    /// before it widens anything.
    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
        panel.prompt = String(localized: "Add")
        return panel.runModal() == .OK ? panel.url : nil
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
        // The only control in the app with no text of its own. Without a
        // label VoiceOver announces it as "button" and nothing else.
        .accessibilityLabel("Select everything in this group")
        .accessibilityValue(spoken)
    }

    private var spoken: LocalizedStringKey {
        switch coverage {
        case .none: "nothing selected"
        case .partial: "some selected"
        case .all: "all selected"
        }
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
        HStack(spacing: 10) {
            TriStateBox(coverage: model.coverage(of: scan.items)) {
                model.toggleAll(scan.items)
            }
            .disabled(scan.items.isEmpty)

            Image(systemName: scan.category.icon)
                .accessibilityHidden(true)
                .font(.system(size: 14))
                .foregroundStyle(scan.items.isEmpty ? AnyShapeStyle(.tertiary)
                                                    : AnyShapeStyle(.tint))
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(scan.items.isEmpty ? 0.4 : 1),
                            in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.category.title).font(.body.weight(.medium))
                // An unreadable folder outranks the count: a category can
                // hold one finding and still be hiding hundreds of folders.
                Group {
                    if !scan.unreadableRoots.isEmpty {
                        Text("Could not be read")
                    } else if scan.items.isEmpty {
                        Text("Empty")
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
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(scan.items.isEmpty ? .tertiary : .primary)
        }
        .padding(.vertical, 7)
        .contextMenu {
            if scan.category.isUserDefined {
                Button("Stop watching this folder") { model.removeFolder(scan.category) }
            }
        }
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
        .contextMenu { PathActions(url: group.root, model: model) }
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
        .contextMenu { PathActions(url: item.url, model: model) }
    }
}

private struct ReportView: View {
    let report: RemovalReport?
    let trashBytes: Int64?
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
                // The size is only claimed when it was actually read. Saying
                // "it holds 0 bytes" right after moving gigabytes into it is
                // worse than saying nothing about the size at all.
                Group {
                    if let trashBytes {
                        Text("The space is freed once the Trash is emptied. It holds \(trashBytes.formattedBytes) now.")
                    } else {
                        Text("The space is freed once the Trash is emptied.")
                    }
                }
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


/// A hand-edited catalog file that could not be read.
private struct CatalogProblemBanner: View {
    let problem: String
    let model: CleanerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.badge.exclamationmark").foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your catalog file could not be read")
                    .font(.callout.weight(.medium))
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Show file") { model.revealCatalogFile() }
                .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

/// Says out loud that the scan was partial, and which of the two reasons it
/// was partial for.
///
/// These need telling apart. Missing permission is something the user can
/// fix, and pointing at Settings is the whole point. A folder that refuses
/// even with permission granted is not, and sending them to Settings again
/// to flip a switch that is already on is advice that wastes their time and
/// teaches them to ignore the banner.
private struct PermissionBanner: View {
    let model: CleanerModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: model.hasFullDiskAccess
                  ? "eye.slash" : "eye.trianglebadge.exclamationmark")
                .foregroundStyle(model.hasFullDiskAccess ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.orange))

            VStack(alignment: .leading, spacing: 2) {
                if model.hasFullDiskAccess {
                    Text("A few folders stayed shut")
                        .font(.callout.weight(.medium))
                    Text("\(model.unreadableRoots.count.foldersText) refused to open even with Full Disk Access granted, so their contents are not in the totals below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This scan is incomplete")
                        .font(.callout.weight(.medium))
                    Text("Some folders refused to be read. Without Full Disk Access the totals below are a floor, not the whole picture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if !model.hasFullDiskAccess {
                Button("Open Settings") { model.openFullDiskAccessSettings() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

/// Checking before deleting should not require leaving the app to find out
/// what a name like "content-v2" actually is.
private struct PathActions: View {
    let url: URL
    let model: CleanerModel

    var body: some View {
        Button("Show in Finder") { model.reveal(url) }
        Button("Copy path") { model.copyPath(url) }
    }
}
