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

    func install() {
        guard statusItems.isEmpty else { return }
        addStatusItem(id: UUID(), icon: "keyboard", menu: placeholderMenu())
    }

    func attach(store: RemapStore) {
        self.store = store
        rebuildAll()
        store.$menuBarItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildAll() }
            .store(in: &cancellables)
    }

    func removeAll() {
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
        fallbackID = nil
    }

    func rebuildAll() {
        guard let store else { return }

        // Respect the "Show in Menu Bar" preference
        if !UserDefaults.standard.bool(forKey: "showInMenuBar") {
            removeAll()
            return
        }

        let items = store.menuBarItems.filter { $0.isEnabled }
        let activeIDs = Set(items.map(\.id))

        // Remove stale items
        for (id, item) in statusItems where !activeIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
        }

        // Keep at least one item so the app doesn't vanish
        if items.isEmpty {
            ensureFallback()
            return
        }
        removeFallback()

        // Create/update
        for menuItem in items {
            let statusItem = statusItems[menuItem.id] ?? addStatusItem(id: menuItem.id, icon: menuItem.icon, menu: nil)
            configure(statusItem, with: menuItem)
        }
    }

    // MARK: - Plumbing

    private func addStatusItem(id: UUID, icon: String, menu: NSMenu?) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: "")
        item.menu = menu
        statusItems[id] = item
        return item
    }

    private func configure(_ statusItem: NSStatusItem, with mbItem: MenuBarItem) {
        statusItem.button?.image = NSImage(systemSymbolName: mbItem.icon.isEmpty ? "circle" : mbItem.icon, accessibilityDescription: mbItem.name)
        statusItem.button?.toolTip = mbItem.name

        if !mbItem.children.isEmpty {
            statusItem.menu = buildMenu(for: mbItem)
            statusItem.button?.action = nil
            statusItem.button?.target = nil
        } else if mbItem.leftClickAction?.kind != .none || mbItem.rightClickAction?.kind != .none {
            statusItem.menu = nil
            statusItem.button?.action = #selector(handleClick(_:))
            statusItem.button?.target = self
            statusItem.button?.cell?.representedObject = mbItem.id
        } else {
            let m = NSMenu()
            m.addItem(withTitle: mbItem.name, action: nil, keyEquivalent: "")
            statusItem.menu = m
            statusItem.button?.action = nil
            statusItem.button?.target = nil
        }
    }

    // MARK: - Menu building

    private func buildMenu(for item: MenuBarItem) -> NSMenu {
        let menu = NSMenu(title: item.name)
        menu.addItem(withTitle: item.name, action: nil, keyEquivalent: "")

        // Parent item's own actions as menu entries
        if let left = item.leftClickAction, left.kind != .none {
            menu.addItem(makeActionItem(title: "Left Click: \(left.summary)", id: item.id, useRight: false))
        }
        if let right = item.rightClickAction, right.kind != .none {
            menu.addItem(makeActionItem(title: "⌥ Click: \(right.summary)", id: item.id, useRight: true))
        }
        if item.leftClickAction?.kind != .none || item.rightClickAction?.kind != .none || !item.children.isEmpty {
            menu.addItem(.separator())
        }

        // Children — recursively build submenus
        for child in item.children where child.isEnabled {
            if child.isSeparator {
                menu.addItem(.separator())
            } else if child.children.isEmpty {
                let mi = makeActionItem(title: child.name, id: child.id, useRight: false)
                if !child.icon.isEmpty { mi.image = NSImage(systemSymbolName: child.icon, accessibilityDescription: child.name) }
                menu.addItem(mi)
            } else {
                let sub = buildSubmenu(for: child)
                let pi = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                pi.submenu = sub
                if !child.icon.isEmpty { pi.image = NSImage(systemSymbolName: child.icon, accessibilityDescription: child.name) }
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
                let mi = makeActionItem(title: child.name, id: child.id, useRight: false)
                if !child.icon.isEmpty { mi.image = NSImage(systemSymbolName: child.icon, accessibilityDescription: child.name) }
                sub.addItem(mi)
            } else {
                let nestedSub = buildSubmenu(for: child)
                let pi = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
                pi.submenu = nestedSub
                if !child.icon.isEmpty { pi.image = NSImage(systemSymbolName: child.icon, accessibilityDescription: child.name) }
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
        fallbackID = nil
    }

    // MARK: - Actions

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let id = sender.cell?.representedObject as? UUID,
              let store, let item = store.menuBarItems.first(where: { $0.id == id }) else { return }
        let useOption = NSEvent.modifierFlags.contains(.option)
        if useOption, let action = item.rightClickAction, action.kind != .none {
            store.executeMenuBarAction(action)
        } else if let action = item.leftClickAction, action.kind != .none {
            store.executeMenuBarAction(action)
        }
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
        }
        return nil
    }

    @objc private func showAnvil() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
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
                .onAppear { StatusBarController.shared.attach(store: store) }
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
            }
        }

        Settings {
            SettingsView(store: store)
                .onAppear { StatusBarController.shared.attach(store: store) }
        }
    }
}
