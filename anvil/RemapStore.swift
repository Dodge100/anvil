import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - Notifications

extension Notification.Name {
    static let menuBarItemsDidChange = Notification.Name("menuBarItemsDidChange")
}

// MARK: - Undo/Redo

private struct UndoSnapshot: Equatable {
    var manipulators: [Manipulator]
    var selectedManipulatorID: UUID?
}

@MainActor
final class RemapStore: ObservableObject {
    @Published var manipulators: [Manipulator] = []
    @Published var selectedManipulatorID: UUID?
    @Published var searchText: String = ""
    @Published var selectedTags: Set<String> = []
    @Published var toastMessage: String? = nil

    private var toastTask: Task<Void, Never>?

    /// Debounced filtered results to avoid recomputing on every keystroke.
    @Published private(set) var debouncedFilteredManipulators: [Manipulator] = []
    private var searchCancellable: AnyCancellable?

    // Undo/redo stacks
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []

    /// Push the current state onto the undo stack before making a mutation.
    /// Automatically discards the redo stack (a new action invalidates redo).
    private func pushUndo() {
        let snapshot = UndoSnapshot(
            manipulators: manipulators,
            selectedManipulatorID: selectedManipulatorID
        )
        undoStack.append(snapshot)
        // Cap undo stack to prevent unbounded memory growth
        let maxUndoDepth = 200
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        // New action invalidates redo
        redoStack.removeAll()
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        // Save current state to redo
        let current = UndoSnapshot(
            manipulators: manipulators,
            selectedManipulatorID: selectedManipulatorID
        )
        redoStack.append(current)
        // Restore previous state
        let snapshot = undoStack.removeLast()
        manipulators = snapshot.manipulators
        selectedManipulatorID = snapshot.selectedManipulatorID
        // Trigger remap engine update
        applyRemaps()
        // Update published state
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        // Save current state to undo
        let current = UndoSnapshot(
            manipulators: manipulators,
            selectedManipulatorID: selectedManipulatorID
        )
        undoStack.append(current)
        // Restore next state
        let snapshot = redoStack.removeLast()
        manipulators = snapshot.manipulators
        selectedManipulatorID = snapshot.selectedManipulatorID
        // Trigger remap engine update
        applyRemaps()
        // Update published state
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    @Published private(set) var isRecordingTrigger = false
    @Published private(set) var recordedTriggerSteps: [KeyShortcut] = []
    @Published private(set) var isCapturingToKey = false

    // MARK: - Clipboard

    /// Internal clipboard storage for Get/Set/Clear Clipboard actions.
    @Published var clipboardText: String = ""

    // MARK: - Config Profiles

    @Published var profiles: [ConfigProfile] = []
    @Published var activeProfileID: UUID {
        didSet { saveProfilesManifest() }
    }

    /// The currently active profile object.
    var activeProfile: ConfigProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    @Published private(set) var remapStatusText = "No active remaps"
    @Published private(set) var remapNeedsPermission = false
    @Published private(set) var remapIsActive = false
    @Published var isPaletteShown = false

    private var paletteWindow: NSWindow?

    /// Bundle ID of the previously frontmost app, for the Activate Last App action.
    private var previousFrontmostBundleID: String?
    private var currentFrontmostBundleID: String?
    private var appActivationObserver: NSObjectProtocol?

    /// Kept alive so speech isn't cut off mid-sentence.
    fileprivate let speechSynthesizer = AVSpeechSynthesizer()

    let engine: KeyboardRemapEngine
    private let daemonMode: Bool

    private var triggerRecordingMonitor: Any?
    private var triggerRecordingManipulatorID: UUID?
    private var triggerRecordingAdditionalTriggerID: UUID?
    private var toKeyMonitor: Any?
    private var configFileSource: DispatchSourceFileSystemObject?
    private var saveConfigTask: Task<Void, Never>?
    private var applyRemapsTask: Task<Void, Never>?
    private var saveMenuBarItemsTask: Task<Void, Never>?

    static let appSupportURL: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.appendingPathComponent("Anvil")
    }()

    static let configURL: URL = appSupportURL.appendingPathComponent("config.json")

    static let profilesManifestURL: URL = appSupportURL.appendingPathComponent("profiles.json")

    static let profilesDirectoryURL: URL = appSupportURL.appendingPathComponent("profiles")

    /// Returns the file URL for a given profile's manipulator data.
    static func profileConfigURL(for id: UUID) -> URL {
        profilesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    static let statusURL: URL = appSupportURL.appendingPathComponent("status.json")
    static let globalVarsURL: URL = appSupportURL.appendingPathComponent("global_vars.json")

    init(engine: KeyboardRemapEngine? = nil, daemonMode: Bool = false) {
        self.engine = engine ?? KeyboardRemapEngine()
        self.daemonMode = daemonMode

        // ── Profile setup ────────────────────────────────────────────
        let (loadedProfiles, loadedActiveID) = Self.loadOrCreateProfilesManifest()
        self.profiles = loadedProfiles
        self.activeProfileID = loadedActiveID

        // ── Load from active profile ────────────────────────────────
        if let profileData = Self.loadProfileData(id: loadedActiveID) {
            self.manipulators = profileData.manipulators
            self.menuBarItems = profileData.menuBarItems
        } else if daemonMode {
            // Fall back to the legacy config.json
            self.manipulators = Self.loadConfig() ?? []
            self.menuBarItems = []
        } else {
            self.manipulators = []
            self.menuBarItems = MenuBarItem.defaults()
        }

        if !daemonMode {
            self.selectedManipulatorID = self.manipulators.first?.id
        } else {
            self.selectedManipulatorID = nil
        }

        self.engine.onStateChange = { [weak self] state in
            Task { @MainActor in self?.updateRemapState(state) }
        }
        self.engine.onExecuteAction = { [weak self] manipulator, action, proxy in
            Task { @MainActor in
                self?.executeAction(action, of: manipulator, proxy: proxy)
            }
        }

        // Load persistent global variables
        if let globalVars = Self.loadGlobalVariables() {
            self.engine.loadGlobalVariables(globalVars)
        }

        // Persist global variables when changed
        self.engine.onGlobalVariablesChange = { vars in
            Self.saveGlobalVariables(vars)
        }

        // Track app activations so Activate Last App can switch back.
        self.currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        self.appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let newApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                if let current = self.currentFrontmostBundleID, current != newApp?.bundleIdentifier {
                    self.previousFrontmostBundleID = current
                }
                self.currentFrontmostBundleID = newApp?.bundleIdentifier
            }
        }

        applyRemaps()
        if !daemonMode {
            // Mirror active profile to config.json for backward compatibility
            mirrorToConfigJSON()
            DaemonManager.installIfNeeded()
        }

        // Initialize debounced filter with the full list
        debouncedFilteredManipulators = computeFilteredManipulators()

