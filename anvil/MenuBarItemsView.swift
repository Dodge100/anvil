import SwiftUI
import UniformTypeIdentifiers

// Menu bar items editor, styled to mirror the Remaps editor (RemapView /
// ManipulatorEditorView): a NavigationSplitView with a two-line sidebar list
// and a flat sectioned detail pane — no Form or card chrome.

struct MenuBarItemsView: View {
    @ObservedObject var store: RemapStore
    // Local search state — sharing the store's searchText with RemapView meant
    // a query typed here silently filtered the Remaps sidebar too.
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            MenuBarItemsSidebar(store: store, searchText: $searchText)
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
    @Binding var searchText: String
    @State private var itemToDelete: MenuBarItem?

    var body: some View {
        itemList
            .frame(minWidth: 280, maxWidth: 380)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationTitle("Menu Bar")
            .toolbar {
                Button { store.addMenuBarItem() } label: {
                    Image(systemName: "plus")
                }
                .help("Add menu bar item")
            }
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

    private var itemList: some View {
        List(selection: $store.selectedMenuBarItemID) {
            ForEach(filteredItems) { item in
                MenuBarItemRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        contextMenuItems(for: item)
                    }
            }
            .onMove { store.moveMenuBarItem(from: $0, to: $1, within: filteredItems) }
            .onDelete { indexSet in
                if let index = indexSet.first, filteredItems.indices.contains(index) {
                    itemToDelete = filteredItems[index]
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var filteredItems: [MenuBarItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.menuBarItems }
        return store.menuBarItems.filter { $0.name.lowercased().contains(query) }
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

// MARK: - Sidebar row (two lines, like ManipulatorRow)

private struct MenuBarItemRow: View, Equatable {
    let item: MenuBarItem

    static func == (lhs: MenuBarItemRow, rhs: MenuBarItemRow) -> Bool {
        lhs.item == rhs.item
    }

    private var subCount: Int {
        item.children.count + item.rightChildren.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isSeparator ? "minus" : (item.icon.isEmpty ? "circle" : item.icon))
                .foregroundStyle(item.isEnabled ? .secondary : .tertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.isSeparator ? "Separator" : (item.name.isEmpty ? "Untitled" : item.name))
                    .lineLimit(1)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !item.isSeparator && subCount > 0 {
                Text("\(subCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
        .opacity(item.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Editor pane

private struct MenuBarItemEditorPane: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        Group {
            if let id = store.selectedMenuBarItemID,
               let index = store.menuBarItems.firstIndex(where: { $0.id == id }) {
                MenuBarItemForm(
                    item: Binding(
                        get: { store.menuBarItems[index] },
                        set: { store.menuBarItems[index] = $0; store.saveMenuBarItems() }
                    ),
                    onDelete: { store.deleteMenuBarItem(id) },
                    onAddChild: { store.addMenuBarChildItem(to: id) },
                    onAddRightChild: { store.addMenuBarRightChildItem(to: id) },
                    onConvertSeparator: { store.toggleMenuBarItemSeparator(id) }
                )
                .id(id)
            } else {
                ContentUnavailableView {
                    Text("No Item Selected")
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
        .navigationTitle(store.selectedMenuBarItem?.name ?? "Menu Bar Item")
    }
}

// MARK: - Detail form (flat sections)

private struct MenuBarItemForm: View {
    @Binding var item: MenuBarItem
    var onDelete: () -> Void
    var onAddChild: () -> Void
    var onAddRightChild: () -> Void
    var onConvertSeparator: () -> Void

    @State private var showIconPicker = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                if item.isSeparator {
                    separatorSection
                } else {
                    leftClickSection
                    rightClickSection
                }
                dangerSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(
            "Delete \"\(item.name)\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: Header (icon / name / enabled) — mirrors ManipulatorEditorView's header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    showIconPicker.toggle()
                } label: {
                    Image(systemName: item.isSeparator ? "minus" : (item.icon.isEmpty ? "circle" : item.icon))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .popover(isPresented: $showIconPicker) {
                    SymbolPickerView(symbols: MenuBarItem.availableIcons, icon: $item.icon)
                }

                TextField("Name", text: $item.name)
                    .font(.title)
                    .labelsHidden()

                Toggle("Enabled", isOn: $item.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Text(item.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Separator

    private var separatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Separators only work inside a menu. As a top-level item this does nothing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Convert to Item") {
                onConvertSeparator()
            }
        }
    }

    // MARK: Left click

    private var leftClickSection: some View {
        clickSection(
            label: "Left click",
            kind: leftKindBinding,
            action: actionBinding(\.leftClickAction),
            children: $item.children,
            onAddSubItem: onAddChild,
            hint: clickHint(
                kind: item.leftClickAction?.kind ?? .none,
                hasChildren: !item.children.isEmpty,
                opensOnThisClick: item.hasLeftAction
            )
        )
    }

    // MARK: Right click

    private var rightClickSection: some View {
        clickSection(
            label: "Right click",
            kind: rightKindBinding,
            action: actionBinding(\.rightClickAction),
            children: $item.rightChildren,
            onAddSubItem: onAddRightChild,
            hint: Text("Right-click the menu bar icon. Falls back to Left Click when set to None.")
        )
    }

    /// A click behavior block: mode picker → mode-specific editor → footnote.
    private func clickSection(
        label: String,
        kind: Binding<MenuBarActionKind>,
        action: Binding<MenuBarItemAction>,
        children: Binding<[MenuBarItem]>,
        onAddSubItem: @escaping () -> Void,
        hint: Text? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(label, selection: kind) {
                ForEach(MenuBarActionKind.allCases) { k in
                    Text(k.rawValue).tag(k)
                }
            }

            switch kind.wrappedValue {
            case .none:
                EmptyView()
            case .showMenu:
                subItemsEditor(for: children, onAdd: onAddSubItem)
            default:
                actionParameters(action: action)
            }

            if let hint {
                hint
            }
        }
    }

    // MARK: Danger

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete Item", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Kind bindings

    private var leftKindBinding: Binding<MenuBarActionKind> {
        Binding(
            get: { item.leftClickAction?.kind ?? .none },
            set: {
                if item.leftClickAction == nil {
                    item.leftClickAction = MenuBarItemAction(kind: $0)
                } else {
                    item.leftClickAction?.kind = $0
                }
            }
        )
    }

    private var rightKindBinding: Binding<MenuBarActionKind> {
        Binding(
            get: { item.rightClickAction?.kind ?? .none },
            set: {
                if item.rightClickAction == nil {
                    item.rightClickAction = MenuBarItemAction(kind: $0)
                } else {
                    item.rightClickAction?.kind = $0
                }
            }
        )
    }

    private func actionBinding(
        _ keyPath: WritableKeyPath<MenuBarItem, MenuBarItemAction?>
    ) -> Binding<MenuBarItemAction> {
        Binding(
            get: { item[keyPath: keyPath] ?? MenuBarItemAction(kind: .none) },
            set: { item[keyPath: keyPath] = $0 }
        )
    }

    /// Footnote under the left-click section: state the consequences plainly.
    private func clickHint(kind: MenuBarActionKind, hasChildren: Bool, opensOnThisClick: Bool) -> Text? {
        if kind == .showMenu {
            return Text(kind.helpText)
        }
        if hasChildren {
            return Text("Set Left Click to \u{201C}Show Menu\u{201D} to open this menu.")
        }
        if opensOnThisClick {
            return Text("Opens when the icon is clicked.")
        }
        return nil
    }

    // MARK: - Action parameters

    @ViewBuilder
    private func actionParameters(action: Binding<MenuBarItemAction>) -> some View {
        switch action.wrappedValue.kind {
        case .none, .showMenu:
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
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .labelsHidden()
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

// MARK: - Sub-items editor (both click menus use this)

@ViewBuilder
private func subItemsEditor(
    for children: Binding<[MenuBarItem]>,
    onAdd: @escaping () -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        if children.wrappedValue.isEmpty {
            Text("No sub-items. Add one to make this a menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(children.wrappedValue.enumerated()), id: \.element.id) { index, _ in
                MenuBarChildRow(
                    child: Binding(
                        get: { children.wrappedValue[index] },
                        set: { newValue in
                            if children.wrappedValue.indices.contains(index) {
                                children.wrappedValue[index] = newValue
                            }
                        }
                    ),
                    index: index,
                    siblingCount: children.wrappedValue.count,
                    siblingIDsProvider: { children.wrappedValue.map(\.id) },
                    onMove: { source, target in
                        children.wrappedValue.move(fromOffsets: source, toOffset: target)
                    },
                    onDelete: { id in
                        children.wrappedValue.removeAll { $0.id == id }
                    }
                )
            }
        }

        Button {
            onAdd()
        } label: {
            Label("Add Sub-item", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Child row (recursive, flat)

private struct MenuBarChildRow: View {
    @Binding var child: MenuBarItem
    let index: Int
    let siblingCount: Int
    /// Identity of the rows this drop target sits among, read at drop time.
    var siblingIDsProvider: () -> [UUID] = { [] }
    var onMove: (IndexSet, Int) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void

    @State private var showIconPicker = false
    @State private var showActions = false
    @State private var childrenExpanded = true
    @State private var showDeleteAlert = false
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    Image(systemName: child.isSeparator ? "minus" : (child.icon.isEmpty ? "circle" : child.icon))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    SymbolPickerView(symbols: MenuBarItem.availableIcons, icon: $child.icon)
                }

                // Name
                TextField("Name", text: $child.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)

                // Action summary badge (submenus can't have click actions)
                if child.children.isEmpty {
                    actionBadge
                }

                Spacer()

                // Enable toggle
                Toggle("", isOn: $child.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(child.isEnabled ? "Enabled" : "Disabled")

                rowMenu
            }
            .padding(.vertical, 4)
            .opacity(child.isEnabled ? 1 : 0.5)
            .background(
                isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onDrop(
                of: [UTType.text],
                delegate: MenuBarChildDropDelegate(
                    targetIndex: index,
                    siblingIDs: siblingIDsProvider,
                    onMove: onMove
                )
            )

            // ── Nested children ──
            if !child.children.isEmpty, childrenExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(child.children.enumerated()), id: \.element.id) { index, _ in
                        MenuBarChildRow(
                            child: Binding(
                                get: { child.children[index] },
                                set: { newValue in
                                    if child.children.indices.contains(index) {
                                        child.children[index] = newValue
                                    }
                                }
                            ),
                            index: index,
                            siblingCount: child.children.count,
                            siblingIDsProvider: { child.children.map(\.id) },
                            onMove: { source, target in
                                child.children.move(fromOffsets: source, toOffset: target)
                            },
                            onDelete: { id in
                                child.children.removeAll { $0.id == id }
                            }
                        )
                    }

                    Button {
                        // Add a sub-sub-item directly through the row binding.
                        var grandchild = MenuBarItem()
                        grandchild.name = "New Sub-item"
                        child.children.append(grandchild)
                    } label: {
                        Label("Add Sub-item", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                }
                .padding(.leading, 20)
            }
        }
        .alert(
            "Delete \"\(child.name)\"?",
            isPresented: $showDeleteAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(child.id)
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: Action badge / popover

    @ViewBuilder
    private var actionBadge: some View {
        if child.hasLeftAction || child.hasRightAction {
            Button {
                showActions.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "cursorarrow.click")
                        .font(.caption2)
                    if child.hasLeftAction {
                        Text("L").font(.caption2.weight(.medium))
                    }
                    if child.hasRightAction {
                        Text("R").font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Edit click actions")
            .popover(isPresented: $showActions, arrowEdge: .trailing) {
                ChildActionEditor(child: $child)
            }
        } else {
            Button {
                showActions.toggle()
            } label: {
                Image(systemName: "cursorarrow.click")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help("Configure click actions")
            .popover(isPresented: $showActions, arrowEdge: .trailing) {
                ChildActionEditor(child: $child)
            }
        }
    }

    // MARK: Context menu

    private var rowMenu: some View {
        Menu {
            Button {
                child.isEnabled.toggle()
            } label: {
                Text(child.isEnabled ? "Disable" : "Enable")
            }
            Button {
                onMove(IndexSet(integer: index), index - 1)
            } label: {
                Text("Move Up")
            }
            .disabled(index == 0)
            Button {
                onMove(IndexSet(integer: index), index + 2)
            } label: {
                Text("Move Down")
            }
            .disabled(index >= siblingCount - 1)
            Divider()
            Button {
                var grandchild = MenuBarItem()
                grandchild.name = "New Sub-item"
                child.children.append(grandchild)
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
}

// MARK: - Drop delegate (drag reorder among the row's own siblings)

private struct MenuBarChildDropDelegate: DropDelegate {
    /// Index of the row this delegate is attached to.
    let targetIndex: Int
    /// Sibling ids of the row's own list, read when the drop lands.
    let siblingIDs: () -> [UUID]
    /// Move within the owning list (SwiftUI List move semantics).
    var onMove: (IndexSet, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let target = targetIndex
        let move = onMove
        let ids = siblingIDs
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                let currentIDs = ids()
                guard let source = currentIDs.firstIndex(of: id), source != target else { return }
                move(IndexSet(integer: source), target)
            }
        }
        return true
    }
}

// MARK: - Child action editor (popover for sub-item click actions)

private struct ChildActionEditor: View {
    @Binding var child: MenuBarItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))

            actionRow(label: "Left click", side: .left)
            actionRow(label: "Right click", side: .right)
        }
        .padding(14)
        .frame(width: 360)
    }

    private enum ActionSide { case left, right }

    private func actionRow(label: String, side: ActionSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(label, selection: actionKindBinding(side: side)) {
                    ForEach(MenuBarActionKind.allCases.filter { $0 != .showMenu }) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .labelsHidden()

                Spacer()

                if currentAction(side: side).kind != .none {
                    Button("Clear") {
                        setAction(side: side, to: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            if currentAction(side: side).kind != .none {
                childActionParameters(action: actionBinding(side: side))
                    .padding(.leading, 0)
            }
        }
    }

    private func currentAction(side: ActionSide) -> MenuBarItemAction {
        switch side {
        case .left: return child.leftClickAction ?? MenuBarItemAction(kind: .none)
        case .right: return child.rightClickAction ?? MenuBarItemAction(kind: .none)
        }
    }

    private func actionBinding(side: ActionSide) -> Binding<MenuBarItemAction> {
        switch side {
        case .left:
            return Binding(
                get: { child.leftClickAction ?? MenuBarItemAction(kind: .none) },
                set: { child.leftClickAction = $0 }
            )
        case .right:
            return Binding(
                get: { child.rightClickAction ?? MenuBarItemAction(kind: .none) },
                set: { child.rightClickAction = $0 }
            )
        }
    }

    private func actionKindBinding(side: ActionSide) -> Binding<MenuBarActionKind> {
        Binding(
            get: { currentAction(side: side).kind },
            set: { newKind in
                if currentAction(side: side).kind == .none {
                    setAction(side: side, to: MenuBarItemAction(kind: newKind))
                } else {
                    var updated = currentAction(side: side)
                    updated.kind = newKind
                    setAction(side: side, to: updated)
                }
            }
        )
    }

    private func setAction(side: ActionSide, to action: MenuBarItemAction?) {
        switch side {
        case .left: child.leftClickAction = action
        case .right: child.rightClickAction = action
        }
    }
}

// MARK: - Child action parameter fields

@ViewBuilder
private func childActionParameters(action: Binding<MenuBarItemAction>) -> some View {
    switch action.wrappedValue.kind {
    case .none, .showMenu:
        EmptyView()
    case .runShortcut:
        TextField("Shortcut name", text: action.shortcutName, prompt: Text("e.g. Open Browser"))
            .textFieldStyle(.roundedBorder)
    case .runShell:
        TextField("Command", text: action.shellCommand, prompt: Text("e.g. echo hello"), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
    case .openApp:
        HStack(spacing: 6) {
            TextField("Bundle ID", text: action.appBundleID, prompt: Text("com.apple.Safari"))
                .textFieldStyle(.roundedBorder)
            TextField("App Name", text: action.appName, prompt: Text("Safari"))
                .textFieldStyle(.roundedBorder)
        }
    case .openURL:
        TextField("URL", text: action.urlString, prompt: Text("https://example.com"))
            .textFieldStyle(.roundedBorder)
    case .sendKey:
        HStack(spacing: 6) {
            TextField("Key", text: action.toKey, prompt: Text("a, space, return"))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 2) {
                ForEach(ModifierKey.flagBased, id: \.self) { mod in
                    Toggle(mod.symbol, isOn: Binding(
                        get: { action.wrappedValue.toModifiers.contains(mod) },
                        set: {
                            if $0 { action.wrappedValue.toModifiers.insert(mod) }
                            else { action.wrappedValue.toModifiers.remove(mod) }
                        }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
        }
    case .setVariable:
        HStack(spacing: 6) {
            TextField("Variable", text: action.variableName, prompt: Text("myVar"))
                .textFieldStyle(.roundedBorder)
            TextField("Value", text: action.variableValue, prompt: Text("some value"))
                .textFieldStyle(.roundedBorder)
        }
    case .toggleVariable:
        TextField("Variable", text: action.variableName, prompt: Text("myVar"))
            .textFieldStyle(.roundedBorder)
    case .incrementVariable:
        HStack(spacing: 6) {
            TextField("Variable", text: action.variableName, prompt: Text("counter"))
                .textFieldStyle(.roundedBorder)
            TextField("Step", text: action.variableValue, prompt: Text("1"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 60)
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
            .frame(minHeight: 60, maxHeight: 100)
            .border(.quaternary)
    }
}
