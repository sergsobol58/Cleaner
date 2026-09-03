import CleanerKit
import SwiftUI

/// The menu bar panel: how much has piled up, what to remove, and a way into
/// the main window.
///
/// A panel rather than a plain menu, because confirmation has to happen right
/// here. Sending the user to the window to confirm would defeat the point of
/// cleaning from the menu bar; skipping confirmation would break the rule the
/// rest of the app is built on.
struct MenuBarView: View {
    let model: CleanerModel
    @Bindable var settings: AppSettings

    @Environment(\.openWindow) private var openWindow
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isConfirming {
                confirmation
            } else {
                overview
            }
        }
        .frame(width: 320)
        .task { await model.scanIfNeeded() }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 6)

            if model.phase == .scanning || model.phase == .idle {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for space to reclaim…")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else if model.phase == .removing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Moving to the Trash…").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                categories
            }

            Divider().padding(.vertical, 6)

            actions
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Found \(model.foundBytes.formattedBytes)")
                .font(.headline)
            if let lastScan = model.lastScan {
                Text("Scanned \(lastScan.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    private var categories: some View {
        VStack(spacing: 0) {
            ForEach(model.scans) { scan in
                Toggle(isOn: Binding(
                    get: { model.coverage(of: scan.items) == .all },
                    set: { on in model.selection.set(scan.items, selected: on) }
                )) {
                    HStack {
                        Text(scan.category.title)
                            .lineLimit(1)
                        Spacer()
                        Text(scan.totalBytes.formattedBytes)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(scan.items.isEmpty)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.selectedBytes > 0 {
                Text("Selected \(model.selectedBytes.formattedBytes) · \(model.selectedItems.count.itemsText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            MenuRow("Move to Trash…", systemImage: "trash") {
                isConfirming = true
            }
            .disabled(!model.canRemove)

            MenuRow("Scan again", systemImage: "arrow.clockwise") {
                Task { await model.scan() }
            }
            .disabled(model.phase == .scanning || model.phase == .removing)

            MenuRow("Open Cleaner", systemImage: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: CleanerApp.mainWindowID)
            }

            Divider().padding(.vertical, 4)

            Toggle("Run in the background only", isOn: $settings.runsInBackground)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            Text("The Dock icon disappears; the app stays in the menu bar.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            Divider().padding(.vertical, 4)

            MenuRow("Quit Cleaner", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Confirmation

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move to the Trash?").font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.touchedScans) { scan in
                    HStack {
                        Text(scan.category.title).font(.callout).lineLimit(1)
                        Spacer()
                        Text(model.selectedBytes(in: scan).formattedBytes)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Total: \(model.selectedBytes.formattedBytes) · \(model.selectedItems.count.itemsText)")
                .font(.callout.bold())

            Text("Nothing is erased for good: the files go to the Trash, and Finder's Put Back brings them home.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { isConfirming = false }
                Button("Move") {
                    isConfirming = false
                    Task { await model.removeSelectedAndRescan() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}

/// A row that behaves like a menu item: full width, highlights on hover.
private struct MenuRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isHovered && isEnabled ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