        // Recompute filtered list when search, tags, OR manipulators change.
        // Manipulators changes (e.g. profile switch) use a short debounce so the
        // sidebar updates nearly instantly while search still feels smooth.
        searchCancellable = Publishers.CombineLatest3(
            $searchText.debounce(for: .milliseconds(150), scheduler: DispatchQueue.main),
            $selectedTags,
            $manipulators.debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
        )
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            self.debouncedFilteredManipulators = self.computeFilteredManipulators()
        }


    }

    deinit {
        for monitor in [triggerRecordingMonitor, toKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        searchCancellable?.cancel()
        saveConfigTask?.cancel()
        applyRemapsTask?.cancel()
        saveMenuBarItemsTask?.cancel()
        // Cancel dispatch source synchronously in deinit
        configFileSource?.cancel()
        configFileSource = nil
    }

    // MARK: - Menu Bar Items

    @Published var menuBarItems: [MenuBarItem] = []
    @Published var selectedMenuBarItemID: UUID?

    var selectedMenuBarItem: MenuBarItem? {
        guard let id = selectedMenuBarItemID else { return nil }
        return menuBarItems.first { $0.id == id }
    }

    // MARK: - Derived State

    @Published private var _allTags: [String] = []
    @Published private var _allFolders: [String] = []

    var allTags: [String] { _allTags }
    var allFolders: [String] { _allFolders }

    /// Rebuild tag/folder caches. Called after any manipulators mutation.
    private func rebuildTagFolderCache() {
        _allTags = Array(Set(manipulators.flatMap(\.tags))).sorted()
        _allFolders = Array(Set(manipulators.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    /// Core filtering logic, extracted for reuse with debounce.
    private func computeFilteredManipulators() -> [Manipulator] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return manipulators
            .filter { manipulator in
                if !selectedTags.isEmpty {
                    let hasAny = !selectedTags.isDisjoint(with: manipulator.tags)
                    if !hasAny { return false }
                }
                if query.isEmpty { return true }
                if manipulator.name.lowercased().contains(query) { return true }
                if manipulator.notes.lowercased().contains(query) { return true }
                if manipulator.trigger.displayLabel.lowercased().contains(query) { return true }
                if manipulator.actions.contains(where: { $0.summary.lowercased().contains(query) }) { return true }
                return false
            }
            .sorted { lhs, rhs in
                if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled && !rhs.isEnabled }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var selectedManipulator: Manipulator? {
        guard let id = selectedManipulatorID else { return nil }
        return manipulators.first { $0.id == id }
    }

    // MARK: - Selection

    func selectManipulator(_ id: UUID?) {
        selectedManipulatorID = id
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func clearTagFilter() {
        selectedTags.removeAll()
    }

    // MARK: - Mutators

    func addManipulator() {
        pushUndo()
        let manipulator = Manipulator(name: "New Manipulator")
        manipulators.append(manipulator)
        selectedManipulatorID = manipulator.id
        applyRemaps()
    }

    func duplicateManipulator(_ id: UUID) {
        pushUndo()
        guard let source = manipulators.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " Copy"
        // Deep-copy actions to ensure independent state (Action uses COW reference)
        copy.actions = source.actions.map { $0.deepCopy() }
        // Deep-copy additional triggers too
        copy.additionalTriggers = source.additionalTriggers.map { additional in
            var dup = additional
            dup.id = UUID()
            dup.conditions = additional.conditions.map { condition in
                var c = condition
                c.id = UUID()
                return c
            }
            return dup
        }
        if let index = manipulators.firstIndex(where: { $0.id == id }) {
            manipulators.insert(copy, at: index + 1)
        } else {
            manipulators.append(copy)
        }
        selectedManipulatorID = copy.id
        applyRemaps()
    }

    func deleteManipulator(_ id: UUID) {
        pushUndo()
        guard let index = manipulators.firstIndex(where: { $0.id == id }) else { return }
        let nextSelection: UUID? = {
            if manipulators.indices.contains(index + 1) {
                return manipulators[index + 1].id
            } else if manipulators.indices.contains(index - 1) {
                return manipulators[index - 1].id
            } else {
                return nil
            }
        }()
        if selectedManipulatorID == id {
            selectedManipulatorID = nextSelection
        }
        manipulators.remove(at: index)
        applyRemaps()
    }

    func updateManipulator(_ id: UUID, _ transform: (inout Manipulator) -> Void) {
        guard let index = manipulators.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        transform(&manipulators[index])
        scheduleApplyRemaps()
    }

    /// Update a manipulator without scheduling an engine rebuild.
    /// Use for cosmetic-only edits (name, notes, folder) where routing is unaffected.
    func updateManipulatorCosmetic(_ id: UUID, _ transform: (inout Manipulator) -> Void) {
        guard let index = manipulators.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        transform(&manipulators[index])
        // Bump objectWillChange so SwiftUI re-renders, but skip the expensive
        // routing rebuild + disk write entirely.
        objectWillChange.send()
    }

    /// Update a manipulator and immediately apply routing (no debounce).
    /// Use when the routing result must be visible instantly (e.g. undo/redo).
    func updateManipulatorImmediate(_ id: UUID, _ transform: (inout Manipulator) -> Void) {
        guard let index = manipulators.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        transform(&manipulators[index])
        applyRemaps()
    }

    func updateSelectedManipulator(_ transform: (inout Manipulator) -> Void) {
        guard let id = selectedManipulatorID else { return }
        updateManipulator(id, transform)
    }

    func updateAction(_ actionID: UUID, in manipulatorID: UUID, _ transform: (inout Action) -> Void) {
        updateManipulator(manipulatorID) { manipulator in
            guard let index = manipulator.actions.firstIndex(where: { $0.id == actionID }) else { return }
            transform(&manipulator.actions[index])
        }
    }

    func updateCondition(_ conditionID: UUID, in manipulatorID: UUID, _ transform: (inout Condition) -> Void) {
        updateManipulator(manipulatorID) { manipulator in
            guard let index = manipulator.conditions.firstIndex(where: { $0.id == conditionID }) else { return }
            transform(&manipulator.conditions[index])
        }
    }

    func addActionToSelected() {
        pushUndo()
        updateSelectedManipulator { $0.actions.append(Action(kind: .sendKey)) }
    }

    func addActionTo(_ manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { $0.actions.append(Action(kind: .sendKey)) }
    }

    func addAction(_ kind: ActionKind, to manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { $0.actions.append(Action(kind: kind)) }
    }

    func removeAction(_ actionID: UUID, from manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            manipulator.actions.removeAll { $0.id == actionID }
        }
    }

    func moveAction(from source: IndexSet, to destination: Int, in manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            manipulator.actions.move(fromOffsets: source, toOffset: destination)
        }
    }

    func addConditionToSelected() {
        pushUndo()
        updateSelectedManipulator { $0.conditions.append(Condition()) }
    }

    func addCondition(to manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { $0.conditions.append(Condition()) }
    }

    func removeCondition(_ conditionID: UUID, from manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            manipulator.conditions.removeAll { $0.id == conditionID }
        }
    }

    func moveCondition(from source: IndexSet, to destination: Int, in manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            manipulator.conditions.move(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Menu Bar Items CRUD

    func addMenuBarItem() {
        let item = MenuBarItem(name: "New Menu Item")
        menuBarItems.append(item)
        selectedMenuBarItemID = item.id
        saveMenuBarItemsImmediate()
    }

    func duplicateMenuBarItem(_ id: UUID) {
        guard let source = menuBarItems.first(where: { $0.id == id }),
              let index = menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " Copy"
        menuBarItems.insert(copy, at: index + 1)
        selectedMenuBarItemID = copy.id
        saveMenuBarItemsImmediate()
    }

    func deleteMenuBarItem(_ id: UUID) {
        guard let index = menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        if selectedMenuBarItemID == id {
            let next = [index + 1, index - 1].first { menuBarItems.indices.contains($0) }
            selectedMenuBarItemID = next.map { menuBarItems[$0].id }
        }
        menuBarItems.remove(at: index)
        saveMenuBarItemsImmediate()
    }

    func updateMenuBarItem(_ id: UUID, _ transform: (inout MenuBarItem) -> Void) {
        guard let index = menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        transform(&menuBarItems[index])
        scheduleSaveMenuBarItems()
    }

    func updateSelectedMenuBarItem(_ transform: (inout MenuBarItem) -> Void) {
        guard let id = selectedMenuBarItemID else { return }
        updateMenuBarItem(id, transform)
    }

    func addMenuBarChildItem(to parentID: UUID) {
        guard let index = menuBarItems.firstIndex(where: { $0.id == parentID }) else {
            // Try deeper nesting
            addNestedMenuBarChildItem(to: parentID, in: &menuBarItems)
            return
        }
        let child = MenuBarItem(name: "Sub Item")
        objectWillChange.send()
        menuBarItems[index].children.append(child)
        // Submenus can't have click actions — clear any that exist.
        menuBarItems[index].leftClickAction = nil
        menuBarItems[index].rightClickAction = nil
        saveMenuBarItemsImmediate()
    }

    /// Recursively find a parent by ID and add a child.
    private func addNestedMenuBarChildItem(to parentID: UUID, in items: inout [MenuBarItem]) -> Bool {
        for i in items.indices {
            if items[i].id == parentID {
                let child = MenuBarItem(name: "Sub Item")
                objectWillChange.send()
                items[i].children.append(child)
                // Submenus can't have click actions — clear any that exist.
                items[i].leftClickAction = nil
                items[i].rightClickAction = nil
                saveMenuBarItemsImmediate()
                return true
            }
            if addNestedMenuBarChildItem(to: parentID, in: &items[i].children) {
                return true
            }
        }
        return false
    }

    /// Recursively find and update a child at any depth.
    func recursiveUpdateMenuBarItem(_ childID: UUID, in items: inout [MenuBarItem], _ transform: (inout MenuBarItem) -> Void) -> Bool {
        for i in items.indices {
            if items[i].id == childID {
                objectWillChange.send()
                transform(&items[i])
                scheduleSaveMenuBarItems()
                return true
            }
            if recursiveUpdateMenuBarItem(childID, in: &items[i].children, transform) {
                return true
            }
        }
        return false
    }

    func updateMenuBarChildItem(_ childID: UUID, in parentID: UUID, _ transform: (inout MenuBarItem) -> Void) {
        guard let parentIndex = menuBarItems.firstIndex(where: { $0.id == parentID }) else {
            // Try deeper
            _ = recursiveUpdateMenuBarItem(childID, in: &menuBarItems, transform)
            return
        }
        guard let childIndex = menuBarItems[parentIndex].children.firstIndex(where: { $0.id == childID }) else {
            _ = recursiveUpdateMenuBarItem(childID, in: &menuBarItems, transform)
            return
        }
        objectWillChange.send()
        transform(&menuBarItems[parentIndex].children[childIndex])
        scheduleSaveMenuBarItems()
    }

    func removeMenuBarSubItem(parentID: UUID, at indexSet: IndexSet) {
        guard let parentIndex = menuBarItems.firstIndex(where: { $0.id == parentID }) else { return }
        objectWillChange.send()
        for index in indexSet.sorted(by: >) {
            guard menuBarItems[parentIndex].children.indices.contains(index) else { continue }
            menuBarItems[parentIndex].children.remove(at: index)
        }
        saveMenuBarItemsImmediate()
    }

    func deleteMenuBarChildItem(_ childID: UUID, from parentID: UUID) {
        guard let parentIndex = menuBarItems.firstIndex(where: { $0.id == parentID }) else {
            _ = recursiveDeleteMenuBarChildItem(childID, in: &menuBarItems)
            return
        }
        objectWillChange.send()
        if menuBarItems[parentIndex].children.contains(where: { $0.id == childID }) {
            menuBarItems[parentIndex].children.removeAll { $0.id == childID }
            saveMenuBarItemsImmediate()
        } else {
            _ = recursiveDeleteMenuBarChildItem(childID, in: &menuBarItems)
        }
    }

    /// Recursively find and delete a child at any depth.
    private func recursiveDeleteMenuBarChildItem(_ childID: UUID, in items: inout [MenuBarItem]) -> Bool {
        for i in items.indices {
            if items[i].id == childID {
                objectWillChange.send()
                items.remove(at: i)
                saveMenuBarItemsImmediate()
                return true
            }
            if recursiveDeleteMenuBarChildItem(childID, in: &items[i].children) {
                return true
            }
        }
        return false
    }

    /// Move a child item (at any depth) up or down among its siblings.
    /// `offset` is -1 for up, +1 for down.
    func moveMenuBarChildItem(_ childID: UUID, offset: Int) {
        guard moveNestedMenuBarChildItem(childID, offset: offset, in: &menuBarItems) else { return }
        saveMenuBarItemsImmediate()
    }

    /// Recursively find the sibling list containing `childID` and move it by `offset`.
    @discardableResult
    private func moveNestedMenuBarChildItem(_ childID: UUID, offset: Int, in items: inout [MenuBarItem]) -> Bool {
        for i in items.indices {
            if let j = items[i].children.firstIndex(where: { $0.id == childID }) {
                let target = j + offset
                guard items[i].children.indices.contains(target) else { return false }
                objectWillChange.send()
                let moved = items[i].children.remove(at: j)
                items[i].children.insert(moved, at: target)
                return true
            }
            if moveNestedMenuBarChildItem(childID, offset: offset, in: &items[i].children) {
                return true
            }
        }
        return false
    }

    /// Move a child (at any depth) so it becomes a child of `targetParentID` at `targetIndex`.
    /// If the target parent is the child's current parent, this reorders it among its siblings.
    func moveMenuBarChildItem(_ childID: UUID, toParent targetParentID: UUID, atIndex targetIndex: Int) {
        guard childID != targetParentID,
              let child = findMenuBarItem(childID, in: menuBarItems),
              !containsMenuBarItem(targetParentID, in: [child]),
              let moved = extractMenuBarChildItem(childID, from: &menuBarItems),
              insertMenuBarChildItem(moved, into: targetParentID, at: targetIndex, in: &menuBarItems)
        else { return }
        saveMenuBarItemsImmediate()
    }

    private func findMenuBarItem(_ id: UUID, in items: [MenuBarItem]) -> MenuBarItem? {
        for item in items {
            if item.id == id { return item }
            if let found = findMenuBarItem(id, in: item.children) { return found }
        }
        return nil
    }

    private func containsMenuBarItem(_ id: UUID, in items: [MenuBarItem]) -> Bool {
        for item in items {
            if item.id == id { return true }
            if containsMenuBarItem(id, in: item.children) { return true }
        }
        return false
    }

    /// Remove a child at any depth from its sibling list and return it.
    @discardableResult
    private func extractMenuBarChildItem(_ childID: UUID, from items: inout [MenuBarItem]) -> MenuBarItem? {
        for i in items.indices {
            if let j = items[i].children.firstIndex(where: { $0.id == childID }) {
                objectWillChange.send()
                return items[i].children.remove(at: j)
            }
            if let found = extractMenuBarChildItem(childID, from: &items[i].children) {
                return found
            }
        }
        return nil
    }

    /// Insert an item into the children of `parentID` at `index` (searches recursively).
    @discardableResult
    private func insertMenuBarChildItem(_ item: MenuBarItem, into parentID: UUID, at index: Int, in items: inout [MenuBarItem]) -> Bool {
        for i in items.indices {
            if items[i].id == parentID {
                let clamped = min(max(index, 0), items[i].children.count)
                objectWillChange.send()
                items[i].children.insert(item, at: clamped)
                return true
            }
            if insertMenuBarChildItem(item, into: parentID, at: index, in: &items[i].children) {
                return true
            }
        }
        return false
    }

    func moveMenuBarItem(from source: IndexSet, to destination: Int) {
        menuBarItems.move(fromOffsets: source, toOffset: destination)
        saveMenuBarItemsImmediate()
    }

    func toggleMenuBarItemSeparator(_ id: UUID) {
        guard let index = menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        menuBarItems[index].isSeparator.toggle()
        if menuBarItems[index].isSeparator {
            menuBarItems[index].name = "Separator"
            menuBarItems[index].leftClickAction = nil
            menuBarItems[index].rightClickAction = nil
            menuBarItems[index].children = []
        }
        saveMenuBarItemsImmediate()
    }

    func toggleMenuBarItemEnabled(_ id: UUID) {
        guard let index = menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        menuBarItems[index].isEnabled.toggle()
        saveMenuBarItemsImmediate()
    }

    // MARK: - Menu Bar Action Execution

    func executeMenuBarAction(_ action: MenuBarItemAction) {
        action.execute(store: self)
    }

    // MARK: - Menu Bar Item helpers (used by MenuBarItemAction.execute)

    func runShellCommand(_ command: String) -> String {
        runShell(command)
    }

    func openApplication(bundleID: String, name: String) {
        openApp(bundleID: bundleID, name: name)
    }

    func postKeyCombo(modifiers: Set<ModifierKey>, keyID: String) {
        postKeyCombo(modifiers: modifiers, keyID: keyID, proxy: nil)
    }

    func showNotificationMessage(_ message: String) {
        showNotification(message)
    }

    // MARK: - Additional Triggers

    func addAdditionalTrigger(to manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) {
            $0.additionalTriggers.append(AdditionalTrigger())
        }
    }

    func removeAdditionalTrigger(_ triggerID: UUID, from manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manip in
            manip.additionalTriggers.removeAll { $0.id == triggerID }
        }
    }

    func updateAdditionalTrigger(_ triggerID: UUID, in manipulatorID: UUID, _ transform: (inout AdditionalTrigger) -> Void) {
        pushUndo()
        updateManipulator(manipulatorID) { manip in
            guard let idx = manip.additionalTriggers.firstIndex(where: { $0.id == triggerID }) else { return }
            transform(&manip.additionalTriggers[idx])
        }
    }

    func addConditionToAdditionalTrigger(_ triggerID: UUID, in manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manip in
            guard let idx = manip.additionalTriggers.firstIndex(where: { $0.id == triggerID }) else { return }
            manip.additionalTriggers[idx].conditions.append(Condition())
        }
    }

    func removeConditionFromAdditionalTrigger(_ conditionID: UUID, additionalTriggerID: UUID, manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manip in
            guard let idx = manip.additionalTriggers.firstIndex(where: { $0.id == additionalTriggerID }) else { return }
            manip.additionalTriggers[idx].conditions.removeAll { $0.id == conditionID }
        }
    }

    func startTriggerRecordingForAdditionalTrigger(_ triggerID: UUID, in manipulatorID: UUID) {
        stopAllCapture()
        isRecordingTrigger = true
        recordedTriggerSteps = []
        triggerRecordingManipulatorID = manipulatorID
        triggerRecordingAdditionalTriggerID = triggerID
        triggerRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let shortcut = self.recordedShortcut(from: event) else { return event }
            self.recordedTriggerSteps.append(shortcut)
            return nil
        }
    }

    func updateConditionInAdditionalTrigger(_ conditionID: UUID, additionalTriggerID: UUID, manipulatorID: UUID, _ transform: (inout Condition) -> Void) {
        pushUndo()
        updateManipulator(manipulatorID) { manip in
            guard let idx = manip.additionalTriggers.firstIndex(where: { $0.id == additionalTriggerID }) else { return }
            guard let ci = manip.additionalTriggers[idx].conditions.firstIndex(where: { $0.id == conditionID }) else { return }
            transform(&manip.additionalTriggers[idx].conditions[ci])
        }
    }

    func toggleTag(_ tag: String, on manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            if manipulator.tags.contains(tag) {
                manipulator.tags.remove(tag)
            } else {
                manipulator.tags.insert(tag)
            }
        }
    }

    func toggleStarred(_ manipulatorID: UUID) {
        pushUndo()
        updateManipulatorCosmetic(manipulatorID) { $0.isStarred.toggle() }
        saveConfig()
    }

    // MARK: - Config Profile CRUD

    /// Create a new empty profile and switch to it.
    func createProfile(name: String, icon: String) {
        pushUndo()
        let profile = ConfigProfile(name: name, icon: icon)
        profiles.append(profile)
        // Save current manipulators + menu bar items into the old profile first
        saveConfig()
        // Switch to the new profile with fresh defaults
        activeProfileID = profile.id
        manipulators = []
        menuBarItems = MenuBarItem.defaults()
        selectedManipulatorID = nil
        saveProfilesManifest()
        saveConfig()
        mirrorToConfigJSON()
        applyRemaps()
        NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
    }

    /// Switch to a different profile, saving the current state first.
    func switchProfile(to id: UUID) {
        guard id != activeProfileID, profiles.contains(where: { $0.id == id }) else { return }
        pushUndo()
        // Save current data into the outgoing profile
        saveConfig()
        // Load the incoming profile's data
        activeProfileID = id
        saveProfilesManifest()
        if let loaded = Self.loadProfileData(id: id) {
            manipulators = loaded.manipulators
            menuBarItems = loaded.menuBarItems
        } else {
            // Profile file doesn't exist yet
            manipulators = []
            menuBarItems = MenuBarItem.defaults()
        }
        selectedManipulatorID = manipulators.first?.id
        mirrorToConfigJSON()
        applyRemaps()
        NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
    }

    /// Rename a profile.
    func renameProfile(_ id: UUID, name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name
        saveProfilesManifest()
    }

    /// Change a profile's icon.
    func updateProfileIcon(_ id: UUID, icon: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].icon = icon
        saveProfilesManifest()
    }

    func updateProfileColor(_ id: UUID, colorName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].colorName = colorName
        saveProfilesManifest()
    }

    /// Duplicate a profile and optionally give it a new name.
    func duplicateProfile(_ id: UUID, newName: String? = nil) {
        guard let sourceProfile = profiles.first(where: { $0.id == id }),
              let sourceData = Self.loadProfileData(id: id) else { return }
        let newProfile = ConfigProfile(
            name: newName ?? "\(sourceProfile.name) Copy",
            icon: sourceProfile.icon
        )
        profiles.append(newProfile)
        // Save the duplicated data into the new profile's file
        Self.ensureAppSupportDirectory()
        try? FileManager.default.createDirectory(at: Self.profilesDirectoryURL, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(sourceData) {
            try? encoded.write(to: Self.profileConfigURL(for: newProfile.id))
        }
        saveProfilesManifest()
    }

    /// Delete a profile. If it's the active profile, switch to another profile first.
    /// The default profile cannot be deleted.
    func deleteProfile(_ id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        guard profile.name != "Default" || profiles.count > 1 else {
            throw ProfileError.cannotDeleteDefault
        }

        let wasActive = id == activeProfileID

        pushUndo()

        profiles.removeAll { $0.id == id }

        // Remove the profile's data file
        let fileURL = Self.profileConfigURL(for: id)
        try? FileManager.default.removeItem(at: fileURL)

        if wasActive {
            // Switch to the first remaining profile
            if let first = profiles.first {
                activeProfileID = first.id
                saveProfilesManifest()
                if let loaded = Self.loadProfileData(id: first.id) {
                    manipulators = loaded.manipulators
                    menuBarItems = loaded.menuBarItems
                } else {
                    manipulators = []
                    menuBarItems = MenuBarItem.defaults()
                }
                selectedManipulatorID = manipulators.first?.id
                applyRemaps()
                NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
            }
        } else {
            saveProfilesManifest()
        }
    }

    /// Allowed profile icon names for the picker.
    static let profileIcons: [String] = ConfigProfile.availableIcons

    // MARK: - Config Profiles Persistence

    private static func ensureAppSupportDirectory() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
    }

    /// Load the profiles manifest from disk, or create a default manifest if none exists.
    /// Returns (profiles, activeProfileID).
    static func loadOrCreateProfilesManifest() -> ([ConfigProfile], UUID) {
        ensureAppSupportDirectory()
        guard let data = try? Data(contentsOf: profilesManifestURL),
              let manifest = try? JSONDecoder().decode(ProfilesManifest.self, from: data),
              !manifest.profiles.isEmpty else {
            // Ensure the profiles directory exists
            try? FileManager.default.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
            // Create a default profile
            let defaultProfile = ConfigProfile.default()
            let manifest = ProfilesManifest(profiles: [defaultProfile], activeProfileID: defaultProfile.id)
            if let encoded = try? JSONEncoder().encode(manifest) {
                try? encoded.write(to: profilesManifestURL)
            }
            return ([defaultProfile], defaultProfile.id)
        }
        return (manifest.profiles, manifest.activeProfileID)
    }

    /// Save the current profiles manifest to disk.
    func saveProfilesManifest() {
        let manifest = ProfilesManifest(profiles: profiles, activeProfileID: activeProfileID)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: Self.profilesManifestURL)
    }

    /// Load a specific profile's data (manipulators + menu bar items) from disk.
    /// Backward‑compatible: if the file is an old‑format `[Manipulator]` array, it converts to `ProfileData`.
    static func loadProfileData(id: UUID) -> ProfileData? {
        let url = profileConfigURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Try new format first (ProfileData)
        if let profileData = try? JSONDecoder().decode(ProfileData.self, from: data) {
            return profileData
        }
        // Fall back to old format [Manipulator]
        if let manipulators = try? JSONDecoder().decode([Manipulator].self, from: data) {
            return ProfileData(manipulators: manipulators, menuBarItems: MenuBarItem.defaults())
        }
        return nil
    }

    // MARK: - Config persistence

    /// Save manipulators and menu bar items to the active profile's dedicated file.
    /// config.json mirror is written lazily — only on profile switch or app launch
    /// — to avoid double-I/O on every change.
    func saveConfig() {
        let profileData = ProfileData(manipulators: manipulators, menuBarItems: menuBarItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(profileData) else { return }

        // Save to active profile file only
        Self.ensureAppSupportDirectory()
        try? FileManager.default.createDirectory(at: Self.profilesDirectoryURL, withIntermediateDirectories: true)
        let profileURL = Self.profileConfigURL(for: activeProfileID)
        try? data.write(to: profileURL)
    }

    /// Mirror the active profile's config to config.json for backward compatibility.
    /// This is called only on profile switch and on app launch, not on every mutation.
    private func mirrorToConfigJSON() {
        guard let data = try? JSONEncoder().encode(manipulators) else { return }
        try? data.write(to: Self.configURL)
    }

    private func scheduleSaveConfig() {
        saveConfigTask?.cancel()
        let profileData = ProfileData(manipulators: manipulators, menuBarItems: menuBarItems)
        let profileURL = Self.profileConfigURL(for: activeProfileID)
        let appSupportURL = Self.appSupportURL
        let profilesDirectoryURL = Self.profilesDirectoryURL
        saveConfigTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(profileData) else { return }
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
            try? data.write(to: profileURL)
        }
    }

    /// Debounced apply for routing rebuilds. Batches rapid mutations (e.g. keystrokes)
    /// so the expensive engine rebuild only runs once after edits settle.
    private func scheduleApplyRemaps() {
        applyRemapsTask?.cancel()
        applyRemapsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
            guard let self, !Task.isCancelled else { return }
            self.applyRemaps()
        }
    }

    /// Debounced save for menu bar items. Avoids disk I/O on every keystroke.
    private func scheduleSaveMenuBarItems() {
        saveMenuBarItemsTask?.cancel()
        saveMenuBarItemsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard let self, !Task.isCancelled else { return }
            // Save menu bar items into the active profile
            self.saveConfig()
            NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
        }
    }

    static func loadConfig() -> [Manipulator]? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode([Manipulator].self, from: data)
    }

    static func loadGlobalVariables() -> [String: String]? {
        guard let data = try? Data(contentsOf: globalVarsURL) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func saveGlobalVariables(_ vars: [String: String]) {
        guard let data = try? JSONEncoder().encode(vars) else { return }
        try? data.write(to: globalVarsURL)
    }

    // MARK: - Menu Bar Items Persistence

    func saveMenuBarItems() {
        scheduleSaveMenuBarItems()
    }

    /// Immediately persist menu bar items to the active profile file.
    private func saveMenuBarItemsImmediate() {
        saveConfig()
        NotificationCenter.default.post(name: .menuBarItemsDidChange, object: nil)
    }

    /// Watch the active profile config file for external changes using kqueue,
    /// eliminating the need for polling. Fires only when the file is actually written.
    func startConfigPolling() {
        stopConfigPolling()
        let url = Self.profileConfigURL(for: activeProfileID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        var lastMod: Date?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mod = attrs[.modificationDate] as? Date {
            lastMod = mod
        }

        source.setEventHandler { [weak self] in
            // Re-check the file actually changed (not just a touch)
            guard let strongSelf = self else { return }

            // If file was deleted or renamed, stop watching
            guard FileManager.default.fileExists(atPath: url.path) else {
                Task { @MainActor in strongSelf.stopConfigPolling() }
                return
            }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let mod = attrs[.modificationDate] as? Date,
                  mod != lastMod else {
                return
            }
            lastMod = mod

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let loaded = Self.loadProfileData(id: self.activeProfileID) {
                    self.manipulators = loaded.manipulators
                    self.menuBarItems = loaded.menuBarItems
                    self.objectWillChange.send()
                    self.applyRemaps()
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        configFileSource = source
    }

    private func stopConfigPolling() {
        configFileSource?.cancel()
        configFileSource = nil
    }

    func writeDaemonStatus() {
        let info: [String: Any] = [
            "running": true,
            "active": remapIsActive,
            "message": remapStatusText,
            "permissionGranted": !remapNeedsPermission,
            "manipulatorCount": manipulators.count,
            "timestamp": Date().timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) else { return }
        try? data.write(to: Self.statusURL)
    }

    // MARK: - Engine apply

    func applyRemaps() {
        rebuildTagFolderCache()
        engine.apply(manipulators)
        if !daemonMode {
            scheduleSaveConfig()
        }
    }

    private func updateRemapState(_ state: KeyboardRemapEngineState) {
        let hasAny = manipulators.contains(where: { $0.isEnabled && $0.trigger.isValid })
        switch state {
        case .inactive:
            remapStatusText = hasAny ? "Remap engine stopped" : "No active manipulators"
            remapNeedsPermission = false
            remapIsActive = hasAny
        case .active(let count):
            remapStatusText = "Engine active (\(count) manipulator\(count == 1 ? "" : "s"))"
            remapNeedsPermission = false
            remapIsActive = true
        case .needsAccessibilityPermission:
            remapStatusText = "Allow Accessibility access"
            remapNeedsPermission = true
            remapIsActive = false
        case .failed(let message):
            remapStatusText = message
            remapNeedsPermission = false
            remapIsActive = false
        }
        writeDaemonStatus()
    }

    func requestRemapPermissions() {
        engine.requestAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Capture

    func startTriggerRecording(for manipulatorID: UUID) {
        stopAllCapture()
        isRecordingTrigger = true
        recordedTriggerSteps = []
        triggerRecordingManipulatorID = manipulatorID
        triggerRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let shortcut = self.recordedShortcut(from: event) else { return event }
            self.recordedTriggerSteps.append(shortcut)
            return nil
        }
    }

    func stopTriggerRecording(save: Bool) {
        guard isRecordingTrigger else { return }
        isRecordingTrigger = false
        if let triggerRecordingMonitor {
            NSEvent.removeMonitor(triggerRecordingMonitor)
            self.triggerRecordingMonitor = nil
        }
        if save,
           !recordedTriggerSteps.isEmpty {
            pushUndo()
            let steps = recordedTriggerSteps
            if let additionalTriggerID = triggerRecordingAdditionalTriggerID,
               let manipulatorID = triggerRecordingManipulatorID {
                updateAdditionalTrigger(additionalTriggerID, in: manipulatorID) { additional in
                    additional.trigger.steps = steps
                }
            } else if let manipulatorID = triggerRecordingManipulatorID {
                updateManipulator(manipulatorID) { $0.trigger.steps = steps }
            }
        }
        triggerRecordingManipulatorID = nil
        triggerRecordingAdditionalTriggerID = nil
        recordedTriggerSteps = []
    }

    func removeRecordedTriggerStep(at index: Int) {
        guard recordedTriggerSteps.indices.contains(index) else { return }
        recordedTriggerSteps.remove(at: index)
    }

    func removeTriggerStep(at index: Int, from manipulatorID: UUID) {
        pushUndo()
        updateManipulator(manipulatorID) { manipulator in
            guard manipulator.trigger.steps.indices.contains(index) else { return }
            manipulator.trigger.steps.remove(at: index)
        }
    }

    func startSendKeyCapture(for actionID: UUID) {
        stopAllCapture()
        guard let manipulatorID = selectedManipulatorID else { return }
        isCapturingToKey = true
        toKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let keyID = self.keyID(from: event)
            let modifiers = self.modifiers(from: event.modifierFlags)
            self.updateAction(actionID, in: manipulatorID) { action in
                action.toKey = keyID
                action.toModifiers = modifiers
            }
            self.stopToKeyCapture()
            return nil
        }
    }

    func stopToKeyCapture() {
        isCapturingToKey = false
        if let toKeyMonitor { NSEvent.removeMonitor(toKeyMonitor); self.toKeyMonitor = nil }
    }

    func stopAllCapture() {
        stopTriggerRecording(save: isRecordingTrigger && !recordedTriggerSteps.isEmpty)
        stopToKeyCapture()
    }

    // MARK: - Import / Export (Manipulators)

    /// Export a manipulator by ID using the save panel.
    @MainActor
    func exportManipulator(_ id: UUID) {
        guard let manipulator = manipulators.first(where: { $0.id == id }) else { return }
        if ManipulatorFile.export(manipulator) {
            showToast("Exported \"\(manipulator.name)\"")
        }
    }

    /// Show an open panel and import a manipulator from a file.
    @MainActor
    func importManipulatorFromPanel() {
        guard let imported = ManipulatorFile.importSingle() else { return }
        addImportedManipulator(imported)
        showToast("Imported \"\(imported.name)\"")
    }

    /// Import a manipulator from a dropped file URL.
    @MainActor
    func importManipulator(from url: URL) {
        guard let imported = try? ManipulatorFile.read(from: url) else {
            showToast("Failed to import file")
            return
        }
        addImportedManipulator(imported)
        showToast("Imported \"\(imported.name)\"")
    }

    // MARK: - Import / Export (Menu Bar Items)

    @MainActor
    func exportMenuBarItem(_ id: UUID) {
        guard let item = menuBarItems.first(where: { $0.id == id }) else { return }
        if MenuBarItemFile.export(item) {
            showToast("Exported \"\(item.name)\"")
        }
    }

    @MainActor
    func importMenuBarItemFromPanel() {
        guard let imported = MenuBarItemFile.importSingle() else { return }
        menuBarItems.append(imported)
        selectedMenuBarItemID = imported.id
        saveMenuBarItemsImmediate()
        showToast("Imported \"\(imported.name)\"")
    }

    @MainActor
    func importMenuBarItem(from url: URL) {
        guard let imported = try? MenuBarItemFile.read(from: url) else {
            showToast("Failed to import file")
            return
        }
        menuBarItems.append(imported)
        selectedMenuBarItemID = imported.id
        saveMenuBarItemsImmediate()
        showToast("Imported \"\(imported.name)\"")
    }

    // MARK: - Toast

    /// Show a brief success message that auto-dismisses.
    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    /// Insert an imported (decoded) manipulator into the store, assigning a fresh ID.
    private func addImportedManipulator(_ manip: Manipulator) {
        pushUndo()
        var imported = manip
        imported.id = UUID()
        // Append " (imported)" only if a local manipulator already has the same name.
        let nameExists = manipulators.contains(where: { $0.name == imported.name })
        if nameExists {
            imported.name = "\(imported.name) (imported)"
        }
        manipulators.append(imported)
        selectedManipulatorID = imported.id
        applyRemaps()
    }

    // MARK: - Action execution

    fileprivate func executeAction(_ action: Action, of manipulator: Manipulator, proxy: CGEventTapProxy?) {
        // CRITICAL: Some action kinds involve synchronous blocking (shell, AppleScript,
        // file I/O). Dispatch those to a background queue so the event-tap callback
        // (which runs on the main run loop) is never blocked.
        let blockingKinds: Set<ActionKind> = [
            .runShell, .runAppleScript, .runShortcut, .openApp, .openURL, .selectInputSource,
            .toggleDarkMode, .setVolume, .muteSystem, .emptyTrash, .lockScreen,
            .showDesktop, .missionControl, .getBatteryState, .getIPAddress,
            .toggleHiddenFiles, .logOut, .restartSystem, .shutdownSystem
        ]
        if blockingKinds.contains(action.kind) {
            // Dispatch blocking actions to a background queue so the event-tap
            // callback (which runs on the main run loop) is never stalled.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                // Perform the blocking work (shell, AppleScript, etc.) on background
                self.executeBlockingAction(action, of: manipulator, proxy: nil)
            }
            return
        }
        self.executeActionImpl(action, of: manipulator, proxy: proxy)
    }

    /// Execute blocking action kinds on a background thread.
    /// Only the blocking I/O is performed here; UI-touching operations
    /// are dispatched back to the main actor.
    private func executeBlockingAction(_ action: Action, of manipulator: Manipulator, proxy: CGEventTapProxy?) {
        switch action.kind {
        case .runShell:
            if !action.shellCommand.isEmpty {
                _ = runShell(action.shellCommand)
            }
        case .runAppleScript:
            if !action.scriptBody.isEmpty {
                _ = Self.runAppleScript(action.scriptBody)
            }
        case .sendUserCommand:
            if !action.userCommand.isEmpty {
                _ = runShell(action.userCommand)
            }
        case .runShortcut:
            if !action.shortcutName.isEmpty {
                _ = ShortcutsService.runShortcut(named: action.shortcutName)
            }
        case .openApp:
            openApp(bundleID: action.appBundleID, name: action.appName)
        case .openURL:
            if let url = URL(string: action.urlString) {
                NSWorkspace.shared.open(url)
            }
        case .getBatteryState:
            let output = runShell("pmset -g batt")
            if let match = output.range(of: #"\d+%"#, options: .regularExpression) {
                engine.setVariable(name: "batteryLevel", value: String(output[match].dropLast()))
            }
            engine.setVariable(name: "batteryCharging", value: output.contains("AC Power") ? "true" : "false")
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        case .getIPAddress:
            let ip = runShell("ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1").trimmingCharacters(in: .whitespacesAndNewlines)
            engine.setVariable(name: "ipAddress", value: ip)
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        default:
            // For other blocking kinds, fall back to main-thread execution
            Task { @MainActor [weak self] in
                self?.executeActionImpl(action, of: manipulator, proxy: proxy)
            }
        }
    }

    fileprivate func executeActionImpl(_ action: Action, of manipulator: Manipulator, proxy: CGEventTapProxy?) {
        switch action.kind {
        case .sendKey:
            if !action.toKey.isEmpty {
                if action.isLazy, !action.toModifiers.isEmpty {
                    engine.setLazyModifiers(action.toModifiers)
                    objectWillChange.send()
                } else {
                    postKeyCombo(modifiers: action.toModifiers, keyID: action.toKey, proxy: proxy)
                }
            }
        case .sendText:
            if !action.text.isEmpty {
                postText(expandVariableTokens(in: action.text), proxy: proxy)
            }
        case .consumerKey:
            if let consumerKey = action.consumerKey {
                postConsumerKey(consumerKey, proxy: proxy)
            }
        case .pointingButton:
            if let button = action.pointingButton {
                postPointingButton(button, proxy: proxy)
            }
        case .mouseKey:
            postMouseKey(action.mouseKey, proxy: proxy)
        case .stickyModifier:
            engine.setStickyModifier(action.stickyModifier.modifier, active: action.stickyModifier.kind == .toggle
                ? !(engine.variables["sticky_\(action.stickyModifier.modifier.rawValue)"] == "true")
                : action.stickyModifier.kind == .on)
            engine.setVariable(name: "sticky_\(action.stickyModifier.modifier.rawValue)",
                               value: action.stickyModifier.kind == .toggle
                               ? (engine.variables["sticky_\(action.stickyModifier.modifier.rawValue)"] == "true" ? "false" : "true")
                               : (action.stickyModifier.kind == .on ? "true" : "false"))
            objectWillChange.send()
        case .halt:
            break
        case .holdDown:
            if !action.toKey.isEmpty && action.holdDownMilliseconds > 0 {
                postKeyCombo(modifiers: action.toModifiers, keyID: action.toKey, proxy: proxy)
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(action.holdDownMilliseconds) * 1_000_000)
                    postKeyUp(keyID: action.toKey, proxy: proxy)
                }
            }
        case .selectInputSource:
            if !action.inputSourceID.isEmpty {
                selectInputSource(action.inputSourceID)
            }
        case .setNotification:
            if !action.notificationMessage.isEmpty {
                showNotification(expandVariableTokens(in: action.notificationMessage))
            }
        case .fromEvent:
            if let keyID = manipulator.trigger.steps.first?.key, !keyID.isEmpty {
                postKeyCombo(modifiers: [], keyID: keyID, proxy: proxy)
            }
        case .softwareFunction:
            executeSoftwareFunction(action, proxy: proxy)
        case .setVariable:
            if !action.variableName.isEmpty {
                engine.setVariable(name: action.variableName, value: action.variableValue)
                objectWillChange.send()
            }
        case .unsetVariable:
            if !action.variableName.isEmpty {
                engine.unsetVariable(name: action.variableName)
                objectWillChange.send()
            }
        case .toggleVariable:
            if !action.variableName.isEmpty {
                let current = engine.variables[action.variableName] ?? (action.toggleInitialState ? "true" : "false")
                let newValue = current == "true" ? "false" : "true"
                engine.setVariable(name: action.variableName, value: newValue)
                objectWillChange.send()
            }
        case .setGlobalVariable:
            if !action.variableName.isEmpty {
                engine.setGlobalVariable(name: action.variableName, value: action.variableValue)
                objectWillChange.send()
            }
        case .unsetGlobalVariable:
            if !action.variableName.isEmpty {
                engine.unsetGlobalVariable(name: action.variableName)
                objectWillChange.send()
            }
        case .runShell:
            if !action.shellCommand.isEmpty {
                _ = runShell(action.shellCommand)
            }
        case .openApp:
            openApp(bundleID: action.appBundleID, name: action.appName)
        case .openURL:
            if let url = URL(string: action.urlString) {
                NSWorkspace.shared.open(url)
            }
        case .runShortcut:
            if !action.shortcutName.isEmpty {
                Task { _ = ShortcutsService.runShortcut(named: action.shortcutName) }
            }
        case .runAppleScript:
            if !action.scriptBody.isEmpty {
                _ = Self.runAppleScript(action.scriptBody)
            }
        case .sendUserCommand:
            if !action.userCommand.isEmpty {
                _ = runShell(action.userCommand)
            }
        case .executeNamedTrigger:
            if !action.namedTrigger.isEmpty {
                engine.triggerNamedTrigger(name: action.namedTrigger, proxy: proxy)
            }
        case .delay:
            let seconds = action.delaySeconds
            Task {
                try? await Task.sleep(for: .seconds(seconds))
            }
        case .disable:
            break
        case .showPalette:
            showMacroPalette()
        case .hidePalette:
            hideMacroPalette()
        case .getSelectedText:
            if let text = getSelectedTextFromFrontmostApp(), !text.isEmpty {
                engine.setVariable(name: "selectedText", value: text)
                clipboardText = text
                objectWillChange.send()
            }
        case .setClipboard:
            if !action.text.isEmpty {
                clipboardText = action.text
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(action.text, forType: .string)
                objectWillChange.send()
            }
        case .getClipboard:
            if let text = NSPasteboard.general.string(forType: .string) {
                clipboardText = text
                engine.setVariable(name: "clipboardText", value: text)
                objectWillChange.send()
            }
        case .clearClipboard:
            clipboardText = ""
            NSPasteboard.general.clearContents()
            objectWillChange.send()
        case .activateApp:
            if let app = runningApp(bundleID: action.appBundleID, name: action.appName) {
                app.unhide()
                app.activate(options: [.activateAllWindows])
            } else {
                openApp(bundleID: action.appBundleID, name: action.appName)
            }
        case .hideApp:
            runningApp(bundleID: action.appBundleID, name: action.appName)?.hide()
        case .unhideApp:
            runningApp(bundleID: action.appBundleID, name: action.appName)?.unhide()
        case .quitApp:
            runningApp(bundleID: action.appBundleID, name: action.appName)?.terminate()
        case .forceQuitApp:
            runningApp(bundleID: action.appBundleID, name: action.appName)?.forceTerminate()
        case .activateLastApp:
            if let bundleID = previousFrontmostBundleID,
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                app.unhide()
                app.activate(options: [.activateAllWindows])
            }
        case .windowAction:
            performWindowAction(action.windowActionKind ?? .leftHalf)
        case .lockScreen:
            _ = runShell("\"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession\" -suspend")
        case .showDesktop:
            _ = runShell("open -b com.apple.exposelauncher --args 1")
        case .missionControl:
            _ = runShell("open -b com.apple.exposelauncher")
        case .toggleDarkMode:
            _ = Self.runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .setVolume:
            let level = max(0, min(100, action.numberValue ?? 50))
            _ = Self.runAppleScript("set volume output volume \(level)")
        case .muteSystem:
            _ = Self.runAppleScript("set volume output muted not (output muted of (get volume settings))")
        case .emptyTrash:
            _ = Self.runAppleScript("tell application \"Finder\" to empty trash")
        case .getBatteryState:
            let output = runShell("pmset -g batt")
            if let match = output.range(of: #"\d+%"#, options: .regularExpression) {
                engine.setVariable(name: "batteryLevel", value: String(output[match].dropLast()))
            }
            engine.setVariable(name: "batteryCharging", value: output.contains("AC Power") ? "true" : "false")
            objectWillChange.send()
        case .getIPAddress:
            let ip = runShell("ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1").trimmingCharacters(in: .whitespacesAndNewlines)
            engine.setVariable(name: "ipAddress", value: ip)
            objectWillChange.send()
        case .toggleHiddenFiles:
            let current = runShell("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = (current == "1" || current.lowercased() == "true") ? "FALSE" : "TRUE"
            _ = runShell("defaults write com.apple.finder AppleShowAllFiles \(newValue); killall Finder")
        case .logOut:
            _ = Self.runAppleScript("tell application \"System Events\" to log out")
        case .restartSystem:
            _ = Self.runAppleScript("tell application \"System Events\" to restart")
        case .shutdownSystem:
            _ = Self.runAppleScript("tell application \"System Events\" to shut down")
        case .speakText:
            if !action.text.isEmpty {
                speechSynthesizer.speak(AVSpeechUtterance(string: action.text))
            }
        case .transformText:
            let kind = action.textTransformKind ?? .upperCase
            let input = NSPasteboard.general.string(forType: .string) ?? ""
            guard !input.isEmpty else { break }
            let output = Self.transformText(input, kind: kind)
            clipboardText = output
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
            objectWillChange.send()
        case .calculateExpression:
            if !action.variableName.isEmpty, !action.variableValue.isEmpty {
                let expression = NSExpression(format: action.variableValue)
                if let result = expression.expressionValue(with: nil, context: nil) as? NSNumber {
                    engine.setVariable(name: action.variableName, value: result.stringValue)
                    objectWillChange.send()
                }
            }
        case .incrementVariable, .decrementVariable:
            if !action.variableName.isEmpty {
                let step = Double(action.variableValue) ?? 1
                let current = Double(engine.variables[action.variableName] ?? "0") ?? 0
                let newValue = action.kind == .incrementVariable ? current + step : current - step
                let formatted = newValue == newValue.rounded() ? String(Int(newValue)) : String(newValue)
                engine.setVariable(name: action.variableName, value: formatted)
                objectWillChange.send()
            }
        case .appendClipboard:
            if !action.text.isEmpty {
                let current = NSPasteboard.general.string(forType: .string) ?? ""
                let combined = current + action.text
                clipboardText = combined
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(combined, forType: .string)
                objectWillChange.send()
            }
        case .pasteClipboard:
            postKeyCombo(modifiers: [.command], keyID: "v", proxy: proxy)
        case .httpRequest:
            if let url = URL(string: action.urlString) {
                let variableName = action.variableName.isEmpty ? "httpResponse" : action.variableName
                Task { [weak self] in
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                    let body = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self?.engine.setVariable(name: variableName, value: body)
                        self?.objectWillChange.send()
                    }
                }
            }
        case .openFile:
            if !action.appPath.isEmpty {
                let expanded = (action.appPath as NSString).expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            }
        case .openFolder:
            if !action.appPath.isEmpty {
                let expanded = (action.appPath as NSString).expandingTildeInPath
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
            }
        case .playSound:
            if !action.text.isEmpty {
                if let sound = NSSound(named: action.text) {
                    sound.play()
                } else {
                    let expanded = (action.text as NSString).expandingTildeInPath
                    NSSound(contentsOfFile: expanded, byReference: true)?.play()
                }
            }
        case .flashScreen:
            flashScreen()
        }
    }

    // MARK: - Accessibility helpers

    /// Gets the selected text from the frontmost application using the Accessibility API.
    private func getSelectedTextFromFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }
        
        // Get the selected text range
        var selectedRange: CFTypeRef?
        guard let element = focusedElement else { return nil }
        let axElement: AXUIElement = unsafeBitCast(element, to: AXUIElement.self)
        let rangeResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        guard rangeResult == .success, let rangeValue = selectedRange else { return nil }
        
        // Extract the selected range
        var startIndex: CFIndex = 0
        let axRangeValue: AXValue = unsafeBitCast(rangeValue, to: AXValue.self)
        AXValueGetValue(axRangeValue, .cfRange, &startIndex)
        
        // For now, use the clipboard approach as fallback
        // Copy selection to pasteboard, read it, then restore
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Simulate Command+C to copy the selection
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) { // 'c' key
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) {
            keyUp.post(tap: .cgSessionEventTap)
        }
        
        // Small delay to allow clipboard to update
        usleep(50000) // 50ms
        
        // Read the clipboard
        let copiedText = pasteboard.string(forType: .string)
        
        // Restore original clipboard content if it changed
        if pasteboard.changeCount != originalChangeCount {
            if let original = originalContent {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }
        
        return copiedText
    }

    /// Find a running application by bundle ID or localized name.
    private func runningApp(bundleID: String, name: String) -> NSRunningApplication? {
        if !bundleID.isEmpty,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == bundleID.lowercased() }) {
            return app
        }
        if !name.isEmpty {
            return NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == name.lowercased() })
        }
        return nil
    }

    // MARK: - Window actions (Accessibility API)

    /// Apply a window action to the frontmost window of the frontmost app.
    /// AX coordinates are global with a top-left origin.
    private func performWindowAction(_ kind: WindowActionKind) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &windowRef) == .success
                || AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef) == .success,
              let windowValue = windowRef else { return }
        let window: AXUIElement = unsafeBitCast(windowValue, to: AXUIElement.self)

        switch kind {
        case .minimize:
            AXUIElementSetAttributeValue(window, "AXMinimized" as CFString, kCFBooleanTrue)
            return
        case .close:
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXCloseButton" as CFString, &button) == .success, let buttonVal = button {
                let closeButton: AXUIElement = unsafeBitCast(buttonVal, to: AXUIElement.self)
                AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
            }
            return
        default:
            break
        }

        // Compute the target frame from the screen's visible area.
        guard let screen = screenForFrontmostWindow(window) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Convert AppKit (bottom-left origin) visible frame to AX top-left origin coords.
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? visible.maxY
        let axTop = globalHeight - visible.maxY

        let w = visible.width, h = visible.height
        let x = visible.minX, yTop = axTop
        let frame: CGRect
        switch kind {
        case .leftHalf: frame = CGRect(x: x, y: yTop, width: w / 2, height: h)
        case .rightHalf: frame = CGRect(x: x + w / 2, y: yTop, width: w / 2, height: h)
        case .topHalf: frame = CGRect(x: x, y: yTop, width: w, height: h / 2)
        case .bottomHalf: frame = CGRect(x: x, y: yTop + h / 2, width: w, height: h / 2)
        case .topLeftQuarter: frame = CGRect(x: x, y: yTop, width: w / 2, height: h / 2)
        case .topRightQuarter: frame = CGRect(x: x + w / 2, y: yTop, width: w / 2, height: h / 2)
        case .bottomLeftQuarter: frame = CGRect(x: x, y: yTop + h / 2, width: w / 2, height: h / 2)
        case .bottomRightQuarter: frame = CGRect(x: x + w / 2, y: yTop + h / 2, width: w / 2, height: h / 2)
        case .center: frame = CGRect(x: x + w / 6, y: yTop + h / 6, width: w * 2 / 3, height: h * 2 / 3)
        case .maximize: frame = CGRect(x: x, y: yTop, width: w, height: h)
        case .minimize, .close: return
        }

        var position = frame.origin
        var size = frame.size
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Find the NSScreen containing the given AX window (by its current position).
    private func screenForFrontmostWindow(_ window: AXUIElement) -> NSScreen? {
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef else { return nil }
        var point = CGPoint.zero
        let axValue: AXValue = unsafeBitCast(positionValue, to: AXValue.self)
        AXValueGetValue(axValue, .cgPoint, &point)
        // Convert AX top-left origin point to AppKit bottom-left origin.
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitPoint = NSPoint(x: point.x, y: globalHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }

    // MARK: - Text transforms

    static func transformText(_ input: String, kind: TextTransformKind) -> String {
        switch kind {
        case .upperCase: return input.uppercased()
        case .lowerCase: return input.lowercased()
        case .capitalize: return input.capitalized
        case .camelCase:
            let words = splitWords(input)
            guard let first = words.first else { return input }
            return first.lowercased() + words.dropFirst().map(\.capitalized).joined()
        case .pascalCase:
            return splitWords(input).map(\.capitalized).joined()
        case .snakeCase:
            return splitWords(input).map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            return splitWords(input).map { $0.lowercased() }.joined(separator: "-")
        case .trimWhitespace:
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .slugify:
            let lowered = splitWords(input).map { $0.lowercased() }.joined(separator: "-")
            return lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
                .reduce(into: "") { $0.append(Character($1)) }
        case .encodeBase64:
            return Data(input.utf8).base64EncodedString()
        case .decodeBase64:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return input }
            return decoded
        case .encodeURL:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        case .decodeURL:
            return input.removingPercentEncoding ?? input
        }
    }

    /// Split text into words on whitespace, punctuation, underscores, hyphens,
    /// and camelCase boundaries.
    private static func splitWords(_ input: String) -> [String] {
        var separated = ""
        var previous: Character?
        for char in input {
            if let previous, previous.isLowercase || previous.isNumber, char.isUppercase {
                separated.append(" ")
            }
            separated.append(char)
            previous = char
        }
        return separated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Screen flash

    /// Flash the screen with a brief translucent overlay, then fade it out.
    private func flashScreen() {
        guard let screen = NSScreen.main else { return }
        let flashWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        flashWindow.level = .screenSaver
        flashWindow.backgroundColor = .white
        flashWindow.alphaValue = 0.7
        flashWindow.ignoresMouseEvents = true
        flashWindow.collectionBehavior = [.canJoinAllSpaces, .transient]
        flashWindow.orderFrontRegardless()

        // Retain the window for the duration of the animation.
        let retainedWindow: NSWindow? = flashWindow
        _ = retainedWindow
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            flashWindow.animator().alphaValue = 0
        }, completionHandler: {
            flashWindow.orderOut(nil)
        })
    }

    private func openApp(bundleID: String, name: String) {
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            return
        }
        if !name.isEmpty {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
                app.activate(options: [])
            } else {
                _ = Self.runAppleScript("tell application \"\(name.replacingOccurrences(of: "\"", with: "\\\""))\"\n    activate\nend tell")
            }
        }
    }

    // MARK: - Macro Palette

    func showMacroPalette() {
        guard !isPaletteShown || paletteWindow == nil else {
            paletteWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let view = MacroPaletteView(store: self)
        let hosting = NSHostingView(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Macro Palette"
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Observe close so we can reset state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(paletteWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )

        paletteWindow = window
        isPaletteShown = true
    }

    func hideMacroPalette() {
        paletteWindow?.close()
        paletteWindow = nil
        isPaletteShown = false
    }

    func toggleMacroPalette() {
        if isPaletteShown {
            hideMacroPalette()
        } else {
            showMacroPalette()
        }
    }

    @objc private func paletteWindowWillClose(_ notification: Notification) {
        paletteWindow = nil
        isPaletteShown = false
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)
    }

    /// Execute all onKeyDown actions of a manipulator, used when a user clicks a
    /// manipulator in the floating macro palette.
    func executeManipulatorFromPalette(_ manipulator: Manipulator) {
        guard manipulator.isEnabled else { return }
        // Check manipulator-level conditions first
        guard manipulator.conditions.allSatisfy({ engine.evaluateCondition($0) }) else { return }
        for action in manipulator.actions where action.fireMode == .onKeyDown {
            guard action.isConfigured else { continue }
            guard action.actionConditions.allSatisfy({ engine.evaluateCondition($0) }) else { continue }
            executeActionImpl(action, of: manipulator, proxy: nil)
            if action.kind == .halt { break }
        }
    }

    // MARK: - Posting events

    /// Cached regex for variable token expansion: {variable_name}
    private static let variableTokenRegex = try! NSRegularExpression(pattern: "\\{([^}]+)\\}", options: [])

    /// Expand {variable_name} tokens in text using a regex-based approach
    /// that avoids O(n²) character-by-character scanning for long strings.
    func expandVariableTokens(in text: String) -> String {
        guard text.contains("{") else { return text }
        let regex = Self.variableTokenRegex
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        var offset = 0

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let varRange = Range(match.range(at: 1), in: text) else { return }
            let name = String(text[varRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let value = engine.variables[name] ?? engine.globalVariables[name] else { return }

            let fullRange = Range(match.range(at: 0), in: text)!
            let adjustedStart = result.index(result.startIndex, offsetBy: offset + text.distance(from: text.startIndex, to: fullRange.lowerBound))
            let adjustedEnd = result.index(result.startIndex, offsetBy: offset + text.distance(from: text.startIndex, to: fullRange.upperBound))
            result.replaceSubrange(adjustedStart..<adjustedEnd, with: value)
            offset += value.count - (text.distance(from: fullRange.lowerBound, to: fullRange.upperBound))
        }
        return result
    }

    func postKeyCombo(modifiers: Set<ModifierKey>, keyID: String, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flagBased = modifiers.compactMap { $0.cgFlag }
        let combined = flagBased.reduce(into: CGEventFlags()) { $0.insert($1) }
        let orderedMods: [ModifierKey] = [.control, .option, .shift, .command, .capsLock, .fn]
        let sortedMods = orderedMods.filter { modifiers.contains($0) }

        for mod in sortedMods {
            for keyID in KeyboardKeyCodeMap.modifierKeyIDs(for: mod) {
                guard let keyCode = KeyboardKeyCodeMap.code(for: keyID) else { continue }
                if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                    event.flags = combined
                    postEvent(event, proxy: proxy)
                }
                break
            }
        }
        if let keyCode = KeyboardKeyCodeMap.code(for: keyID) {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                down.flags = combined
                postEvent(down, proxy: proxy)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                up.flags = combined
                postEvent(up, proxy: proxy)
            }
        }
        for mod in sortedMods.reversed() {
            for keyID in KeyboardKeyCodeMap.modifierKeyIDs(for: mod) {
                guard let keyCode = KeyboardKeyCodeMap.code(for: keyID) else { continue }
                if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                    event.flags = combined.subtracting(mod.cgFlag ?? CGEventFlags())
                    postEvent(event, proxy: proxy)
                }
                break
            }
        }
    }

    /// Post a string as keyboard input by synthesizing Unicode key events.
    /// CGEvent's `keyboardSetUnicodeString` has a documented limit of 64 UTF-16 code
    /// units per call. For longer strings, we chunk into segments of 64 code units
    /// and post each as a separate key-down/key-up pair.
    fileprivate func postText(_ text: String, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        let chunkSize = 64
        var offset = 0

        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            let chunk = Array(utf16[offset..<end])
            offset = end

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.flags = []
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                postEvent(down, proxy: proxy)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.flags = []
                postEvent(up, proxy: proxy)
            }
        }
    }

    /// Events we post ourselves are tagged so the event-tap callback can filter them out,
    /// preventing feedback loops that could cause OS freezes.
    private func postEvent(_ event: CGEvent, proxy: CGEventTapProxy?) {
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    fileprivate func postKeyUp(keyID: String, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyCode = KeyboardKeyCodeMap.code(for: keyID) else { return }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = []
            postEvent(up, proxy: proxy)
        }
    }

    fileprivate func postConsumerKey(_ consumerKey: ConsumerKeyCode, proxy: CGEventTapProxy? = nil) {
        let nxKeyType = consumerKey.nxKeyType
        postConsumerKeyEvent(nxKeyType: nxKeyType, isDown: true, proxy: proxy)
        postConsumerKeyEvent(nxKeyType: nxKeyType, isDown: false, proxy: proxy)
    }

    private func postConsumerKeyEvent(nxKeyType: Int32, isDown: Bool, proxy: CGEventTapProxy?) {
        let keyState = isDown ? 0x0A00 : 0x0B00
        let data1 = (Int(nxKeyType) << 16) | keyState
        guard let nsEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let event = nsEvent.cgEvent else { return }
        postEvent(event, proxy: proxy)
    }

    fileprivate func postPointingButton(_ button: PointingButton, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let cgButton = button.cgButton
        let eventType: CGEventType = cgButton == .left ? .leftMouseDown : cgButton == .right ? .rightMouseDown : .otherMouseDown
        let upType: CGEventType = cgButton == .left ? .leftMouseUp : cgButton == .right ? .rightMouseUp : .otherMouseUp

        let location = CGEvent(source: source)?.location ?? NSEvent.mouseLocation
        let downEvent = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: location, mouseButton: cgButton)
        let upEvent = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton)

        if let downEvent, button == .back || button == .forward {
            downEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button == .back ? 3 : 4))
        }
        if let upEvent, button == .back || button == .forward {
            upEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button == .back ? 3 : 4))
        }

        if let downEvent { postEvent(downEvent, proxy: proxy) }
        if let upEvent { postEvent(upEvent, proxy: proxy) }
    }

    fileprivate func postMouseKey(_ mouseKey: MouseKeyAction, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let speed = mouseKey.speedMultiplier

        if mouseKey.x != 0 || mouseKey.y != 0 {
            let currentPos = CGEvent(source: source)?.location ?? NSEvent.mouseLocation
            let newPos = CGPoint(
                x: currentPos.x + CGFloat(mouseKey.x) * speed,
                y: currentPos.y + CGFloat(mouseKey.y) * speed
            )
            CGWarpMouseCursorPosition(newPos)
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
                postEvent(moveEvent, proxy: proxy)
            }
        }

        if mouseKey.verticalWheel != 0 || mouseKey.horizontalWheel != 0 {
            if let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                          wheel1: Int32(mouseKey.verticalWheel), wheel2: Int32(mouseKey.horizontalWheel), wheel3: 0) {
                postEvent(scrollEvent, proxy: proxy)
            }
        }
    }

    fileprivate func selectInputSource(_ inputSourceID: String) {
        let script = """
        use framework "Carbon"
        use scripting additions
        
        set sourceID to "\(inputSourceID.replacingOccurrences(of: "\"", with: "\\\""))"
        try
            tell application "System Events" to tell process "SystemUIServer"
                set srcList to every menu bar item whose description is "text input"
            end tell
        end try
        """
        _ = Self.runAppleScript(script)
    }

    func showNotification(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Anvil"
            content.body = message
            content.sound = nil
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    fileprivate func executeSoftwareFunction(_ action: Action, proxy: CGEventTapProxy?) {
        switch action.softwareFunction {
        case .doubleClick:
            let source = CGEventSource(stateID: .hidSystemState)
            let location = CGEvent(source: source)?.location ?? NSEvent.mouseLocation
            for click in 1...2 {
                if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left) {
                    down.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                    postEvent(down, proxy: proxy)
                }
                if let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) {
                    up.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                    postEvent(up, proxy: proxy)
                }
            }
        case .sleepSystem:
            let task = Process()
            task.launchPath = "/usr/bin/pmset"
            task.arguments = ["sleepnow"]
            try? task.run()
        case .setCursorPosition:
            let source = CGEventSource(stateID: .hidSystemState)
            let location = CGPoint(x: CGFloat(action.cursorPositionX), y: CGFloat(action.cursorPositionY))
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) {
                postEvent(moveEvent, proxy: proxy)
            }
        case .openApplication:
            guard !action.appPath.isEmpty else { return }
            let path = action.appPath
            // Try as bundle identifier
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
                return
            }
            // Try as file system path
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return
            }
            // Try as display name via AppleScript
            _ = Self.runAppleScript("""
                tell application "\(path.replacingOccurrences(of: "\"", with: "\\\""))"
                    activate
                end tell
            """)
        }
    }

    fileprivate func runShell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]
        task.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return "" }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runAppleScript(_ source: String) -> String {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil_\\(UUID().uuidString).applescript")
        do {
            try source.write(to: tmp, atomically: true, encoding: .utf8)
        } catch { return "" }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [tmp.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return "" }
        task.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Helpers

    private func keyID(from event: NSEvent) -> String {
        if let keyID = KeyboardKeyCodeMap.id(for: CGKeyCode(event.keyCode)) {
            return keyID
        }
        if let character = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), !character.isEmpty {
            return character.lowercased()
        }
        switch event.keyCode {
        case 123: return "left_arrow"
        case 124: return "right_arrow"
        case 125: return "down_arrow"
        case 126: return "up_arrow"
        default: return "key_\(event.keyCode)"
        }
    }

    private func recordedShortcut(from event: NSEvent) -> KeyShortcut? {
        let keyID = keyID(from: event)
        var modifiers = modifiers(from: event.modifierFlags)
        if event.type == .flagsChanged {
            guard KeyboardKeyCodeMap.isModifierKeyID(keyID) else { return nil }
            guard event.modifierFlags.intersection([.command, .shift, .option, .control, .capsLock, .function]).isEmpty == false else { return nil }
            for modifier in ModifierKey.allCases where KeyboardKeyCodeMap.modifierKeyIDs(for: modifier).contains(keyID) {
                modifiers.remove(modifier)
            }
        }
        return KeyShortcut(mandatoryModifiers: modifiers, key: keyID)
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var modifiers: Set<ModifierKey> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if flags.contains(.function) { modifiers.insert(.fn) }
        return modifiers
    }
}

