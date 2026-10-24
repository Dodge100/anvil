import SwiftUI

// MARK: - Command Palettes View

/// The "Command Palette" tab: manages palettes and the commands inside them.
struct CommandPaletteView: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        NavigationSplitView {
            CommandPaletteSidebar(store: store)
                .navigationTitle("Command Palettes")
        } detail: {
            CommandPaletteEditorPane(store: store)
                .frame(minWidth: 560)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.addCommandPalette()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new command palette")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let id = store.selectedCommandPaletteID {
                        store.showCommandPalette(id)
                    }
                } label: {
                    Image(systemName: "play")
                }
                .disabled(store.selectedCommandPalette == nil)
                .help("Show the selected palette")

                ProfileSwitcherButton(store: store)
            }
        }
    }
}

// MARK: - Sidebar

private struct CommandPaletteSidebar: View {
    @ObservedObject var store: RemapStore
    @State private var searchText = ""
    @State private var paletteToDelete: CommandPalette?

    private var filteredPalettes: [CommandPalette] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.commandPalettes }
        return store.commandPalettes.filter {
            $0.name.lowercased().contains(query) || $0.style.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            paletteList
        }
        .frame(minWidth: 280, maxWidth: 380)
        .alert(
            "Delete \"\(paletteToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { paletteToDelete != nil },
                set: { if !$0 { paletteToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { paletteToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = paletteToDelete?.id {
                    store.deleteCommandPalette(id)
                }
                paletteToDelete = nil
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
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
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
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var paletteList: some View {
        if filteredPalettes.isEmpty {
            ContentUnavailableView {
                Label(searchText.isEmpty ? "No Palettes" : "No Matches", systemImage: "command.square")
            } description: {
                Text(searchText.isEmpty
                     ? "Add a palette to launch commands from anywhere."
                     : "No palettes match the current search.")
            } actions: {
                Button("Add Palette") {
                    store.addCommandPalette()
                }
            }
        } else {
            List(selection: $store.selectedCommandPaletteID) {
                ForEach(filteredPalettes) { palette in
                    CommandPaletteRow(palette: palette)
                        .tag(palette.id)
                        .contextMenu {
                            contextMenuItems(for: palette)
                        }
                }
                .onMove { source, dest in
                    store.moveCommandPalette(from: source, to: dest)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for palette: CommandPalette) -> some View {
        Button {
            store.toggleCommandPaletteEnabled(palette.id)
        } label: {
            Text(palette.isEnabled ? "Disable" : "Enable")
        }

        Button {
            store.duplicateCommandPalette(palette.id)
        } label: {
            Text("Duplicate")
        }

        Button(role: .destructive) {
            paletteToDelete = palette
        } label: {
            Text("Delete")
        }
    }
}

// MARK: - Palette Row

private struct CommandPaletteRow: View {
    let palette: CommandPalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: palette.icon)
                .foregroundStyle(palette.isEnabled ? .secondary : .tertiary)
                .frame(width: 16)
            Text(palette.name.isEmpty ? "Untitled" : palette.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(palette.style.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .opacity(palette.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Editor Pane

private struct CommandPaletteEditorPane: View {
    @ObservedObject var store: RemapStore
    @State private var selectedItemID: UUID?
    @State private var showIconPicker = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if let palette = store.selectedCommandPalette {
                editorContent(palette: palette)
            } else {
                ContentUnavailableView {
                    Label("No Palette Selected", systemImage: "command.square")
                } description: {
                    Text("Select a palette from the sidebar, or add a new one.")
                } actions: {
                    Button {
                        store.addCommandPalette()
                    } label: {
                        Text("Add Palette")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editorContent(palette: CommandPalette) -> some View {
        let binding = Binding(
            get: { palette },
            set: { newPalette in
                if let index = store.commandPalettes.firstIndex(where: { $0.id == newPalette.id }) {
                    store.commandPalettes[index] = newPalette
                    store.saveCommandPalettes()
                }
            }
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(palette: palette, binding: binding)
                triggerCard(palette: palette, binding: binding)
                commandsCard(palette: palette, binding: binding)
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .onChange(of: store.selectedCommandPaletteID) { _, _ in
            selectedItemID = nil
        }
        .alert(
            "Delete \"\(store.selectedCommandPalette?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = store.selectedCommandPaletteID {
                    store.deleteCommandPalette(id)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: Header

    private func headerCard(palette: CommandPalette, binding: Binding<CommandPalette>) -> some View {
        EditorCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        showIconPicker.toggle()
                    } label: {
                        Image(systemName: palette.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showIconPicker) {
                        IconPickerGrid(icon: binding.icon)
                    }

                    TextField("Name", text: binding.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.weight(.semibold))

                    Toggle("", isOn: binding.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .help(palette.isEnabled ? "Enabled" : "Disabled")

                    Menu {
                        Button {
                            store.duplicateCommandPalette(palette.id)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Style")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: binding.style) {
                        ForEach(CommandPaletteStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.icon)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(palette.style.helpText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if palette.style == .shelf {
                        Label("Either/or: no commands = plain file shelf. Add up to 4 commands to act on the files you drop (paths are passed to shell and app commands).", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Position")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: binding.spawn) {
                        ForEach(CommandPaletteSpawn.allCases) { spawn in
                            Text(spawn.rawValue).tag(spawn)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(palette.spawn.helpText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Panels can also be dragged by their background while open.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Trigger

    private func triggerCard(palette: CommandPalette, binding: Binding<CommandPalette>) -> some View {
        EditorCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trigger")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text("Hotkey")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    KeyComboCaptureField(
                        modifiers: palette.hotkey.mandatoryModifiers,
                        key: palette.hotkey.key,
                        isCapturing: store.isCapturingCommandPaletteHotkey,
                        onStart: { store.startCommandPaletteHotkeyCapture(for: palette.id) },
                        onCancel: { store.stopCommandPaletteHotkeyCapture() }
                    )

                    if palette.hasHotkey {
                        Button("Clear") {
                            binding.wrappedValue.hotkey = KeyShortcut()
                            store.saveCommandPalettes()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("Options")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Toggle("Show in Menu Bar", isOn: binding.showInMenuBar)
                        .toggleStyle(.checkbox)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("Preview")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Button {
                        store.showCommandPalette(palette.id)
                    } label: {
                        Label("Show Palette", systemImage: "play")
                    }
                    .disabled(!palette.isEnabled)

                    Spacer()
                }

                if store.remapNeedsPermission {
                    Label(
                        "Global hotkeys need Accessibility permission.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Commands

    private func commandsCard(palette: CommandPalette, binding: Binding<CommandPalette>) -> some View {
        EditorCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Commands")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addCommandPaletteItem(to: palette.id)
                        selectedItemID = store.selectedCommandPalette?.items.last?.id
                    } label: {
                        Label("Add Command", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                if palette.items.isEmpty {
                    Text("No commands yet. Add one to give this palette something to do.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 2) {
                        ForEach(palette.items) { item in
                            commandRow(item: item, paletteID: palette.id, isSelected: item.id == selectedItemID)
                        }
                    }
                }

                if let selectedItem = palette.items.first(where: { $0.id == selectedItemID }) {
                    Divider()
                        .padding(.vertical, 4)
                    commandEditor(item: selectedItem, paletteID: palette.id, showsLookPicker: palette.style == .spotlight)
                }
            }
        }
    }

    private func commandRow(item: CommandPaletteItem, paletteID: UUID, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.caption)
                .foregroundStyle(item.isEnabled ? .secondary : .tertiary)
                .frame(width: 18)
            Text(item.name.isEmpty ? "Untitled" : item.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if item.look == .strip {
                Text("Strip Box")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            if item.action.kind != .none {
                Text(item.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemID = isSelected ? nil : item.id
        }
        .contextMenu {
            Button {
                selectedItemID = item.id
            } label: {
                Text("Edit")
            }
            Button {
                store.duplicateCommandPaletteItem(item.id, in: paletteID)
            } label: {
                Text("Duplicate")
            }
            Button(role: .destructive) {
                store.deleteCommandPaletteItem(item.id, from: paletteID)
                if selectedItemID == item.id { selectedItemID = nil }
            } label: {
                Text("Delete")
            }
        }
        .opacity(item.isEnabled ? 1 : 0.5)
    }

    private func commandEditor(item: CommandPaletteItem, paletteID: UUID, showsLookPicker: Bool = false) -> some View {
        let itemBinding = Binding(
            get: { item },
            set: { newItem in
                store.updateCommandPaletteItem(newItem.id, in: paletteID) { $0 = newItem }
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Name", text: itemBinding.name)
                    .textFieldStyle(.roundedBorder)
                Toggle("Enabled", isOn: itemBinding.isEnabled)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Text("Icon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("SF Symbol", text: itemBinding.icon)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Subtitle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("Optional description", text: itemBinding.subtitle)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Category")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("Optional group (Spotlight tabs)", text: itemBinding.category)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }

            if showsLookPicker {
                HStack(spacing: 8) {
                    Text("Look")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: itemBinding.look) {
                        ForEach(CommandPaletteItemLook.allCases) { look in
                            Text(look.rawValue).tag(look)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .help(item.look.helpText)
                    Text(item.look.helpText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Text("Colour")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                ForEach(CommandPaletteItem.availableTints, id: \.self) { tint in
                    Button {
                        itemBinding.wrappedValue.tint = tint
                    } label: {
                        Circle()
                            .fill(Color(commandPaletteTintName: tint))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(item.tint == tint ? 0.8 : 0), lineWidth: 2)
                            )
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .help(tint.capitalized)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Keywords")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("Comma separated search terms", text: Binding(
                    get: { item.keywords.joined(separator: ", ") },
                    set: { newValue in
                        let parts = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        itemBinding.wrappedValue.keywords = parts
                    }
                ))
                .textFieldStyle(.roundedBorder)
                Spacer()
            }

            HStack(alignment: .top, spacing: 8) {
                Text("Action")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: itemBinding.action.kind) {
                        ForEach(MenuBarActionKind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.icon)
                                .tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    Text(item.action.kind.helpText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if item.action.kind != .none {
                SimpleActionParametersEditor(
                    action: itemBinding.action,
                    manipulators: store.manipulators
                )
                .padding(.leading, 108)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}
