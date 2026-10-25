import SwiftUI

struct RemapView: View {
    @ObservedObject var store: RemapStore
    @State private var activeOnly = false
    @State private var groupByFolder = false

    private var isFiltering: Bool {
        activeOnly || !store.selectedTags.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            ManipulatorSidebar(store: store, activeOnly: $activeOnly, groupByFolder: $groupByFolder)
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Enabled Only", isOn: $activeOnly)
                    Toggle("Group by Folder", isOn: $groupByFolder)
                    if !store.allTags.isEmpty {
                        Divider()
                        Section("Tags") {
                            ForEach(store.allTags, id: \.self) { tag in
                                Toggle(tag, isOn: Binding(
                                    get: { store.selectedTags.contains(tag) },
                                    set: { _ in
                                        store.toggleTag(tag)
                                    }
                                ))
                            }
                        }
                    }
                } label: {
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .menuIndicator(.hidden)
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
    @Binding var activeOnly: Bool
    @Binding var groupByFolder: Bool
    @State private var folderExpanded: [String: Bool] = [:]

    private var displayedManipulators: [Manipulator] {
        // Use debounced results for smoother UI when searching
        let base = store.debouncedFilteredManipulators
        if activeOnly {
            return base.filter { $0.isEnabled }
        }
        return base
    }

    /// Folder groups computed once per body evaluation (not per row).
    private var folderGroups: [(folder: String, items: [Manipulator])] {
        let groups = Dictionary(grouping: displayedManipulators) {
            $0.folder.isEmpty ? "Uncategorized" : $0.folder
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            manipulatorList
                .frame(maxHeight: .infinity)
            if store.remapNeedsPermission {
                permissionBanner
            }
        }
        .frame(minWidth: 280, maxWidth: 380)
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search")
    }

    @ViewBuilder
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Required")
                    .font(.footnote.weight(.medium))
                Text("Enable access to remap keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                store.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(8)
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
            List(selection: $store.selectedManipulatorID) {
                ForEach(folderGroups, id: \.folder) { folder, items in
                    DisclosureGroup(isExpanded: expandedBinding(for: folder)) {
                        ForEach(items) { manipulator in
                            ManipulatorRow(
                                store: store,
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
                ForEach(displayedManipulators) { manipulator in
                    ManipulatorRow(
                        store: store,
                        manipulator: manipulator,
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

private struct ManipulatorRow: View, Equatable {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    var onToggleEnabled: () -> Void
    var onDuplicate: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void

    static func == (lhs: ManipulatorRow, rhs: ManipulatorRow) -> Bool {
        lhs.manipulator == rhs.manipulator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(manipulator.name.isEmpty ? "Untitled Manipulator" : manipulator.name)
                .lineLimit(1)
            HStack(spacing: 4) {
                if manipulator.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
                Text(manipulator.summary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .opacity(manipulator.isEnabled ? 1 : 0.5)
        .contextMenu {
            Button(manipulator.isEnabled ? "Disable" : "Enable") {
                onToggleEnabled()
            }
            Button(manipulator.isStarred ? "Unstar" : "Star") {
                store.toggleStarred(manipulator.id)
            }
            Divider()
            Button("Duplicate") {
                onDuplicate()
            }
            Menu("Move to Folder") {
                Button("None") {
                    store.updateManipulatorCosmetic(manipulator.id) { $0.folder = "" }
                }
                ForEach(store.allFolders, id: \.self) { folder in
                    Button(folder) {
                        store.updateManipulatorCosmetic(manipulator.id) { $0.folder = folder }
                    }
                }
            }
            if !store.allTags.isEmpty {
                Menu("Tags") {
                    ForEach(store.allTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { manipulator.tags.contains(tag) },
                            set: { _ in
                                store.toggleTag(tag, on: manipulator.id)
                            }
                        ))
                    }
                }
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