extension Manipulator {
    static func defaults() -> [Manipulator] {
        [
            // ================================================================
            // FEATURE: consumer_key_code trigger — media/consumer keys as triggers
            // ================================================================
            Manipulator(
                name: "[TEST] Consumer Key Trigger (Volume Down)",
                notes: "Tests: consumer_key_code as trigger.\nBehavior: Pressing Volume Down key shows a notification instead of changing volume. Demonstrates intercepting media keys.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "vk_consumer_volume_down")],
                    keyType: .consumer
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Consumer key trigger: Volume Down intercepted!"
                )]
            ),

            // ================================================================
            // FEATURE: pointing_button trigger — mouse buttons as triggers
            // ================================================================
            Manipulator(
                name: "[TEST] Pointing Button Trigger (Right Click)",
                notes: "Tests: pointing_button as trigger.\nBehavior: Right-clicking shows a notification. Demonstrates intercepting mouse buttons.\nWARNING: Disabled by default — very disruptive.",
                isEnabled: false,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "right")],
                    keyType: .pointing
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Pointing button trigger: Right click intercepted!"
                )]
            ),

            // ================================================================
            // FEATURE: any key trigger — wildcard key matching
            // ================================================================
            Manipulator(
                name: "[TEST] Any Key Trigger",
                notes: "Tests: any key wildcard trigger.\nBehavior: Pressing ANY keyboard key shows a notification. Demonstrates the 'any' trigger type.\nWARNING: Disabled by default — catches EVERY keystroke.",
                isEnabled: false,
                trigger: ManipulatorTrigger(
                    steps: [],
                    keyType: .any,
                    anyKey: true
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Any key trigger fired!"
                )]
            ),

            // ================================================================
            // FEATURE: mandatory modifiers with caps_lock
            // ================================================================
            Manipulator(
                name: "[TEST] Mandatory Modifier: Caps Lock",
                notes: "Tests: caps_lock as mandatory modifier.\nBehavior: When Caps Lock is ON, pressing 'k' sends uppercase 'K' (bypasses normal shift behavior). Demonstrates caps_lock modifier matching.\nTo test: Turn on Caps Lock, press k → should type K.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.capsLock], key: "k")]),
                actions: [Action(
                    kind: .sendKey,
                    toKey: "k",
                    toModifiers: [.shift]
                )]
            ),

            // ================================================================
            // FEATURE: fn modifier tracking
            // ================================================================
            Manipulator(
                name: "[TEST] Fn Modifier Trigger",
                notes: "Tests: fn as modifier.\nBehavior: Pressing fn+'j' sends 'fn_j'. Demonstrates fn key modifier tracking.\nTo test: Hold fn key and press j.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.fn], key: "j")]),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Fn modifier detected! fn+j pressed."
                )]
            ),

            // ================================================================
            // FEATURE: optional modifiers
            // ================================================================
            Manipulator(
                name: "[TEST] Optional Modifiers",
                notes: "Tests: optional modifiers.\nBehavior: Pressing cmd+shift+h OR cmd+shift+opt+h both trigger. Optional modifier 'option' can be present or absent.\nTo test: Try cmd+shift+h, then cmd+shift+opt+h → both should trigger.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.command, .shift], optionalModifiers: [.option], key: "h")]),
                actions: [Action(
                    kind: .sendText,
                    text: "Hello from optional modifiers!"
                )]
            ),

            // ================================================================
            // FEATURE: simultaneous chord trigger
            // ================================================================
            Manipulator(
                name: "[TEST] Simultaneous Chord Trigger",
                notes: "Tests: simultaneous (chord) trigger.\nBehavior: Pressing 'j' AND 'k' at the same time types 'chord!'. Pressing them sequentially does nothing.\nTo test: Press j+k together quickly.",
                isEnabled: false,
                trigger: ManipulatorTrigger(
                    simultaneous: SimultaneousTrigger(
                        keys: [
                            KeyShortcut(key: "j"),
                            KeyShortcut(key: "k")
                        ],
                        options: SimultaneousOptions(
                            keyDownOrder: .insensitive,
                            keyUpOrder: .insensitive,
                            keyUpWhen: .any
                        )
                    )
                ),
                actions: [Action(
                    kind: .sendText,
                    text: "chord!"
                )]
            ),

            // ================================================================
            // FEATURE: simultaneous chord WITH simultaneous_options
            // ================================================================
            Manipulator(
                name: "[TEST] Simultaneous Chord Strict Order",
                notes: "Tests: simultaneous_options.key_down_order strict.\nBehavior: Pressing 'u' then 'i' (u first) triggers. 'i' then 'u' (i first) does NOT trigger. Demonstrates strict key-down order.\nTo test: Press u then i together (u first).",
                isEnabled: false,
                trigger: ManipulatorTrigger(
                    simultaneous: SimultaneousTrigger(
                        keys: [
                            KeyShortcut(key: "u"),
                            KeyShortcut(key: "i")
                        ],
                        options: SimultaneousOptions(
                            keyDownOrder: .strict,
                            keyUpOrder: .insensitive,
                            keyUpWhen: .any
                        )
                    )
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Strict order chord: u+i (u first) triggered!"
                )]
            ),

            // ================================================================
            // FEATURE: consumerKey action — send media keys
            // ================================================================
            Manipulator(
                name: "[TEST] Consumer Key Action (Volume Up)",
                notes: "Tests: consumerKey action (To: consumer_key_code).\nBehavior: Pressing ctrl+opt+cmd+v increases system volume.\nTo test: Press ctrl+opt+cmd+v → volume goes up.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "v")]),
                actions: [Action(
                    kind: .consumerKey,
                    consumerKey: .volumeUp
                )]
            ),

            // ================================================================
            // FEATURE: pointingButton action — send mouse clicks
            // ================================================================
            Manipulator(
                name: "[TEST] Pointing Button Action (Left Click)",
                notes: "Tests: pointingButton action (To: pointing_button).\nBehavior: Pressing ctrl+opt+cmd+m performs a left mouse click at current cursor position.\nTo test: Position mouse, press ctrl+opt+cmd+m.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "m")]),
                actions: [Action(
                    kind: .pointingButton,
                    pointingButton: .left
                )]
            ),

            // ================================================================
            // FEATURE: mouseKey action — move mouse
            // ================================================================
            Manipulator(
                name: "[TEST] Mouse Key Action (Move Right 50px)",
                notes: "Tests: mouseKey action with X/Y movement.\nBehavior: Pressing ctrl+opt+cmd+right moves mouse cursor 50px to the right.\nTo test: Press ctrl+opt+cmd+right → mouse moves right.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "right_arrow")]),
                actions: [Action(
                    kind: .mouseKey,
                    mouseKey: MouseKeyAction(x: 50, y: 0, speedMultiplier: 1.0)
                )]
            ),

            // ================================================================
            // FEATURE: mouseKey action — scroll
            // ================================================================
            Manipulator(
                name: "[TEST] Mouse Key Action (Scroll Down)",
                notes: "Tests: mouseKey action with scroll wheel.\nBehavior: Pressing ctrl+opt+cmd+down_arrow scrolls down 3 ticks.\nTo test: Press ctrl+opt+cmd+down_arrow → page scrolls down.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "down_arrow")]),
                actions: [Action(
                    kind: .mouseKey,
                    mouseKey: MouseKeyAction(verticalWheel: 3, speedMultiplier: 1.0)
                )]
            ),

            // ================================================================
            // FEATURE: stickyModifier action
            // ================================================================
            Manipulator(
                name: "[TEST] Sticky Modifier Action",
                notes: "Tests: stickyModifier action.\nBehavior: Pressing ctrl+opt+cmd+s toggles Command as a sticky modifier. Once sticky, the next keypress has Command applied even without holding ⌘.\nTo test: Press ctrl+opt+cmd+s, then press 't' → should open new tab in Safari (⌘+t). Press again to release.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "s")]),
                actions: [Action(
                    kind: .stickyModifier,
                    stickyModifier: StickyModifierAction(modifier: .command, kind: .toggle)
                )]
            ),

            // ================================================================
            // FEATURE: halt action
            // ================================================================
            Manipulator(
                name: "[TEST] Halt Action",
                notes: "Tests: halt action to stop further actions.\nBehavior: Pressing ctrl+opt+cmd+p triggers 3 actions: 1) shows notification 'Before halt', 2) halt stops processing, 3) shows notification 'After halt' (should NOT fire).\nTo test: Press ctrl+opt+cmd+p → only 'Before halt' notification appears.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "p")]),
                actions: [
                    Action(
                        kind: .setNotification,
                        notificationMessage: "Before halt — this should appear"
                    ),
                    Action(kind: .halt),
                    Action(
                        kind: .setNotification,
                        notificationMessage: "After halt — this should NOT appear"
                    )
                ]
            ),

            // ================================================================
            // FEATURE: holdDown action
            // ================================================================
            Manipulator(
                name: "[TEST] Hold Down Action (500ms)",
                notes: "Tests: holdDown action with duration.\nBehavior: Pressing ctrl+opt+cmd+. (period) holds down the period key for 500ms, producing '.....'. Different from a normal tap.\nTo test: Press ctrl+opt+cmd+. → should type ...... (held for 500ms).",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "period")]),
                actions: [Action(
                    kind: .holdDown,
                    toKey: "period",
                    holdDownMilliseconds: 500
                )]
            ),

            // ================================================================
            // FEATURE: setNotification action
            // ================================================================
            Manipulator(
                name: "[TEST] Notification Action",
                notes: "Tests: setNotification action.\nBehavior: Pressing ctrl+opt+cmd+n shows a notification.\nTo test: Press ctrl+opt+cmd+n → notification appears.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "n")]),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Anvil: Notification action works!"
                )]
            ),

            // ================================================================
            // FEATURE: fromEvent action — mirror the original event
            // ================================================================
            Manipulator(
                name: "[TEST] From Event Action (Mirror)",
                notes: "Tests: fromEvent action.\nBehavior: Pressing ctrl+opt+f mirrors the original 'f' press through (still sends 'f' to the system). No visible effect — passes the event through unchanged.\nTo test: Press ctrl+opt+f → 'f' is typed normally.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "f")]),
                actions: [Action(kind: .fromEvent)]
            ),

            // ================================================================
            // FEATURE: softwareFunction — double click
            // ================================================================
            Manipulator(
                name: "[TEST] Software Function: Double Click",
                notes: "Tests: softwareFunction - cg_event_double_click.\nBehavior: Pressing ctrl+opt+cmd+d double-clicks at the current mouse position.\nTo test: Hover over a file or link, press ctrl+opt+cmd+d → opens it.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "d")]),
                actions: [Action(
                    kind: .softwareFunction,
                    softwareFunction: .doubleClick
                )]
            ),

            // ================================================================
            // FEATURE: softwareFunction — sleep system
            // ================================================================
            Manipulator(
                name: "[TEST] Software Function: Sleep System",
                notes: "Tests: softwareFunction - iokit_power_management_sleep_system.\nBehavior: Pressing ctrl+opt+cmd+shift+escape puts the computer to sleep.\nWARNING: Disabled by default — disruptive!",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command, .shift], key: "escape")]),
                actions: [Action(
                    kind: .softwareFunction,
                    softwareFunction: .sleepSystem
                )]
            ),

            // ================================================================
            // FEATURE: device_exists condition
            // ================================================================
            Manipulator(
                name: "[TEST] Condition: Device Exists",
                notes: "Tests: device_exists condition.\nBehavior: Pressing ctrl+opt+cmd+e sends text 'Device present' ONLY if a built-in keyboard exists (always true on MacBooks).\nTo test: Press ctrl+opt+cmd+e → types 'Device present'. Disconnect built-in keyboard (if possible) → should NOT fire.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "e")]),
                conditions: [Condition(
                    kind: .deviceExists,
                    op: .isEqual,
                    target: "built-in"
                )],
                actions: [Action(
                    kind: .sendText,
                    text: "Device present"
                )]
            ),

            // ================================================================
            // FEATURE: expression condition
            // ================================================================
            Manipulator(
                name: "[TEST] Condition: Expression (Variable == Value)",
                notes: "Tests: expression condition.\nBehavior: Pressing ctrl+opt+cmd+x sends 'Expr true' ONLY if variable 'mode' equals 'a'.\nTo test: Press ctrl+opt+cmd+1 first, then press ctrl+opt+cmd+x.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "x")]),
                conditions: [Condition(
                    kind: .expression,
                    op: .isEqual,
                    target: "mode == \"a\""
                )],
                actions: [Action(
                    kind: .sendText,
                    text: "Expr true"
                )]
            ),

            // ================================================================
            // FEATURE: event_changed condition
            // ================================================================
            Manipulator(
                name: "[TEST] Condition: Event Changed (Keyboard Type)",
                notes: "Tests: event_changed condition.\nBehavior: Pressing ctrl+opt+cmd+y sends 'Event changed' ONLY if the keyboard type has changed (always evaluates as possible).\nTo test: Press ctrl+opt+cmd+y → should fire (event change is always possible).",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "y")]),
                conditions: [Condition(
                    kind: .eventChanged,
                    op: .isEqual,
                    target: "keyboard_type"
                )],
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Event changed condition met!"
                )]
            ),

            // ================================================================
            // FEATURE: lazy modifier
            // ================================================================
            Manipulator(
                name: "[TEST] Lazy Modifier Action",
                notes: "Tests: lazy modifier on an action.\nBehavior: Pressing ctrl+opt+cmd+l sends 'l' with a LAZY Command modifier. The Command modifier does NOT take effect until another key is pressed after release.\nTo test: Press ctrl+opt+cmd+l (release) then quickly press 't' → cmd+t (new tab) fires.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "l")]),
                actions: {
                    var action = Action(kind: .sendKey, toKey: "l", toModifiers: [.command])
                    action.isLazy = true
                    return [action]
                }()
            ),

            // ================================================================
            // FEATURE: per-action conditions (to.conditions)
            // ================================================================
            Manipulator(
                name: "[TEST] Per-Action Conditions",
                notes: "Tests: to.conditions (per-action conditions).\nBehavior: Pressing ctrl+opt+cmd+a triggers 2 actions: 1) Sends 'A' ONLY if variable 'cond' == 'true', 2) Sends 'B' unconditionally.\nTo test: First set 'cond' variable to 'true', then press → types 'AB'. If 'cond' is anything else → types just 'B'.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "a")]),
                actions: [
                    Action(
                        kind: .sendKey,
                        fireMode: .onKeyDown,
                        toKey: "a",
                        toModifiers: [.shift],
                        actionConditions: [Condition(
                            kind: .variable,
                            op: .isEqual,
                            target: "cond",
                            value: "true"
                        )]
                    ),
                    Action(
                        kind: .sendKey,
                        fireMode: .onKeyDown,
                        toKey: "b",
                        toModifiers: [.shift]
                    )
                ]
            ),

            // ================================================================
            // FEATURE: selectInputSource action
            // ================================================================
            Manipulator(
                name: "[TEST] Select Input Source (ABC)",
                notes: "Tests: selectInputSource action.\nBehavior: Pressing ctrl+opt+cmd+i switches to the ABC keyboard layout.\nTo test: Press ctrl+opt+cmd+i → input source switches to ABC.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "i")]),
                actions: [Action(
                    kind: .selectInputSource,
                    inputSourceID: "com.apple.keylayout.ABC"
                )]
            ),

            // ================================================================
            // FEATURE: mouse_basic manipulator type
            // ================================================================
            Manipulator(
                name: "[TEST] Mouse Basic (Middle Button Remap)",
                notes: "Tests: mouse_basic manipulator type.\nBehavior: Middle mouse button click shows a notification instead of normal behavior.\nWARNING: Disabled by default — disruptive.",
                isEnabled: true,
                manipulatorType: .mouseBasic,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "middle")],
                    keyType: .pointing
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Mouse Basic: middle button remapped!"
                )]
            ),

            // ================================================================
            // FEATURE: mouse_motion_to_scroll manipulator type
            // ================================================================
            Manipulator(
                name: "[TEST] Mouse Motion to Scroll",
                notes: "Tests: mouse_motion_to_scroll manipulator type.\nBehavior: Converts mouse movement into scroll events. Moving the mouse up/down scrolls instead of moving cursor. Speed can be adjusted in Parameters → mouse_motion_to_scroll_speed.\nWARNING: Disabled by default — very disruptive for normal use.",
                isEnabled: true,
                manipulatorType: .mouseMotionToScroll,
                trigger: ManipulatorTrigger(),
                actions: [],
                parameters: ManipulatorParameters(mouseMotionToScrollSpeed: 1.0)
            ),

            // ================================================================
            // FEATURE: repeat action modifier
            // ================================================================
            Manipulator(
                name: "[TEST] Repeat Disabled Action",
                notes: "Tests: isRepeatEnabled action modifier.\nBehavior: Pressing and holding ctrl+opt+cmd+r sends 'r' once and does NOT repeat, even if held down.\nTo test: Hold ctrl+opt+cmd+r → 'r' appears once, not repeatedly.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "r")]),
                actions: {
                    var action = Action(kind: .sendKey, toKey: "r")
                    action.isRepeatEnabled = false
                    return [action]
                }()
            ),

            // ================================================================
            // FEATURE: Variable set/get via actions
            // ================================================================
            Manipulator(
                name: "[TEST] Variable Set + Toggle",
                notes: "Tests: variable set/toggle/unset actions.\nBehavior: Pressing ctrl+opt+cmd+1 sets variable 'mode'='a' and shows it. Pressing ctrl+opt+cmd+2 toggles mode true/false and shows it. Pressing ctrl+opt+cmd+0 unsets it.\nTo test: Use ctrl+opt+cmd+1 before the expression condition test.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "1")]),
                actions: [
                    Action(
                        kind: .setVariable,
                        variableName: "mode",
                        variableValue: "a"
                    ),
                    Action(kind: .setNotification, notificationMessage: "mode={mode}")
                ]
            ),
            Manipulator(
                name: "[TEST] Variable Toggle (mode)",
                notes: "Tests: toggle variable. Press ctrl+opt+cmd+2 to toggle 'mode' between true/false and show the result.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "2")]),
                actions: [
                    Action(
                        kind: .toggleVariable,
                        variableName: "mode",
                        toggleInitialState: false
                    ),
                    Action(kind: .setNotification, notificationMessage: "mode={mode}")
                ]
            ),
            Manipulator(
                name: "[TEST] Variable Unset (mode)",
                notes: "Tests: unset variable. Press ctrl+opt+cmd+0 to remove 'mode' variable.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "0")]),
                actions: [
                    Action(
                        kind: .unsetVariable,
                        variableName: "mode"
                    ),
                    Action(kind: .setNotification, notificationMessage: "mode unset")
                ]
            ),

            // ================================================================
            // FEATURE: Sequence trigger (multi-step)
            // ================================================================
            Manipulator(
                name: "[TEST] Sequence Trigger (a → b → c)",
                notes: "Tests: multi-step sequence trigger.\nBehavior: Pressing 'a', then 'b', then 'c' in sequence (within timeout) types 'Sequence complete!'.\nTo test: Press a, then b, then c within ~1.5 seconds.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [
                    KeyShortcut(key: "a"),
                    KeyShortcut(key: "b"),
                    KeyShortcut(key: "c")
                ]),
                actions: [Action(
                    kind: .sendText,
                    text: "Sequence complete!"
                )]
            ),

            // ================================================================
            // FEATURE: Typed string trigger (app-specific via frontmostApp
            //          condition)
            // ================================================================
            Manipulator(
                name: "[TEST] String Trigger (teh → autocorrect demo)",
                notes: "Tests: typed string trigger with full-match mode.\nBehavior: Typing \"teh\" triggers: backspace × 3 + type \"the\".\nThis demonstrates autocorrect behavior: when you type \"teh\", it replaces it with \"the\" as you type.\nThe space (or any following character) passes through normally.\nTo test: Type \"teh\" → should autocorrect to \"the\".",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "teh",
                        matchMode: .fullMatch,
                        timeoutSeconds: 1.5
                    )
                ),
                actions: [
                    // Delete the three typed characters ("teh")
                    Action(kind: .sendKey, toKey: "delete"),
                    Action(kind: .sendKey, toKey: "delete"),
                    Action(kind: .sendKey, toKey: "delete"),
                    // Type the corrected word
                    Action(kind: .sendText, text: "the")
                ]
            ),

            Manipulator(
                name: "[TEST] String Trigger (app-specific — Safari only)",
                notes: "Tests: typed string trigger scoped to a specific application.\nBehavior: Typing \"@@q\" in Safari shows a notification. The trigger only fires when Safari is the frontmost app.\nDemonstrates app-specific string triggering using the frontmostApp condition.\nTo test: Open Safari, type @@q → notification appears. Switch to another app, type @@q → nothing happens.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "@@q",
                        matchMode: .fullMatch,
                        timeoutSeconds: 2.0
                    )
                ),
                conditions: [Condition(
                    kind: .frontmostApp,
                    op: .isEqual,
                    target: "com.apple.Safari"
                )],
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "App-specific string trigger fired in Safari!"
                )]
            ),

            // ================================================================
            // FEATURE: Typed string trigger — prefix match mode
            // ================================================================
            Manipulator(
                name: "[TEST] String Trigger (prefix — 'ht' → http://)",
                notes: "Tests: typed string trigger with prefix match mode.\nBehavior: Type \"http\" and it appends \"://\" after the original text.\nTo test: Type \"http\" → should produce \"http://\".",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "http",
                        matchMode: .prefix,
                        timeoutSeconds: 1.5,
                        clearOnMatch: true
                    )
                ),
                actions: [
                    Action(kind: .sendText, text: "://")
                ]
            ),

            // ================================================================
            // FEATURE: Typed string trigger — anyMatch mode
            // ================================================================
            Manipulator(
                name: "[TEST] String Trigger (anyMatch — 'XYZ' anywhere)",
                notes: "Tests: typed string trigger with anyMatch mode.\nBehavior: When the typed buffer contains \"XYZ\" anywhere, types \"!\".\nThe trigger fires as soon as \"XYZ\" appears in the text, regardless of what was typed before or after.\nTo test: Type \"abcXYZdef\" → should produce \"abcXYZdef!\".",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "XYZ",
                        matchMode: .anyMatch,
                        timeoutSeconds: 3.0,
                        clearOnMatch: false
                    )
                ),
                actions: [
                    Action(kind: .sendText, text: "!")
                ]
            ),

            // ================================================================
            // FEATURE: Typed string trigger with clearOnMatch
            // ================================================================
            Manipulator(
                name: "[TEST] String Trigger (clearOnMatch — 'bug' → fixed)",
                notes: "Tests: typed string trigger with clearOnMatch=true.\nBehavior: Typing \"bug\" triggers: delete × 3 + type \"fixed\".\nThis demonstrates autocorrect behavior with automatic buffer clearing: the original \"bug\" is replaced by \"fixed\" and the buffer resets so subsequent typing isn't affected.\nTo test: Type \"bug\" → it autocorrects to \"fixed\". Type \"test bug more\" → the anyMatch below triggers on a full match, while this requires an exact full match so it won't fire in the middle of a sentence.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "bug",
                        matchMode: .fullMatch,
                        timeoutSeconds: 1.5,
                        clearOnMatch: true
                    )
                ),
                actions: [
                    Action(kind: .sendKey, toKey: "delete"),
                    Action(kind: .sendKey, toKey: "delete"),
                    Action(kind: .sendKey, toKey: "delete"),
                    Action(kind: .sendText, text: "fixed")
                ]
            ),

            // ================================================================
            // FEATURE: ifOtherKeyPressed fire mode
            // ================================================================
            Manipulator(
                name: "[TEST] If Other Key Pressed (tap = o / other = notification)",
                notes: "Tests: ifOtherKeyPressed fire mode.\nBehavior: Hold 'o' — if released within timeout, types 'alone!'. If another key is pressed while holding 'o', shows a notification. Demonstrates tap-vs-combo behavior.\nTo test: Quick tap 'o' → types 'alone!'. Hold 'o' and press another key → notification appears. If both fire modes are present on the same manipulator, they are mutually exclusive.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(key: "o")]),
                actions: [
                    Action(
                        kind: .sendText,
                        fireMode: .ifAlone,
                        text: "alone!"
                    ),
                    Action(
                        kind: .setNotification,
                        fireMode: .ifOtherKeyPressed,
                        notificationMessage: "Other key pressed while 'o' held!"
                    )
                ]
            ),

            // ================================================================
            // FEATURE: Named trigger — trigger a manipulator by name from another
            // ================================================================
            Manipulator(
                name: "[TEST] Named Trigger: Subroutine",
                notes: "Tests: named trigger (triggerName).\nBehavior: This manipulator has a triggerName 'my_subroutine' and can be triggered by another manipulator via the 'Execute Named Trigger' action. It types 'Hello from subroutine!' when triggered.\nIt is NOT triggered by any keyboard shortcut.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    triggerName: "my_subroutine"
                ),
                actions: [Action(
                    kind: .sendText,
                    text: "Hello from subroutine!"
                )]
            ),
            Manipulator(
                name: "[TEST] Execute Named Trigger",
                notes: "Tests: executeNamedTrigger action.\nBehavior: Pressing ctrl+opt+cmd+; (semicolon) executes the named trigger 'my_subroutine', which types 'Hello from subroutine!'.\nTo test: First enable the '[TEST] Named Trigger: Subroutine' manipulator above, then press ctrl+opt+cmd+;.",
                isEnabled: true,
                trigger: ManipulatorTrigger(steps: [KeyShortcut(mandatoryModifiers: [.control, .option, .command], key: "semicolon")]),
                actions: [Action(
                    kind: .executeNamedTrigger,
                    namedTrigger: "my_subroutine"
                )]
            ),

            // ================================================================
            // FEATURE: Hot Key multi-tap trigger (double-tap)
            // ================================================================
            Manipulator(
                name: "[TEST] Hot Key: Double-Tap 'z'",
                notes: "Tests: hotKey multi-tap with tapCount=2.\nBehavior: Tapping 'z' twice quickly (within 400ms) types 'double tap!'.\nA single tap does NOT type 'z' — it's consumed while waiting for a potential second tap.\nTo test: Tap 'z' twice quickly → types 'double tap!'.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "z")],
                    hotKey: HotKeyTriggerConfig(
                        tapCount: 2,
                        tapTimeoutMilliseconds: 400
                    )
                ),
                actions: [Action(
                    kind: .sendText,
                    fireMode: .onKeyDown,
                    text: "double tap!"
                )]
            ),

            // ================================================================
            // FEATURE: Hot Key multi-tap trigger (triple-tap)
            // ================================================================
            Manipulator(
                name: "[TEST] Hot Key: Triple-Tap 'x'",
                notes: "Tests: hotKey multi-tap with tapCount=3.\nBehavior: Tapping 'x' three times quickly (within 500ms) types 'triple tap!'.\nFewer than 3 taps within the timeout are consumed but produce no action.\nTo test: Tap 'x' three times quickly → types 'triple tap!'.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "x")],
                    hotKey: HotKeyTriggerConfig(
                        tapCount: 3,
                        tapTimeoutMilliseconds: 500
                    )
                ),
                actions: [Action(
                    kind: .sendText,
                    fireMode: .onKeyDown,
                    text: "triple tap!"
                )]
            ),

            // ================================================================
            // FEATURE: Hot Key with per-action tap count (different actions per
            //          tap count)
            // ================================================================
            Manipulator(
                name: "[TEST] Hot Key: Tap 'c' 1×→copy 2×→cut 3×→paste",
                notes: "Tests: hotKey multi-tap with per-action tapCount.\nBehavior: Single tap 'c' → copies (cmd+c). Double-tap 'c' → cuts (cmd+x). Triple-tap 'c' → pastes (cmd+v).\nEach action specifies a different tapCount. The trigger must reach the maximum needed tap count before the action fires.\nTo test: Quick tap 'c' → clipboard copy. Double-tap 'c' → cut. Triple-tap 'c' → paste.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "c")],
                    hotKey: HotKeyTriggerConfig(
                        tapCount: 3,
                        tapTimeoutMilliseconds: 500
                    )
                ),
                actions: [
                    Action(
                        kind: .sendKey,
                        fireMode: .onKeyDown,
                        toKey: "c",
                        toModifiers: [.command],
                        tapCount: 1
                    ),
                    Action(
                        kind: .sendKey,
                        fireMode: .onKeyDown,
                        toKey: "x",
                        toModifiers: [.command],
                        tapCount: 2
                    ),
                    Action(
                        kind: .sendKey,
                        fireMode: .onKeyDown,
                        toKey: "v",
                        toModifiers: [.command],
                        tapCount: 3
                    )
                ]
            ),

            // ================================================================
            // FEATURE: Hot Key with hold (tap then hold the final tap)
            // ================================================================
            Manipulator(
                name: "[TEST] Hot Key: Double-Tap & Hold 'v'",
                notes: "Tests: hotKey multi-tap with holdRequired.\nBehavior: Tap 'v' twice, then hold the second tap for 500ms → types 'held!'.\nDemonstrates combining multi-tap counting with hold detection.\nTo test: Tap 'v' twice, holding the second tap for 500ms → types 'held!'.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "v")],
                    hotKey: HotKeyTriggerConfig(
                        tapCount: 2,
                        tapTimeoutMilliseconds: 400,
                        holdRequired: true,
                        holdThresholdMilliseconds: 500
                    )
                ),
                actions: [
                    Action(
                        kind: .sendText,
                        fireMode: .ifHeldDown,
                        text: "held!",
                        tapCount: 2
                    )
                ]
            ),

            // ================================================================
            // FEATURE: Typed string trigger with app-specific scope (appBundleID)
            // ================================================================
            Manipulator(
                name: "[TEST] String Trigger (appBundleID — Safari only)",
                notes: "Tests: typed string trigger with appBundleID directly on StringTriggerOptions.\nBehavior: Typing \"@@s\" in Safari types \" Safari activated!\". The trigger only fires when Safari is the frontmost app.\nUnlike the older test which uses a separate frontmostApp condition, this scopes the trigger via stringTrigger.appBundleID.\nTo test: Open Safari, type @@s → types \" Safari activated!\". Switch to another app, type @@s → nothing happens.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    stringTrigger: StringTriggerOptions(
                        string: "@@s",
                        matchMode: .fullMatch,
                        timeoutSeconds: 2.0,
                        appBundleID: "com.apple.Safari"
                    )
                ),
                actions: [Action(
                    kind: .sendText,
                    text: " Safari activated!"
                )]
            ),

            // ================================================================
            // FEATURE: Modifier key as trigger (bug fix — modifiers arrive as
            //          flagsChanged, not keyDown, and are now dispatched)
            // ================================================================
            Manipulator(
                name: "[TEST] Modifier Key Trigger (Right Command)",
                notes: "Tests: a modifier key as the trigger key itself.\nBehavior: Pressing the RIGHT Command key alone shows a notification. Modifier keys emit flagsChanged events (not keyDown), which previously were never dispatched — this manipulator verifies the fix.\nTo test: Tap right ⌘ → notification appears. The left ⌘ key behaves normally.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(key: "right_command")]
                ),
                actions: [Action(
                    kind: .setNotification,
                    notificationMessage: "Modifier trigger works: Right Command pressed!"
                )]
            ),

            // ================================================================
            // FEATURE: windowAction — snap frontmost window (left half)
            // ================================================================
            Manipulator(
                name: "[TEST] Window Action (⌃⌥← → Left Half)",
                notes: "Tests: windowAction (Accessibility API window management).\nBehavior: Ctrl+Option+Left Arrow snaps the frontmost window to the left half of the screen.\nTo test: Focus any window, press ⌃⌥← → the window fills the left half.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "left_arrow")]
                ),
                actions: [{
                    var action = Action(kind: .windowAction)
                    action.windowActionKind = .leftHalf
                    return action
                }()]
            ),

            // ================================================================
            // FEATURE: windowAction — snap frontmost window (right half)
            // ================================================================
            Manipulator(
                name: "[TEST] Window Action (⌃⌥→ → Right Half)",
                notes: "Tests: windowAction with a second kind.\nBehavior: Ctrl+Option+Right Arrow snaps the frontmost window to the right half.\nTo test: Focus any window, press ⌃⌥→.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "right_arrow")]
                ),
                actions: [{
                    var action = Action(kind: .windowAction)
                    action.windowActionKind = .rightHalf
                    return action
                }()]
            ),

            // ================================================================
            // FEATURE: toggleDarkMode
            // ================================================================
            Manipulator(
                name: "[TEST] Toggle Dark Mode (⌃⌥D)",
                notes: "Tests: toggleDarkMode action.\nBehavior: Ctrl+Option+D toggles between Dark and Light appearance.\nTo test: Press ⌃⌥D → the system appearance flips.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "d")]
                ),
                actions: [Action(kind: .toggleDarkMode)]
            ),

            // ================================================================
            // FEATURE: transformText — clipboard UPPERCASE
            // ================================================================
            Manipulator(
                name: "[TEST] Transform Clipboard to UPPERCASE (⌃⌥U)",
                notes: "Tests: transformText action.\nBehavior: Ctrl+Option+U uppercases the current clipboard text and shows a notification.\nTo test: Copy some text, press ⌃⌥U, then paste → text is UPPERCASE.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "u")]
                ),
                actions: [
                    {
                        var action = Action(kind: .transformText)
                        action.textTransformKind = .upperCase
                        return action
                    }(),
                    Action(kind: .setNotification, notificationMessage: "Clipboard transformed to UPPERCASE")
                ]
            ),

            // ================================================================
            // FEATURE: setVolume + playSound
            // ================================================================
            Manipulator(
                name: "[TEST] Set Volume 25% + Ping (⌃⌥V)",
                notes: "Tests: setVolume and playSound actions.\nBehavior: Ctrl+Option+V sets system volume to 25% and plays the Ping sound so you can hear the level.\nTo test: Press ⌃⌥V → volume changes and Ping plays.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "v")]
                ),
                actions: [
                    {
                        var action = Action(kind: .setVolume)
                        action.numberValue = 25
                        return action
                    }(),
                    Action(kind: .playSound, text: "Ping")
                ]
            ),

            // ================================================================
            // FEATURE: speakText
            // ================================================================
            Manipulator(
                name: "[TEST] Speak Text (⌃⌥S)",
                notes: "Tests: speakText action (text-to-speech).\nBehavior: Ctrl+Option+S speaks a phrase aloud.\nTo test: Press ⌃⌥S → your Mac talks.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "s")]
                ),
                actions: [Action(kind: .speakText, text: "Anvil automation engine is working")]
            ),

            // ================================================================
            // FEATURE: incrementVariable + calculateExpression
            // ================================================================
            Manipulator(
                name: "[TEST] Increment Counter (⌃⌥I)",
                notes: "Tests: incrementVariable action.\nBehavior: Ctrl+Option+I increments the 'counter' variable by 1 and shows a notification. Check the variable in conditions or the debug panel.\nTo test: Press ⌃⌥I repeatedly → counter increases.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "i")]
                ),
                actions: [
                    Action(kind: .incrementVariable, variableName: "counter"),
                    Action(kind: .setNotification, notificationMessage: "Counter incremented — check the 'counter' variable")
                ]
            ),

            // ================================================================
            // FEATURE: getBatteryState + getIPAddress
            // ================================================================
            Manipulator(
                name: "[TEST] Battery & IP → Variables (⌃⌥B)",
                notes: "Tests: getBatteryState and getIPAddress actions.\nBehavior: Ctrl+Option+B stores battery level in 'batteryLevel', charging state in 'batteryCharging', and IP in 'ipAddress' variables, then notifies.\nTo test: Press ⌃⌥B → notification appears; variables are set for use in conditions.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "b")]
                ),
                actions: [
                    Action(kind: .getBatteryState),
                    Action(kind: .getIPAddress),
                    Action(kind: .setNotification, notificationMessage: "Battery {batteryLevel}% charging={batteryCharging} IP={ipAddress}")
                ]
            ),

            // ================================================================
            // FEATURE: flashScreen
            // ================================================================
            Manipulator(
                name: "[TEST] Flash Screen (⌃⌥F)",
                notes: "Tests: flashScreen action.\nBehavior: Ctrl+Option+F flashes the screen with a brief white overlay — useful as silent visual feedback for macros.\nTo test: Press ⌃⌥F → the screen flashes.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "f")]
                ),
                actions: [Action(kind: .flashScreen)]
            ),

            // ================================================================
            // FEATURE: activateLastApp
            // ================================================================
            Manipulator(
                name: "[TEST] Activate Last App (⌃⌥Tab)",
                notes: "Tests: activateLastApp action.\nBehavior: Ctrl+Option+Tab switches back to the previously active application (quick app toggle).\nTo test: Switch between two apps, then press ⌃⌥Tab → jumps back to the previous app.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "tab")]
                ),
                actions: [Action(kind: .activateLastApp)]
            ),

            // ================================================================
            // FEATURE: httpRequest
            // ================================================================
            Manipulator(
                name: "[TEST] HTTP Request (⌃⌥H)",
                notes: "Tests: httpRequest action.\nBehavior: Ctrl+Option+H makes a GET request to example.com and stores the response body in the 'httpResponse' variable.\nTo test: Press ⌃⌥H → notification appears; the response is stored for use in conditions.",
                isEnabled: true,
                trigger: ManipulatorTrigger(
                    steps: [KeyShortcut(mandatoryModifiers: [.control, .option], key: "h")]
                ),
                actions: [
                    Action(kind: .httpRequest, urlString: "https://example.com"),
                    Action(kind: .setNotification, notificationMessage: "GET https://example.com → stored in 'httpResponse'")
                ]
            ),
        ]
    }
}
