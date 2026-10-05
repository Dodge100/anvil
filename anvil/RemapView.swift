import SwiftUI

struct RemapView: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        NavigationSplitView {
            ManipulatorSidebar(store: store)
                .navigationTitle("Manipulators")
        } detail: {
            ManipulatorEditorPane(store: store)
                .frame(minWidth: 560)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.addManipulator()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new manipulator (⌘N)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.importManipulatorFromPanel()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .help("Import a manipulator file (⌘⌥I)")

                Button {
                    if let id = store.selectedManipulatorID {
                        store.exportManipulator(id)
                    }
                } label: {
                    Image(systemName: "tray.and.arrow.up")
                }
                .disabled(store.selectedManipulatorID == nil)
                .help("Export the selected manipulator (⌘⌥E)")

                ProfileSwitcherButton(store: store)
            }
        }
    }
}

private struct ManipulatorSidebar: View {
    @ObservedObject var store: RemapStore
    @State private var showFilterPopover = false
    @State private var groupByFolder = false
    @State private var activeOnly = false
    @State private var folderExpanded: [String: Bool] = [:]

    private var displayedManipulators: [Manipulator] {
        // Use debounced results for smoother UI when searching
        let base = store.debouncedFilteredManipulators
        if activeOnly {
            return base.filter { $0.isEnabled }
        }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            manipulatorList
                .frame(maxHeight: .infinity)
            permissionBanner
        }
        .frame(minWidth: 280, maxWidth: 380)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if store.remapNeedsPermission {
            VStack(alignment: .leading, spacing: 6) {
                Label("Accessibility Required", systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Button("Grant") {
                        store.requestRemapPermissions()
                    }
                    .controlSize(.small)
                    Button("Settings") {
                        store.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.remapIsActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(store.remapStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }



    @ViewBuilder
    private var manipulatorList: some View {
        if displayedManipulators.isEmpty {
            VStack {
                Spacer()
                ContentUnavailableView {
                    Text("No manipulators")
                } description: {
                    Text(store.searchText.isEmpty && store.selectedTags.isEmpty
                         ? "Add one to get started."
                         : "No manipulators match the current filter.")
                } actions: {
                    Button {
                        store.addManipulator()
                    } label: {
                        Text("Add Manipulator")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else if groupByFolder {
            let groups = Dictionary(grouping: displayedManipulators) {
                $0.folder.isEmpty ? "Uncategorized" : $0.folder
            }
            let sortedFolders = groups.keys.sorted()
            List(selection: $store.selectedManipulatorID) {
                ForEach(sortedFolders, id: \.self) { folder in
                    DisclosureGroup(isExpanded: expandedBinding(for: folder)) {
                        ForEach(groups[folder] ?? []) { manipulator in
                            ManipulatorRow(
                                manipulator: manipulator,
                                onToggleEnabled: { store.updateManipulator(manipulator.id) { $0.isEnabled.toggle() } },
                                onDuplicate: { store.duplicateManipulator(manipulator.id) },
                                onExport: { store.exportManipulator(manipulator.id) },
                                onDelete: { store.deleteManipulator(manipulator.id) }
                            )
                            .tag(manipulator.id)
                        }
                    } label: {
                        Text(folder)
                            .font(.headline)
                    }
                }
            }
            .listStyle(.sidebar)
        } else {
            List(selection: $store.selectedManipulatorID) {
                ForEach(Array(displayedManipulators.enumerated()), id: \.element.id) { index, manipulator in
                    ManipulatorRow(
                        manipulator: manipulator,
                        index: index,
                        onToggleEnabled: { store.updateManipulator(manipulator.id) { $0.isEnabled.toggle() } },
                        onDuplicate: { store.duplicateManipulator(manipulator.id) },
                        onExport: { store.exportManipulator(manipulator.id) },
                        onDelete: { store.deleteManipulator(manipulator.id) }
                    )
                    .tag(manipulator.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func expandedBinding(for folder: String) -> Binding<Bool> {
        Binding(
            get: { folderExpanded[folder, default: true] },
            set: { folderExpanded[folder] = $0 }
        )
    }
}

private struct ManipulatorRow: View {
    let manipulator: Manipulator
    var index: Int = 0
    var onToggleEnabled: () -> Void
    var onDuplicate: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(manipulator.name.isEmpty ? "Untitled" : manipulator.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !manipulator.trigger.displayLabel.isEmpty {
                Text(manipulator.trigger.displayLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .opacity(manipulator.isEnabled ? 1 : 0.5)
        .contextMenu {
            Button(manipulator.isEnabled ? "Disable" : "Enable") {
                onToggleEnabled()
            }
            Button("Duplicate") {
                onDuplicate()
            }
            Divider()
            Button("Export…") {
                onExport()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

struct ManipulatorEditorPane: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        Group {
            if let manipulator = store.selectedManipulator {
                ManipulatorEditorView(store: store, manipulator: manipulator)
            } else {
                ContentUnavailableView {
                    Text("No Manipulator Selected")
                } description: {
                    Text("Add a manipulator or pick one from the list.")
                } actions: {
                    Button {
                        store.addManipulator()
                    } label: {
                        Text("Add Manipulator")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(store.selectedManipulator?.name ?? "Manipulator")
    }
}



struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalWidth = max(totalWidth, rowWidth - spacing)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, rowWidth - spacing)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
