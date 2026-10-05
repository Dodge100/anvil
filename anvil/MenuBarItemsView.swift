import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Menu Bar Items View

struct MenuBarItemsView: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        NavigationSplitView {
            MenuBarItemsSidebar(store: store)
                .navigationTitle("Menu Bar Items")
        } detail: {
            MenuBarItemEditorPane(store: store)
                .frame(minWidth: 560)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.addMenuBarItem()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new menu bar item")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.importMenuBarItemFromPanel()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .help("Import a menu bar item file (⌘⌥I)")

                Button {
                    if let id = store.selectedMenuBarItemID {
                        store.exportMenuBarItem(id)
                    }
                } label: {
                    Image(systemName: "tray.and.arrow.up")
                }
                .disabled(store.selectedMenuBarItemID == nil)
                .help("Export the selected menu bar item (⌘⌥E)")

                ProfileSwitcherButton(store: store)
            }
        }
    }
}

// MARK: - Sidebar

private struct MenuBarItemsSidebar: View {
    @ObservedObject var store: RemapStore
    @State private var itemToDelete: MenuBarItem?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            itemList
        }
        .frame(minWidth: 280, maxWidth: 380)
        .alert(
            "Delete \"\(itemToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = itemToDelete?.id {
                    store.deleteMenuBarItem(id)
                }
                itemToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var itemList: some View {
        let filteredItems: [MenuBarItem] = {
            let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return store.menuBarItems }
            return store.menuBarItems.filter { $0.name.lowercased().contains(query) }
        }()

        return Group {
            if filteredItems.isEmpty {
                ContentUnavailableView {
                    Label(store.searchText.isEmpty ? "No Items" : "No Matches", systemImage: "menubar.rectangle")
                } description: {
                    Text(store.searchText.isEmpty ? "Add items to customize the menu bar." : "No items match the current search.")
                } actions: {
                    Button("Add") {
                        store.addMenuBarItem()
                    }
                }
            } else {
                List(selection: $store.selectedMenuBarItemID) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        MenuBarItemRow(item: item, index: index)
                            .tag(item.id)
                            .contextMenu {
                                contextMenuItems(for: item)
                            }
                    }
                    .onMove { source, dest in
                        store.moveMenuBarItem(from: source, to: dest)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            itemToDelete = store.menuBarItems[index]
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenuItems(for item: MenuBarItem) -> some View {
        Button {
            store.toggleMenuBarItemEnabled(item.id)
        } label: {
            Text(item.isEnabled ? "Disable" : "Enable")
        }

        if !item.isSeparator {
            Button {
                store.addMenuBarChildItem(to: item.id)
                store.selectedMenuBarItemID = item.id
            } label: {
                Text("Add Sub-item")
            }
        }

        Button {
            store.toggleMenuBarItemSeparator(item.id)
        } label: {
            Text(item.isSeparator ? "Convert to Item" : "Make Separator")
        }

        Button {
            store.duplicateMenuBarItem(item.id)
        } label: {
            Text("Duplicate")
        }

        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Text("Delete")
        }
    }
}

// MARK: - Menu Bar Item Row

