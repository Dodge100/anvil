import SwiftUI
import AppKit
import Combine

// MARK: - Status Bar Controller
// Each enabled MenuBarItem becomes its own icon in the macOS menu bar.

final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var store: RemapStore?
    private var cancellables: Set<AnyCancellable> = []
    private var rebuildWorkItem: DispatchWorkItem?
    private var iconCache: [String: NSImage] = [:]

    func install() {
        guard statusItems.isEmpty else { return }
        addStatusItem(id: UUID(), icon: "keyboard", menu: placeholderMenu())
    }

    func attach(store: RemapStore) {
        // Guard against double-attach (ContentView + Settings both call attach).
        if self.store === store, !cancellables.isEmpty { return }
        cancellables.removeAll()
        self.store = store
        rebuildAll()
        store.$menuBarItems
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)
    }

    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildAll() }
        rebuildWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func cachedIcon(named name: String, fallback: String = "circle") -> NSImage? {
        let key = name.isEmpty ? fallback : name
        if let cached = iconCache[key] { return cached }
        let image = NSImage(systemSymbolName: key, accessibilityDescription: key)
        if let image { iconCache[key] = image }
        return image
    }

    func removeAll() {
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
        orderedIDs = []
        fallbackID = nil
        transientMenuIDs.removeAll()
    }

    func rebuildAll() {
        guard let store else { return }

        // Respect the "Show in Menu Bar" preference
        if !UserDefaults.standard.bool(forKey: "showInMenuBar") {
            removeAll()
            return
        }

        // Top-level separators are only meaningful inside menus, never as
        // standalone status icons (they render as stray "—" in the menu bar).
        let items = store.menuBarItems.filter { $0.isEnabled && !$0.isSeparator }
        let activeIDs = Set(items.map(\.id))

        // Remove stale items (collect first — mutating while iterating is unsafe)
        let staleIDs = statusItems.keys.filter { !activeIDs.contains($0) && $0 != fallbackID }
        for id in staleIDs {
            if let item = statusItems[id] {
                NSStatusBar.system.removeStatusItem(item)
                statusItems.removeValue(forKey: id)
            }
            orderedIDs.removeAll { $0 == id }
        }

        // Keep at least one item so the app doesn't vanish
        if items.isEmpty {
            ensureFallback()
            orderedIDs = []
            return
        }
        removeFallback()

        // NSStatusItem placement: the most recently created item appears
        // leftmost. To match the sidebar's left-to-right order, create in
        // reverse. If the sidebar was reordered, rebuild to reflect it.
        let desiredIDs = items.map(\.id)
        if orderedIDs.filter({ activeIDs.contains($0) }) != desiredIDs {
            for (_, item) in statusItems {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItems.removeAll()
            orderedIDs = []
            fallbackID = nil
        }

        // Create/update (reversed so display order matches sidebar order)
        for menuItem in items.reversed() {
            let statusItem = statusItems[menuItem.id] ?? addStatusItem(id: menuItem.id, icon: menuItem.icon, menu: nil)
            configure(statusItem, with: menuItem)
        }
        orderedIDs = desiredIDs
    }

    /// Creation order of live status items. Needed to mirror sidebar order.
    private var orderedIDs: [UUID] = []

    // MARK: - Plumbing

    private func addStatusItem(id: UUID, icon: String, menu: NSMenu?) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = cachedIcon(named: icon)
        item.menu = menu
        statusItems[id] = item
        return item
    }

    private func configure(_ statusItem: NSStatusItem, with mbItem: MenuBarItem) {
        let image = cachedIcon(named: mbItem.icon)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = mbItem.name

        let hasMenuClick = (mbItem.leftClickAction?.kind ?? .none) == .showMenu
            || (mbItem.rightClickAction?.kind ?? .none) == .showMenu

        if hasMenuClick || mbItem.hasLeftAction || mbItem.hasRightAction {
            // Manual click handling: each click can run an action directly
            // or open its own sub-items menu (Show Menu).
            statusItem.menu = nil
            statusItem.button?.action = #selector(handleClick(_:))
            statusItem.button?.target = self
            // Without this, right-click never reaches handleClick —
            // the user is forced to ⌥-click instead.
            statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem.button?.cell?.representedObject = mbItem.id
        } else if !mbItem.children.isEmpty {
            // No click behavior configured: the system shows the sub-items
            // menu on any click.
            statusItem.menu = buildMenu(title: mbItem.name, children: mbItem.children)
            statusItem.button?.action = nil
            statusItem.button?.target = nil
        } else {
            let m = NSMenu()
            m.addItem(withTitle: mbItem.name, action: nil, keyEquivalent: "")
            statusItem.menu = m
            statusItem.button?.action = nil
            statusItem.button?.target = nil
        }
    }

    // MARK: - Menu building

    private func buildMenu(title: String, children: [MenuBarItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        if !children.isEmpty {
            menu.addItem(.separator())
        }

        // Children — recursively build submenus
        for child in children where child.isEnabled {
            if child.isSeparator {
                menu.addItem(.separator())
            } else if child.children.isEmpty {
                // Sub-items with no action render as plain (disabled) text rows.
                let mi = child.hasLeftAction
                    ? makeActionItem(title: child.name, id: child.id, useRight: false)
                    : NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                if !child.icon.isEmpty { mi.image = cachedIcon(named: child.icon) }
                menu.addItem(mi)
            } else {
                let sub = buildSubmenu(for: child)
                let pi = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                pi.submenu = sub
                if !child.icon.isEmpty { pi.image = cachedIcon(named: child.icon) }
                menu.addItem(pi)
            }
        }

        menu.addItem(.separator())
        menu.addItem(makePlainItem(title: "Show Anvil", action: #selector(showAnvil)))
        menu.addItem(.separator())
        menu.addItem(makePlainItem(title: "Quit", action: #selector(quitApp), key: "q"))
        return menu
    }

    private func makeActionItem(title: String, id: UUID, useRight: Bool) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(executeAction(_:)), keyEquivalent: "")
        mi.representedObject = ActionPayload(id: id, useRight: useRight)
        mi.target = self
        return mi
    }

    private func makePlainItem(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    /// Recursively build an NSMenu for a menu bar item that has children.
    private func buildSubmenu(for item: MenuBarItem) -> NSMenu {
        let sub = NSMenu(title: item.name)
        for child in item.children where child.isEnabled {
            if child.isSeparator {
                sub.addItem(.separator())
            } else if child.children.isEmpty {
                // Sub-items with no action render as plain (disabled) text rows.
                let mi = child.hasLeftAction
                    ? makeActionItem(title: child.name, id: child.id, useRight: false)
                    : NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                if !child.icon.isEmpty { mi.image = cachedIcon(named: child.icon) }
                sub.addItem(mi)
            } else {
                let nestedSub = buildSubmenu(for: child)
                let pi = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                pi.submenu = nestedSub
                if !child.icon.isEmpty { pi.image = cachedIcon(named: child.icon) }
                sub.addItem(pi)
            }
        }
        return sub
    }

    // MARK: - Fallback (empty state)

    private var fallbackID: UUID?

    private func ensureFallback() {
        guard fallbackID == nil else { return }
        let menu = NSMenu()
        menu.addItem(makePlainItem(title: "Show Anvil", action: #selector(showAnvil)))
        menu.addItem(.separator())
        menu.addItem(makePlainItem(title: "Quit", action: #selector(quitApp), key: "q"))
        let id = UUID()
        addStatusItem(id: id, icon: "keyboard", menu: menu)
        fallbackID = id
    }

    private func removeFallback() {
        guard let id = fallbackID, let item = statusItems[id] else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItems.removeValue(forKey: id)
        orderedIDs.removeAll { $0 == id }
        fallbackID = nil
    }

    // MARK: - Actions

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let id = sender.cell?.representedObject as? UUID,
              let store, let item = store.menuBarItems.first(where: { $0.id == id }),
              let statusItem = statusItems[id] else { return }
        // Right-click (two-finger / Ctrl-click) OR ⌥-click triggers the
        // right behavior. Plain left-click triggers the left behavior.
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
        let leftKind = item.leftClickAction?.kind ?? .none
        let rightKind = item.rightClickAction?.kind ?? .none

        if isRight {
            if rightKind == .showMenu {
                showTransientMenu(title: item.name, children: item.rightChildren, itemID: id, on: statusItem)
            } else if let action = item.rightClickAction, rightKind != .none {
                store.executeMenuBarAction(action)
            } else if let action = item.leftClickAction, leftKind != .none, leftKind != .showMenu {
                // Fallback: right-click with no right behavior still does the left action
                store.executeMenuBarAction(action)
            }
        } else {
            if leftKind == .showMenu {
                showTransientMenu(title: item.name, children: item.children, itemID: id, on: statusItem)
            } else if let action = item.leftClickAction, leftKind != .none {
                store.executeMenuBarAction(action)
            }
        }
    }

    /// Status items currently showing a transient click-triggered menu.
    private var transientMenuIDs: Set<UUID> = []
    /// Reentrancy guard while popping a transient menu via performClick.
    private var isShowingTransientMenu = false

    /// Temporarily attach a menu and open it as if the icon were clicked.
    /// The menu is detached again in menuDidClose(_:) so the next click is
    /// routed through handleClick(_:) — the stock way to show a menu for
    /// only one mouse button while the other runs an action.
    private func showTransientMenu(title: String, children: [MenuBarItem], itemID: UUID, on statusItem: NSStatusItem) {
        guard !isShowingTransientMenu, let button = statusItem.button else { return }
        let menu = buildMenu(title: title, children: children)
        menu.delegate = self
        transientMenuIDs.insert(itemID)
        isShowingTransientMenu = true
        statusItem.menu = menu
        button.performClick(nil)
        isShowingTransientMenu = false
    }

    @objc private func executeAction(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? ActionPayload, let store else { return }
        guard let target = findItem(id: p.id, in: store.menuBarItems) else { return }
        if p.useRight, let action = target.rightClickAction, action.kind != .none {
            store.executeMenuBarAction(action)
        } else if let action = target.leftClickAction, action.kind != .none {
            store.executeMenuBarAction(action)
        }
    }

    private func findItem(id: UUID, in items: [MenuBarItem]) -> MenuBarItem? {
        for item in items {
            if item.id == id { return item }
            if let found = findItem(id: id, in: item.children) { return found }
            if let found = findItem(id: id, in: item.rightChildren) { return found }
        }
        return nil
    }

    @objc private func showAnvil() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - NSMenuDelegate (transient click-triggered menus)

extension StatusBarController: NSMenuDelegate {
    /// Detach a transient menu once it closes so the next click is routed
    /// through handleClick(_:) again instead of reopening the menu.
    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let matched = self.transientMenuIDs.filter { self.statusItems[$0]?.menu === menu }
            for id in matched {
                self.statusItems[id]?.menu = nil
                self.transientMenuIDs.remove(id)
            }
        }
    }
}

// MARK: - Helpers

private struct ActionPayload { let id: UUID; let useRight: Bool }

private func placeholderMenu() -> NSMenu {
    let m = NSMenu()
    m.addItem(withTitle: "Starting…", action: nil, keyEquivalent: "")
    return m
}

// MARK: - App

struct AnvilApp: App {
    @StateObject private var store = RemapStore()

    init() {
        UserDefaults.standard.register(defaults: ["showInMenuBar": true])
        StatusBarController.shared.install()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1100, minHeight: 700)
                .frame(idealWidth: 1280, idealHeight: 800)
                .onAppear {
                    StatusBarController.shared.attach(store: store)
                    CommandPaletteController.shared.attach(store: store)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Add standard File menu items for manipulator management
            CommandGroup(after: .newItem) {
                Button("New Manipulator") {
                    store.addManipulator()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Manipulator…") {
                    store.importManipulatorFromPanel()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Export Manipulator…") {
                    if let id = store.selectedManipulatorID {
                        store.exportManipulator(id)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(store.selectedManipulatorID == nil)
            }

            // Undo/Redo in Edit menu (replaces hidden button approach)
            CommandGroup(after: .pasteboard) {
                Button("Undo") {
                    store.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)

                Button("Redo") {
                    store.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedo)
            }

            // View menu for palette and config access
            CommandMenu("View") {
                Toggle("Show Macro Palette", isOn: Binding(
                    get: { store.isPaletteShown },
                    set: { _ in store.toggleMacroPalette() }
                ))
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Menu("Command Palettes") {
                    let palettes = store.commandPalettes.filter { $0.isEnabled }
                    if palettes.isEmpty {
                        Text("No command palettes")
                    } else {
                        ForEach(palettes) { palette in
                            Button {
                                store.showCommandPalette(palette.id)
                            } label: {
                                Label(palette.name.isEmpty ? "Untitled" : palette.name, systemImage: palette.icon)
                            }
                        }
                    }
                }
            }

            CommandMenu("Manipulator") {
                if let selectedManipulator = store.manipulators.first(where: { $0.id == store.selectedManipulatorID }) {
                    Button("Duplicate Manipulator") {
                        store.duplicateManipulator(selectedManipulator.id)
                    }
                    .keyboardShortcut("d", modifiers: [.command])

                    Button("Delete Manipulator") {
                        store.deleteManipulator(selectedManipulator.id)
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])

                    Divider()

                    Button(selectedManipulator.isEnabled ? "Disable Manipulator" : "Enable Manipulator") {
                        store.toggleEnabled(selectedManipulator.id)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button(selectedManipulator.isStarred ? "Unstar Manipulator" : "Star Manipulator") {
                        store.toggleStarred(selectedManipulator.id)
                    }

                    Divider()

                    Button("Select Next Manipulator") {
                        store.selectNextManipulator()
                    }
                    .keyboardShortcut(.downArrow, modifiers: [.control, .command])

                    Button("Select Previous Manipulator") {
                        store.selectPreviousManipulator()
                    }
                    .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                } else {
                    Button("Duplicate Manipulator") { }
                    .disabled(true)
                    .keyboardShortcut("d", modifiers: [.command])

                    Button("Delete Manipulator") { }
                    .disabled(true)
                    .keyboardShortcut(.delete, modifiers: [.command])

                    Divider()

                    Button("Enable Manipulator") { }
                    .disabled(true)
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button("Star Manipulator") { }
                    .disabled(true)

                    Divider()

                    Button("Select Next Manipulator") { }
                    .disabled(true)
                    .keyboardShortcut(.downArrow, modifiers: [.control, .command])

                    Button("Select Previous Manipulator") { }
                    .disabled(true)
                    .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                }
            }
        }

        Settings {
            SettingsView(store: store)
                .onAppear { StatusBarController.shared.attach(store: store) }
        }
    }
}