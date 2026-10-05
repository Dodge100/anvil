import SwiftUI

// MARK: - Floating Macro Palette

/// A floating palette view that lists all enabled manipulators and allows
/// triggering them by clicking or keyboard.  Designed to be hosted inside an NSPanel
/// (floating, always-on-top).
struct MacroPaletteView: View {
    @ObservedObject var store: RemapStore
    @State private var searchText = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    /// All items displayed in the flat list (favorites first, then rest).
    private var displayItems: [Manipulator] {
        let base = store.debouncedFilteredManipulators
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = base
            .filter { $0.isEnabled && $0.trigger.isValid && $0.actions.contains(where: \.isConfigured) }
            .filter { manipulator in
                guard !query.isEmpty else { return true }
                return manipulator.name.lowercased().contains(query)
                    || manipulator.trigger.displayLabel.lowercased().contains(query)
                    || manipulator.actions.contains { $0.summary.lowercased().contains(query) }
                    || manipulator.tags.contains { $0.lowercased().contains(query) }
            }
        // Sort: starred first, then alphabetical
        return filtered.sorted { a, b in
            if a.isStarred != b.isStarred { return a.isStarred && !b.isStarred }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Items grouped by star status + tags.
    private struct SectionGroup: Identifiable {
        let id: String
        let title: String
        let items: [Manipulator]
    }

    private var sections: [SectionGroup] {
        guard searchText.isEmpty else { return [SectionGroup(id: "_all", title: "Results", items: displayItems)] }

        let starred = displayItems.filter(\.isStarred)
        let unstarred = displayItems.filter { !$0.isStarred }

        var groups: [SectionGroup] = []
        if !starred.isEmpty {
            groups.append(SectionGroup(id: "_starred", title: "Favorites", items: starred))
        }

        // Group remaining by first tag
        var tagGroups: [String: [Manipulator]] = [:]
        for item in unstarred {
            let group = item.tags.sorted().first ?? "General"
            tagGroups[group, default: []].append(item)
        }
        for (tag, items) in tagGroups.sorted(by: { $0.key < $1.key }) {
            groups.append(SectionGroup(id: tag, title: tag, items: items))
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ──
            searchBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            // ── Content ──
            if displayItems.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 340, idealWidth: 380, minHeight: 300, idealHeight: 460)
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)

            TextField("Search macros…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .font(.subheadline)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: searchText) { _ in
            selectedIndex = 0
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command.square")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No Macros" : "No Matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Create and enable manipulators with actions\nto see them here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Content

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        if section.title != "Results" {
                            SectionHeader(title: section.title)
                        }

                        ForEach(Array(section.items.enumerated()), id: \.element.id) { offset, manipulator in
                            let globalIndex = globalIndex(for: section, offset: offset)
                            PaletteItemRow(
                                manipulator: manipulator,
                                isSelected: globalIndex == selectedIndex,
                                onTrigger: { triggerItem(manipulator) },
                                onToggleStar: { store.toggleStarred(manipulator.id) },
                                onEdit: {
                                    store.selectManipulator(manipulator.id)
                                    store.hideMacroPalette()
                                    if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                                        mainWindow.makeKeyAndOrderFront(nil)
                                        NSApp.activate(ignoringOtherApps: true)
                                    }
                                }
                            )
                            .id(manipulator.id)
                            .onTapGesture {
                                triggerItem(manipulator)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("keyboardNavigation"))) { notification in
                // Handled via key event monitor below
            }
            .background(
                // Keyboard event handling via representable
                KeyEventHandler { event in
                    handleKeyEvent(event, proxy: proxy)
                }
            )
        }
    }

    // MARK: - Helpers

    private func globalIndex(for section: SectionGroup, offset: Int) -> Int {
        var idx = 0
        for s in sections {
            if s.id == section.id { return idx + offset }
            idx += s.items.count
        }
        return idx + offset
    }

    private var totalCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    private func handleKeyEvent(_ event: NSEvent, proxy: ScrollViewProxy) -> Bool {
        switch event.keyCode {
        case 125: // Down arrow
            if selectedIndex < totalCount - 1 {
                selectedIndex += 1
                scrollToSelection(proxy)
            }
            return true
        case 126: // Up arrow
            if selectedIndex > 0 {
                selectedIndex -= 1
                scrollToSelection(proxy)
            }
            return true
        case 36, 76: // Return / Enter
            if displayItems.indices.contains(selectedIndex) {
                triggerItem(displayItems[selectedIndex])
            }
            return true
        default:
            return false
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard displayItems.indices.contains(selectedIndex) else { return }
        let item = displayItems[selectedIndex]
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(item.id, anchor: .center)
        }
    }

    private func triggerItem(_ manipulator: Manipulator) {
        store.executeManipulatorFromPalette(manipulator)
    }
}

// MARK: - Key Event Handler (NSViewRepresentable)

private struct KeyEventHandler: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private class KeyView: NSView {
        var handler: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if handler?(event) == true { return }
            super.keyDown(with: event)
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            if title == "Favorites" {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Palette Item Row

private struct PaletteItemRow: View {
    let manipulator: Manipulator
    let isSelected: Bool
    let onTrigger: () -> Void
    let onToggleStar: () -> Void
    let onEdit: () -> Void

    private var primaryActionSummary: String? {
        manipulator.actions.first(where: { $0.isConfigured })?.summary
    }

    var body: some View {
        Button {
            onTrigger()
        } label: {
            HStack(spacing: 10) {
                // Star toggle
                Button {
                    onToggleStar()
                } label: {
                    Image(systemName: manipulator.isStarred ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(manipulator.isStarred ? Color.yellow : Color(nsColor: .tertiaryLabelColor))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(manipulator.isStarred ? "Unfavorite" : "Favorite")
                Text(triggerKeyLabel)
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 22)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                // Name + summary
                VStack(alignment: .leading, spacing: 2) {
                    Text(manipulator.name.isEmpty ? "Untitled" : manipulator.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let summary = primaryActionSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Keyboard shortcut display
                let shortcut = manipulator.trigger.displayLabel
                if !shortcut.isEmpty && shortcut != "Not recorded" {
                    Text(shortcut)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                : nil
        )
        .padding(.horizontal, 6)
        .contextMenu {
            Button {
                onToggleStar()
            } label: {
                Label(manipulator.isStarred ? "Unfavorite" : "Favorite", systemImage: "star")
            }
            Button("Edit in Editor") {
                onEdit()
            }
            Divider()
            Text("Trigger: \(manipulator.trigger.displayLabel)")
            Text("Actions: \(manipulator.actions.filter(\.isConfigured).count)")
            if !manipulator.tags.isEmpty {
                Text("Tags: \(manipulator.tags.sorted().joined(separator: ", "))")
            }
        }
    }

    private var triggerKeyLabel: String {
        if manipulator.trigger.keyType != .keyboard {
            return manipulator.trigger.keyType.symbol
        }
        if let firstKey = manipulator.trigger.steps.first?.displayLabel {
            return String(firstKey.prefix(4))
        }
        return manipulator.trigger.keyType.symbol
    }
}
