import AppKit
import Combine
import SwiftUI

// MARK: - Command Palette Controller

/// Borderless floating panel that can become key without activating the app:
/// AppKit rejects `makeKeyAndOrderFront` for plain borderless panels, which
/// left the search field unable to receive keyboard input.
final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Presents command palettes in their configured style, routes global hotkeys to
/// them, and mirrors palettes that are flagged to appear in the menu bar.
@MainActor
final class CommandPaletteController: ObservableObject {
    static let shared = CommandPaletteController()

    // MARK: - State

    /// The palette currently on screen, if any.
    @Published private(set) var activePalette: CommandPalette?
    /// Search text for the active palette.
    @Published var query: String = "" {
        didSet {
            if query != oldValue {
                selectedIndex = 0
                updatePanelSize()
            }
        }
    }
    /// Index of the highlighted entry in the filtered results.
    @Published private(set) var selectedIndex: Int = 0
    /// Category tab selected in the Spotlight style (nil = all categories).
    @Published var selectedCategory: String?
    /// Files gathered by dropping onto a shelf-style palette this session.
    @Published private(set) var droppedFiles: [URL] = []
    /// Bumped shortly after a palette becomes key so SwiftUI re-asserts the
    /// search field focus (focus set during onAppear is dropped — the panel is
    /// not key yet at that point).
    @Published var searchFocusTick = 0

    private var panel: NSPanel?
    private weak var store: RemapStore?
    private var previousApp: NSRunningApplication?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // MARK: Drag-shake gesture (Dropover-style shelf reveal)

    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    /// Recent cursor samples of the current drag, (time, point).
    private var dragTrack: [(time: TimeInterval, point: NSPoint)] = []
    private var lastShelfReveal: TimeInterval = 0

    // MARK: - Setup