private struct MenuBarItemRow: View {
    let item: MenuBarItem
    var index: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            if item.isSeparator {
                Image(systemName: "minus")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Text("Separator")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: item.icon)
                    .foregroundStyle(item.isEnabled ? .secondary : .tertiary)
                    .frame(width: 16)
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !item.children.isEmpty {
                    Text("\(item.children.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .opacity(item.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Editor Pane

private struct MenuBarItemEditorPane: View {
    @ObservedObject var store: RemapStore
    @State private var showIconPicker = false
    @State private var showDeleteConfirmation = false
    @State private var actionsExpanded = true
    @State private var subitemsExpanded = true

    var body: some View {
        Group {
            if let item = store.selectedMenuBarItem {
                editorContent(item: item)
            } else {
                ContentUnavailableView {
                    Label("No Item Selected", systemImage: "menubar.rectangle")
                } description: {
                    Text("Select a menu bar item from the sidebar.")
                } actions: {
                    Button {
                        store.addMenuBarItem()
                    } label: {
                        Text("Add Item")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "Delete \"\(store.selectedMenuBarItem?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = store.selectedMenuBarItemID {
                    store.deleteMenuBarItem(id)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func editorContent(item: MenuBarItem) -> some View {
        let binding = Binding(
            get: { item },
            set: { newItem in
                if let idx = store.menuBarItems.firstIndex(where: { $0.id == newItem.id }) {
                    store.menuBarItems[idx] = newItem
                    store.saveMenuBarItems()
                }
            }
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── Header card ──
                EditorCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                showIconPicker.toggle()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showIconPicker) {
                                IconPickerView(item: binding)
                            }

                            TextField("Name", text: binding.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2.weight(.semibold))

                            Toggle("", isOn: binding.isEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .help(item.isEnabled ? "Enabled" : "Disabled")

                            Menu {
                                Button {
                                    store.duplicateMenuBarItem(item.id)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                if !item.isSeparator {
                                    Button {
                                        store.toggleMenuBarItemSeparator(item.id)
                                    } label: {
                                        Label(item.isSeparator ? "Convert to Item" : "Make Separator", systemImage: "minus")
                                    }
                                }
                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }

                if !item.isSeparator && item.children.isEmpty {
                    // ── Click Actions card ──
                    EditorCard {
                        CollapsibleStepCard(
                            title: "Click Actions",
                            accentColor: .blue,
                            isExpanded: $actionsExpanded
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Left Click")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .trailing)

                                    Picker("", selection: Binding(
                                        get: { item.leftClickAction?.kind ?? .none },
                                        set: { newKind in
                                            if item.leftClickAction == nil {
                                                binding.wrappedValue.leftClickAction = MenuBarItemAction(kind: newKind)
                                            } else {
                                                binding.wrappedValue.leftClickAction?.kind = newKind
                                            }
                                            store.saveMenuBarItems()
                                        }
                                    )) {
                                        ForEach(MenuBarActionKind.allCases) { kind in
                                            Text(kind.rawValue).tag(kind)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 180)

                                    Spacer()

                                    if item.leftClickAction != nil, item.leftClickAction?.kind != .none {
                                        Button("Clear") {
                                            binding.wrappedValue.leftClickAction = nil
                                            store.saveMenuBarItems()
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    }
                                }

                                if let leftAction = item.leftClickAction, leftAction.kind != .none {
                                    actionParameters(action: Binding(
                                        get: { leftAction },
                                        set: { binding.wrappedValue.leftClickAction = $0; store.saveMenuBarItems() }
                                    ))
                                    .padding(.leading, 100)
                                }

                                HStack(spacing: 10) {
                                    Text("Right Click (⌥)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .trailing)

                                    Picker("", selection: Binding(
                                        get: { item.rightClickAction?.kind ?? .none },
                                        set: { newKind in
                                            if item.rightClickAction == nil {
                                                binding.wrappedValue.rightClickAction = MenuBarItemAction(kind: newKind)
                                            } else {
                                                binding.wrappedValue.rightClickAction?.kind = newKind
                                            }
                                            store.saveMenuBarItems()
                                        }
                                    )) {
                                        ForEach(MenuBarActionKind.allCases) { kind in
                                            Text(kind.rawValue).tag(kind)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 180)

                                    Spacer()

                                    if item.rightClickAction != nil, item.rightClickAction?.kind != .none {
                                        Button("Clear") {
                                            binding.wrappedValue.rightClickAction = nil
                                            store.saveMenuBarItems()
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    }
                                }

                                if let rightAction = item.rightClickAction, rightAction.kind != .none {
                                    actionParameters(action: Binding(
                                        get: { rightAction },
                                        set: { binding.wrappedValue.rightClickAction = $0; store.saveMenuBarItems() }
                                    ))
                                    .padding(.leading, 100)
                                }
                            }
                        }
                    }
                }

                if !item.isSeparator {
                    // ── Sub-items card ──
                    EditorCard {
                        CollapsibleStepCard(
                            title: "Sub-items",
                            accentColor: .purple,
                            isExpanded: $subitemsExpanded
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                if item.children.isEmpty {
                                    Text("No sub-items. Add one to create a submenu.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                } else {
                                    ForEach(Array(item.children.enumerated()), id: \.element.id) { index, child in
                                        RecursiveChildRow(
                                            child: child,
                                            index: index,
                                            siblingCount: item.children.count,
                                            parentChain: [item.id],
                                            store: store
                                        )
                                    }
                                }

                                Button {
                                    store.addMenuBarChildItem(to: item.id)
                                } label: {
                                    Label("Add Sub-item", systemImage: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .alert(
            "Delete \"\(store.selectedMenuBarItem?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = store.selectedMenuBarItemID {
                    store.deleteMenuBarItem(id)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Action Parameters

    @ViewBuilder
    private func actionParameters(action: Binding<MenuBarItemAction>) -> some View {
        switch action.wrappedValue.kind {
        case .none:
            EmptyView()
        case .runShortcut:
            TextField("Shortcut name", text: action.shortcutName, prompt: Text("e.g. Open Browser"))
                .textFieldStyle(.roundedBorder)
        case .runShell:
            TextField("Command", text: action.shellCommand, prompt: Text("e.g. echo hello"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        case .openApp:
            HStack(spacing: 8) {
                TextField("Bundle ID", text: action.appBundleID, prompt: Text("com.apple.Safari"))
                    .textFieldStyle(.roundedBorder)
                TextField("App Name", text: action.appName, prompt: Text("Safari"))
                    .textFieldStyle(.roundedBorder)
            }
        case .openURL:
            TextField("URL", text: action.urlString, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
        case .sendKey:
            HStack(spacing: 8) {
                TextField("Key", text: action.toKey, prompt: Text("a, space, return"))
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 2) {
                    ForEach(ModifierKey.flagBased, id: \.self) { mod in
                        Toggle(mod.symbol, isOn: Binding(
                            get: { action.wrappedValue.toModifiers.contains(mod) },
                            set: {
                                if $0 { action.wrappedValue.toModifiers.insert(mod) }
                                else { action.wrappedValue.toModifiers.remove(mod) }
                                store.saveMenuBarItems()
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        case .setVariable:
            HStack(spacing: 8) {
                TextField("Variable", text: action.variableName, prompt: Text("myVar"))
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: action.variableValue, prompt: Text("some value"))
                    .textFieldStyle(.roundedBorder)
            }
        case .toggleVariable:
            TextField("Variable", text: action.variableName, prompt: Text("myVar"))
                .textFieldStyle(.roundedBorder)
        case .incrementVariable:
            HStack(spacing: 8) {
                TextField("Variable", text: action.variableName, prompt: Text("counter"))
                    .textFieldStyle(.roundedBorder)
                TextField("Step", text: action.variableValue, prompt: Text("1"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }
        case .setNotification:
            TextField("Message", text: action.notificationMessage, prompt: Text("Hello from Anvil!"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        case .openFile:
            TextField("File path", text: action.filePath, prompt: Text("~/Documents"))
                .textFieldStyle(.roundedBorder)
        case .runAppleScript:
            TextEditor(text: action.scriptBody)
                .font(.caption.monospaced())
                .frame(minHeight: 60, maxHeight: 120)
                .border(.quaternary)
        }
    }
}

// MARK: - Recursive Child Row (supports arbitrary nesting)

// MARK: - Drop Delegate (drag-to-reorder for sub-items)

private struct MenuBarChildRowDropDelegate: DropDelegate {
    let targetParentID: UUID
    let targetIndex: Int
    let store: RemapStore
    var onHighlight: (Bool) -> Void = { _ in }

    func dropEntered(info: DropInfo) {
        onHighlight(true)
    }

    func dropExited(info: DropInfo) {
        onHighlight(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onHighlight(false)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let parentID = targetParentID
        let index = targetIndex
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                store.moveMenuBarChildItem(id, toParent: parentID, atIndex: index)
            }
        }
        return true
    }
}

private struct RecursiveChildRow: View {
    let child: MenuBarItem
    var index: Int = 0
    var siblingCount: Int = 1
    /// Chain of parent IDs from the root down to this child's parent.
    let parentChain: [UUID]
    @ObservedObject var store: RemapStore
    @State private var showIconPicker = false
    @State private var showDeleteAlert = false
    @State private var childrenExpanded = true
    @State private var showActions = false
    @State private var isDropTarget = false

    private var depth: Int { parentChain.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ── This row ──
            HStack(spacing: 8) {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: child.id.uuidString as NSString)
                    }
                    .onHover { hovering in
                        if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
                    .help("Drag to reorder")

                // Disclosure chevron if has children
                if !child.children.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            childrenExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(childrenExpanded ? 90 : 0))
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon
                Button {
                    showIconPicker.toggle()
                } label: {
                    Image(systemName: child.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    IconPickerGrid(icon: Binding(
                        get: { child.icon },
                        set: { newIcon in
                            _ = store.recursiveUpdateMenuBarItem(child.id, in: &store.menuBarItems) { $0.icon = newIcon }
                        }
                    ))
                }

                // Name
                TextField("Name", text: Binding(
                    get: { child.name },
                    set: { newValue in
                        _ = store.recursiveUpdateMenuBarItem(child.id, in: &store.menuBarItems) { $0.name = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

                // Action summary badge (submenus can't have click actions)
                if child.children.isEmpty, child.hasLeftAction || child.hasRightAction {
                    Button {
                        showActions.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cursorarrow.click")
                                .font(.caption2)
                            Text(child.hasLeftAction ? "L" : "")
                                .font(.caption2.weight(.medium))
                            if child.hasRightAction {
                                Text("R")
                                    .font(.caption2.weight(.medium))
                            }
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Edit actions")
                    .popover(isPresented: $showActions, arrowEdge: .trailing) {
                        ChildActionEditor(
                            childID: child.id,
                            store: store
                        )
                    }
                } else if child.children.isEmpty {
                    Button {
                        showActions.toggle()
                    } label: {
                        Image(systemName: "cursorarrow.click")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Configure actions")
                    .popover(isPresented: $showActions, arrowEdge: .trailing) {
                        ChildActionEditor(
                            childID: child.id,
                            store: store
                        )
                    }
                }

                Spacer()

                // Enable toggle
                Toggle("", isOn: Binding(
                    get: { child.isEnabled },
                    set: { newValue in
                        _ = store.recursiveUpdateMenuBarItem(child.id, in: &store.menuBarItems) { $0.isEnabled = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                // Context menu
                Menu {
                    Button {
                        _ = store.recursiveUpdateMenuBarItem(child.id, in: &store.menuBarItems) { $0.isEnabled.toggle() }
                    } label: {
                        Text(child.isEnabled ? "Disable" : "Enable")
                    }
                    Button {
                        store.moveMenuBarChildItem(child.id, offset: -1)
                    } label: {
                        Text("Move Up")
                    }
                    .disabled(index == 0)
                    Button {
                        store.moveMenuBarChildItem(child.id, offset: 1)
                    } label: {
                        Text("Move Down")
                    }
                    .disabled(index >= siblingCount - 1)
                    Divider()
                    Button {
                        store.addMenuBarChildItem(to: child.id)
                    } label: {
                        Text("Add Sub-item")
                    }
                    Divider()
                    Button {
                        showActions = true
                    } label: {
                        Text("Configure Actions…")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Text("Delete")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.vertical, 4)
            .padding(.leading, CGFloat(depth - 1) * 10)
            .opacity(child.isEnabled ? 1 : 0.5)
            .background(
                isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onDrop(
                of: [UTType.text],
                delegate: MenuBarChildRowDropDelegate(
                    targetParentID: parentChain.last ?? child.id,
                    targetIndex: index,
                    store: store,
                    onHighlight: { highlighted in
                        isDropTarget = highlighted
                    }
                )
            )

            // ── Nested children ──
            if !child.children.isEmpty, childrenExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(child.children.enumerated()), id: \.element.id) { index, nestedChild in
                        RecursiveChildRow(
                            child: nestedChild,
                            index: index,
                            siblingCount: child.children.count,
                            parentChain: parentChain + [child.id],
                            store: store
                        )
                    }


                    Button {
                        store.addMenuBarChildItem(to: child.id)
                    } label: {
                        Label("Add Sub-item", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(depth) * 14 + 44)
                    .padding(.vertical, 2)
                }
                .padding(.leading, 20)
            }
        }
        .alert(
            "Delete \"\(child.name)\"?",
            isPresented: $showDeleteAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let parentID = parentChain.last {
                    store.deleteMenuBarChildItem(child.id, from: parentID)
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

// MARK: - Child Action Editor (popover for sub-item actions)

private enum ActionSide { case left, right }

private struct ChildActionEditor: View {
    let childID: UUID
    @ObservedObject var store: RemapStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))

            actionRow(label: "Left Click", side: .left)

            actionRow(label: "Right Click (⌥)", side: .right)
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Action Row

    private func actionRow(label: String, side: ActionSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)

                Picker("", selection: actionKindBinding(side: side)) {
                    ForEach(MenuBarActionKind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)

                if currentAction(side: side).kind != .none {
                    Button("Clear") {
                        setAction(side: side, to: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
                }

                Spacer()
            }

            if currentAction(side: side).kind != .none {
                ActionParamsView(
                    action: currentAction(side: side),
                    onChange: { newAction in
                        setAction(side: side, to: newAction)
                    },
                    store: store
                )
                .padding(.leading, 90)
            }
        }
    }

    // MARK: - Helpers

    private func currentAction(side: ActionSide) -> MenuBarItemAction {
        guard let child = findChild(id: childID, in: store.menuBarItems) else { return MenuBarItemAction() }
        switch side {
        case .left:  return child.leftClickAction ?? MenuBarItemAction()
        case .right: return child.rightClickAction ?? MenuBarItemAction()
        }
    }

    private func actionKindBinding(side: ActionSide) -> Binding<MenuBarActionKind> {
        Binding(
            get: { currentAction(side: side).kind },
            set: { newKind in
                _ = store.recursiveUpdateMenuBarItem(childID, in: &store.menuBarItems) { item in
                    switch side {
                    case .left:
                        if item.leftClickAction == nil {
                            item.leftClickAction = MenuBarItemAction(kind: newKind)
                        } else {
                            item.leftClickAction?.kind = newKind
                        }
                    case .right:
                        if item.rightClickAction == nil {
                            item.rightClickAction = MenuBarItemAction(kind: newKind)
                        } else {
                            item.rightClickAction?.kind = newKind
                        }
                    }
                }
            }
        )
    }

    private func setAction(side: ActionSide, to action: MenuBarItemAction?) {
        _ = store.recursiveUpdateMenuBarItem(childID, in: &store.menuBarItems) { item in
            switch side {
            case .left:  item.leftClickAction = action
            case .right: item.rightClickAction = action
            }
        }
    }
}

// MARK: - Standalone Action Parameters View

private struct ActionParamsView: View {
    let action: MenuBarItemAction
    let onChange: (MenuBarItemAction) -> Void
    @ObservedObject var store: RemapStore

    var body: some View {
        switch action.kind {
        case .none:
            EmptyView()
        case .runShortcut:
            TextField("Shortcut name", text: binding(\.shortcutName, default: ""), prompt: Text("e.g. Open Browser"))
                .textFieldStyle(.roundedBorder)
        case .runShell:
            TextField("Command", text: binding(\.shellCommand, default: ""), prompt: Text("e.g. echo hello"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        case .openApp:
            HStack(spacing: 6) {
                TextField("Bundle ID", text: binding(\.appBundleID, default: ""), prompt: Text("com.apple.Safari"))
                    .textFieldStyle(.roundedBorder)
                TextField("App Name", text: binding(\.appName, default: ""), prompt: Text("Safari"))
                    .textFieldStyle(.roundedBorder)
            }
        case .openURL:
            TextField("URL", text: binding(\.urlString, default: ""), prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
        case .sendKey:
            HStack(spacing: 6) {
                TextField("Key", text: binding(\.toKey, default: ""), prompt: Text("a, space, return"))
                    .textFieldStyle(.roundedBorder)
            }
        case .setVariable:
            HStack(spacing: 6) {
                TextField("Variable", text: binding(\.variableName, default: ""), prompt: Text("myVar"))
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: binding(\.variableValue, default: ""), prompt: Text("some value"))
                    .textFieldStyle(.roundedBorder)
            }
        case .toggleVariable:
            TextField("Variable", text: binding(\.variableName, default: ""), prompt: Text("myVar"))
                .textFieldStyle(.roundedBorder)
        case .incrementVariable:
            HStack(spacing: 6) {
                TextField("Variable", text: binding(\.variableName, default: ""), prompt: Text("counter"))
                    .textFieldStyle(.roundedBorder)
                TextField("Step", text: binding(\.variableValue, default: ""), prompt: Text("1"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)
            }
        case .setNotification:
            TextField("Message", text: binding(\.notificationMessage, default: ""), prompt: Text("Hello!"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        case .openFile:
            TextField("File path", text: binding(\.filePath, default: ""), prompt: Text("~/Documents"))
                .textFieldStyle(.roundedBorder)
        case .runAppleScript:
            TextEditor(text: binding(\.scriptBody, default: ""))
                .font(.caption.monospaced())
                .frame(minHeight: 60, maxHeight: 100)
                .border(.quaternary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<MenuBarItemAction, String>, default: String) -> Binding<String> {
        Binding(
            get: { action[keyPath: keyPath] },
            set: { newValue in
                var copy = action
                copy[keyPath: keyPath] = newValue
                onChange(copy)
            }
        )
    }
}

/// Find a child by ID in the tree recursively.
private func findChild(id: UUID, in items: [MenuBarItem]) -> MenuBarItem? {
    for item in items {
        if item.id == id { return item }
        if let found = findChild(id: id, in: item.children) { return found }
    }
    return nil
}

// MARK: - Icon Picker (reusable grid)

private struct IconPickerGrid: View {
    @Binding var icon: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6),
                spacing: 4
            ) {
                ForEach(MenuBarItem.availableIcons, id: \.self) { candidate in
                    Button {
                        icon = candidate
                        dismiss()
                    } label: {
                        Image(systemName: candidate)
                            .font(.body)
                            .frame(width: 28, height: 28)
                            .background(
                                candidate == icon
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 220, height: 260)
    }
}

// MARK: - Icon Picker (for top-level items)

private struct IconPickerView: View {
    @Binding var item: MenuBarItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        IconPickerGrid(icon: $item.icon)
    }
}