    /// Attach the store so hotkeys, menu bar items and actions can be resolved.
    func attach(store: RemapStore) {
        self.store = store
        store.$commandPalettes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildStatusItems()
                    self?.refreshActivePalette()
                }
            }
            .store(in: &cancellables)
        rebuildStatusItems()
        installMonitors()
    }

    private func installMonitors() {
        guard globalKeyMonitor == nil else { return }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalKeyDown(event)
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseDown()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.panel != nil {
                return self.handlePaletteKeyDown(event) ? nil : event
            }
            if self.handleGlobalKeyDown(event) { return nil }
            return event
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            // Only swallow the click when it dismisses the palette.
            return self.handleMouseDown() ? nil : event
        }
    }

    // MARK: - Showing

    /// Present a palette in its configured style.
    /// - Parameter activate: false when revealed mid-drag, so the drag isn't disturbed.
    func show(_ palette: CommandPalette, activate: Bool = true) {
        guard palette.isEnabled else { return }
        if activate {
            previousApp = NSWorkspace.shared.frontmostApplication
        }

        dismissPanel()
        activePalette = palette
        query = ""
        selectedIndex = 0
        selectedCategory = nil
        droppedFiles = []

        let style = palette.style
        let size = panelSize(for: style)
        let panel = CommandPalettePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = palette.name
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.level = style == .shelf ? .statusBar : .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: CommandPalettePanelView(controller: self))
        // The controller owns the window size (adaptive panelSize above); without
        // this the hosting view resizes the window to SwiftUI's ideal size, which
        // collapses to zero for flexible layouts like the 2×2 shelf grid.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrameOrigin(origin(for: style, size: size))

        self.panel = panel
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hosting)
        invalidatePanelShadow()
        // Focus set during onAppear runs before the panel is key and is dropped.
        // Nudge the views shortly after the panel is key to (re-)focus the field.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard let self, self.panel != nil else { return }
            self.searchFocusTick += 1
        }
    }

    /// Close the palette if it is open.
    func hide() {
        guard panel != nil else { return }
        dismissPanel()
        activePalette = nil
        query = ""
        selectedIndex = 0
        selectedCategory = nil
        droppedFiles = []
        // Hand focus back to whatever was frontmost before the palette opened.
        if let previousApp {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    /// Open the palette if it is closed, close it if it is already showing.
    func toggle(_ palette: CommandPalette) {
        if activePalette?.id == palette.id, panel != nil {
            hide()
        } else {
            show(palette)
        }
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Re-read the active palette from the store so live edits are reflected.
    private func refreshActivePalette() {
        guard let id = activePalette?.id, let store else { return }
        if let updated = store.commandPalettes.first(where: { $0.id == id }) {
            activePalette = updated
        }
    }

    // MARK: - Results

    /// The items shown for the active palette, filtered by the search query.
    var filteredItems: [CommandPaletteItem] {
        guard let palette = activePalette else { return [] }
        let items = palette.enabledItems
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { $0.searchText.lowercased().contains(query) }
    }

    /// The items shown after the category tab filter is applied.
    private var presentedItems: [CommandPaletteItem] {
        guard let category = selectedCategory, !category.isEmpty else { return filteredItems }
        return filteredItems.filter { $0.category == category }
    }

    /// Commands rendered as boxes in the strip under the search field.
    var stripItems: [CommandPaletteItem] {
        presentedItems.filter { $0.look == .strip }
    }

    /// Commands rendered as full-width spotlight rows.
    var rowItems: [CommandPaletteItem] {
        presentedItems.filter { $0.look == .row }
    }

    /// The commands the Spotlight panel presents, in selection order: strip
    /// boxes first, then full-size rows.
    var visibleItems: [CommandPaletteItem] {
        stripItems + rowItems
    }

    /// Whether the given item is the highlighted one.
    func isSelected(_ item: CommandPaletteItem) -> Bool {
        let items = visibleItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        return index == selectedIndex
    }

    /// Moves the highlight back to the first result.
    func resetSelection() {
        selectedIndex = 0
    }

    /// Run a palette item.
    /// A shelf palette with gathered files stays open so more can be added and
    /// further commands run against them; everything else closes on trigger.
    func trigger(_ item: CommandPaletteItem) {
        guard let store else { return }
        let files = droppedFiles
        if activePalette?.style == .shelf && !files.isEmpty {
            // Keep the shelf on screen (Dropover-style).
        } else {
            hide()
        }
        store.executeCommandPaletteAction(item.action, shelfFiles: files)
    }

    // MARK: - Dropped files

    /// Adds a file dropped onto a shelf palette.
    func addDroppedFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !droppedFiles.contains(where: { $0.standardizedFileURL == standardized }) else { return }
        droppedFiles.append(standardized)
    }

    /// Removes one gathered file.
    func removeDroppedFile(_ url: URL) {
        droppedFiles.removeAll { $0 == url }
    }

    /// Clears every gathered file.
    func clearDroppedFiles() {
        droppedFiles.removeAll()
    }

    // MARK: - Keyboard

    private func handlePaletteKeyDown(_ event: NSEvent) -> Bool {
        // Digits and letters are intentionally not intercepted: they must type
        // into the search field.
        switch event.keyCode {
        case 125: // ↓
            moveSelection(by: navigationRowStep)
        case 126: // ↑
            moveSelection(by: -navigationRowStep)
        case 123: // ←
            moveSelection(by: -1)
        case 124: // →
            moveSelection(by: 1)
        case 36, 76: // Return / Enter
            triggerSelected()
        case 53: // Escape
            hide()
        default:
            return false
        }
        return true
    }

    /// Number of items the selection jumps when moving vertically.
    private var navigationRowStep: Int {
        activePalette?.style == .grid ? 4 : 1
    }

    private func moveSelection(by offset: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        let next = selectedIndex + offset
        if next < 0 {
            selectedIndex = 0
        } else if next >= count {
            selectedIndex = count - 1
        } else {
            selectedIndex = next
        }
    }

    private func triggerSelected() {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        trigger(items[selectedIndex])
    }

    // MARK: - Global hotkeys

    /// Returns true when the event matched a palette hotkey.
    private func handleGlobalKeyDown(_ event: NSEvent) -> Bool {
        guard let store, !store.isCapturingCommandPaletteHotkey else { return false }
        let keyID = store.keyID(from: event)
        let modifiers = store.modifiers(from: event.modifierFlags)
        guard let palette = store.commandPalettes.first(where: { palette in
            palette.isEnabled && palette.hasHotkey && Self.hotkey(palette.hotkey, matches: keyID, modifiers: modifiers)
        }) else { return false }
        toggle(palette)
        return true
    }

    /// Compares a configured hotkey against an incoming key press.
    private static func hotkey(_ hotkey: KeyShortcut, matches keyID: String, modifiers: Set<ModifierKey>) -> Bool {
        guard hotkey.key == keyID else { return false }
        let required = hotkey.mandatoryModifiers
        guard required.isSubset(of: modifiers) else { return false }
        // Caps lock and fn are ignored so they never block a shortcut.
        let extra = modifiers.subtracting(required).subtracting([.capsLock, .fn])
        return extra.isEmpty
    }

    // MARK: - Outside click

    /// Dismisses the palette when the user clicks outside of it.
    private func handleMouseDown() -> Bool {
        guard let panel else { return false }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) { return false }
        hide()
        return true
    }

    // MARK: - Drag-shake gesture

    /// Whether a visible shelf palette exists and the reveal gesture is active.
    private var hasEnabledShelfPalette: Bool {
        guard let store else { return false }
        return store.commandPalettes.contains { $0.isEnabled && $0.style == .shelf }
    }

    /// Installs or removes the drag monitors used to reveal the shelf by
    /// shaking/wiggling the cursor while holding dragged files.
    private func updateShelfGestureMonitor() {
        if hasEnabledShelfPalette {
            guard dragMonitor == nil else { return }
            dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                Task { @MainActor in
                    self?.handleDragEvent(event)
                }
            }
            dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                Task { @MainActor in
                    self?.dragTrack.removeAll()
                }
            }
        } else if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
            if let monitor = dragEndMonitor {
                NSEvent.removeMonitor(monitor)
                dragEndMonitor = nil
            }
            dragTrack.removeAll()
        }
    }

    /// Tracks the cursor path and reveals the shelf when it looks like a
    /// shake/wiggle: a long path that stays in a small area during a file drag.
    private func handleDragEvent(_ event: NSEvent) {
        guard panel == nil else { return }

        // Only react to drags that actually carry files (e.g. from Finder).
        let types = NSPasteboard(name: .drag).types ?? []
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        guard types.contains(.fileURL) || types.contains(filenamesType) else {
            dragTrack.removeAll()
            return
        }

        let now = event.timestamp
        dragTrack.append((now, NSEvent.mouseLocation))
        dragTrack.removeAll { now - $0.time > 0.7 }
        guard dragTrack.count >= 6 else { return }

        let points = dragTrack.map(\.point)
        var pathLength: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            pathLength += hypot(b.x - a.x, b.y - a.y)
        }
        let displacement = hypot(
            points[points.count - 1].x - points[0].x,
            points[points.count - 1].y - points[0].y
        )

        if pathLength > 260, displacement < 110, now - lastShelfReveal > 1.5 {
            lastShelfReveal = now
            dragTrack.removeAll()
            if let store,
               let palette = store.commandPalettes.first(where: { $0.isEnabled && $0.style == .shelf }) {
                show(palette, activate: false)
            }
        }
    }

    // MARK: - Placement

    /// The size the panel uses for a given style, adapted to the current results.
    private func panelSize(for style: CommandPaletteStyle) -> CGSize {
        switch style {
        case .spotlight:
            // Collapses to a single search field until there is something to show.
            if query.isEmpty && filteredItems.isEmpty {
                return CGSize(width: 460, height: 64)
            }
            let hasCategories = categories(for: filteredItems).isEmpty == false
            // The strip of boxes under the search field, when any commands use it.
            let stripHeight: CGFloat = stripItems.isEmpty ? 0 : 84
            let chrome: CGFloat = 48 + stripHeight + (hasCategories ? 27 : 0) + 16
            let rows = min(rowItems.count, 8)
            let height: CGFloat
            if rows == 0 && stripItems.isEmpty {
                // The "no matches" placeholder.
                height = chrome + 110
            } else {
                height = chrome + CGFloat(rows) * 44 + CGFloat(max(rows - 1, 0)) * 2
            }
            // A strip palette may grow taller than the rows-only cap so the
            // strip never gets squeezed out.
            let cap: CGFloat = stripItems.isEmpty ? 452 : 541
            return CGSize(width: 640, height: min(cap, height))
        case .shelf:
            // Square drop shelf (Dropover-style).
            return CGSize(width: 260, height: 260)
        case .circular:
            return CGSize(width: 460, height: 460)
        case .grid:
            return CGSize(width: 720, height: 460)
        }
    }

    /// Categories present in a list of items, in first-seen order.
    func categories(for items: [CommandPaletteItem]) -> [String] {
        var seen: [String] = []
        for item in items {
            let category = item.category.trimmingCharacters(in: .whitespaces)
            if !category.isEmpty && !seen.contains(category) {
                seen.append(category)
            }
        }
        return seen
    }

    /// Resizes the panel so it fits the current results.
    private func updatePanelSize() {
        guard let panel, let style = activePalette?.style else { return }
        let size = panelSize(for: style)
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: style, size: size))
        invalidatePanelShadow()
    }

    /// Re-derives the window shadow from the current content silhouette.
    private func invalidatePanelShadow() {
        panel?.invalidateShadow()
    }

    /// Computes the on-screen origin for a palette of the given style and size.
    private func origin(for style: CommandPaletteStyle, size: CGSize) -> NSPoint {
        let frame = targetScreen.visibleFrame
        switch activePalette?.spawn ?? .standard {
        case .cursor:
            return clamped(nearCursorOrigin(style: style, size: size), frame: frame, size: size)
        case .screenCenter:
            return NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        case .standard:
            switch style {
            case .spotlight, .grid:
                // Anchored a fixed distance from the top of the screen, growing downwards.
                let top = frame.maxY - frame.height * 0.12
                return NSPoint(x: frame.midX - size.width / 2, y: top - size.height)
            case .shelf, .circular:
                return clamped(nearCursorOrigin(style: style, size: size), frame: frame, size: size)
            }
        }
    }

    /// Origin centred on the mouse; drop shelves sit just below the cursor so a
    /// dragged file doesn't cover them.
    private func nearCursorOrigin(style: CommandPaletteStyle, size: CGSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let belowCursor: CGFloat = style == .shelf ? 60 : 0
        return NSPoint(x: mouse.x - size.width / 2, y: mouse.y - belowCursor - size.height / 2)
    }

    /// Keeps a panel origin fully on screen.
    private func clamped(_ point: NSPoint, frame: NSRect, size: CGSize) -> NSPoint {
        var origin = point
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        return origin
    }

    /// The screen the palette should appear on — the one under the mouse.
    private var targetScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
    }

    // MARK: - Menu bar

    /// Mirrors palettes flagged with `showInMenuBar` as status items.
    private func rebuildStatusItems() {
        updateShelfGestureMonitor()
        guard let store else { return }
        let palettes = store.commandPalettes.filter { $0.isEnabled && $0.showInMenuBar }
        let activeIDs = Set(palettes.map(\.id))

        for (id, item) in statusItems where !activeIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
        }

        for palette in palettes {
            let statusItem: NSStatusItem
            if let existing = statusItems[palette.id] {
                statusItem = existing
            } else {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItems[palette.id] = statusItem
            }
            statusItem.button?.image = NSImage(systemSymbolName: palette.icon, accessibilityDescription: palette.name)
            statusItem.button?.toolTip = palette.name
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusItemClicked(_:))
            statusItem.button?.cell?.representedObject = palette.id
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let id = sender.cell?.representedObject as? UUID,
              let store,
              let palette = store.commandPalettes.first(where: { $0.id == id }) else { return }
        toggle(palette)
    }
}
