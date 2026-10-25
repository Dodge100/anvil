import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Menu Bar Action Kind

enum MenuBarActionKind: String, CaseIterable, Identifiable, Codable, CustomStringConvertible {
    case none = "None"
    case showMenu = "Show Menu"
    case runShortcut = "Run Shortcut"
    case runShell = "Run Shell"
    case openApp = "Open App"
    case openURL = "Open URL"
    case sendKey = "Send Key"
    case setVariable = "Set Variable"
    case toggleVariable = "Toggle Variable"
    case incrementVariable = "Increment Variable"
    case setNotification = "Show Notification"
    case openFile = "Open File"
    case runAppleScript = "Run AppleScript"

    var id: String { rawValue }
    var description: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "minus"
        case .showMenu: return "list.bullet"
        case .runShortcut: return "shortcuts"
        case .runShell: return "terminal"
        case .openApp: return "app"
        case .openURL: return "link"
        case .sendKey: return "keyboard"
        case .setVariable: return "variable"
        case .toggleVariable: return "switch.variable"
        case .incrementVariable: return "plus.circle"
        case .setNotification: return "bell"
        case .openFile: return "doc"
        case .runAppleScript: return "applescript"
        }
    }

    var helpText: String {
        switch self {
        case .none: return "No action"
        case .showMenu: return "Open the item's sub-items menu"
        case .runShortcut: return "Run a macOS Shortcut"
        case .runShell: return "Execute a shell command"
        case .openApp: return "Open an application"
        case .openURL: return "Open a URL"
        case .sendKey: return "Send a keyboard shortcut"
        case .setVariable: return "Set an Anvil variable"
        case .toggleVariable: return "Toggle an Anvil variable (true/false)"
        case .incrementVariable: return "Increment a numeric variable"
        case .setNotification: return "Show a macOS notification"
        case .openFile: return "Open a file or folder"
        case .runAppleScript: return "Run an AppleScript"
        }
    }
}

// MARK: - Menu Bar Item Action

/// An action that a menu bar item can perform on left-click or right-click.
struct MenuBarItemAction: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: MenuBarActionKind = .none

    // Generic parameters (only the relevant ones are used per kind)
    var shortcutName: String = ""
    var shellCommand: String = ""
    var appBundleID: String = ""
    var appName: String = ""
    var urlString: String = ""
    var toKey: String = ""
    var toModifiers: Set<ModifierKey> = []
    var variableName: String = ""
    var variableValue: String = ""
    var notificationMessage: String = ""
    var filePath: String = ""
    var scriptBody: String = ""

    var summary: String {
        switch kind {
        case .none: return "No action"
        case .showMenu: return "Show menu"
        case .runShortcut: return shortcutName.isEmpty ? "Run shortcut" : "Run \u{201C}\(shortcutName)\u{201D}"
        case .runShell:
            let cmd = shellCommand.trimmingCharacters(in: .whitespaces)
            if cmd.isEmpty { return "Run shell" }
            let prefix = cmd.prefix(50)
            return "Shell: \(prefix)\(cmd.count > 50 ? "\u{2026}" : "")"
        case .openApp: return appName.isEmpty ? "Open app" : "Open \(appName)"
        case .openURL: return urlString.isEmpty ? "Open URL" : urlString
        case .sendKey:
            if toKey.isEmpty { return "Send key" }
            return "Send \(KeyShortcut(mandatoryModifiers: toModifiers, key: toKey).displayLabel)"
        case .setVariable:
            return variableName.isEmpty ? "Set variable" : "\(variableName) = \(variableValue)"
        case .toggleVariable: return variableName.isEmpty ? "Toggle variable" : "Toggle \(variableName)"
        case .incrementVariable: return variableName.isEmpty ? "Increment" : "\(variableName)++"
        case .setNotification: return notificationMessage.isEmpty ? "Notify" : "Notify: \(notificationMessage.prefix(40))"
        case .openFile: return filePath.isEmpty ? "Open file" : "\(filePath)"
        case .runAppleScript: return scriptBody.isEmpty ? "Run AppleScript" : "AppleScript"
        }
    }

    /// Execute this action using the given remap engine / store context.
    ///
    /// Kinds that perform blocking I/O (shell commands, AppleScript, Shortcuts)
    /// are dispatched to a background queue so a slow command can't freeze the
    /// UI — the same treatment the manipulator engine gives its blocking actions.
    @MainActor
    func execute(store: RemapStore) {
        // .showMenu is intercepted by StatusBarController, which opens the
        // menu directly — there is nothing to execute here.
        guard kind != .none && kind != .showMenu else { return }
        switch kind {
        case .none, .showMenu:
            break
        case .runShortcut:
            if !shortcutName.isEmpty {
                let name = shortcutName
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = ShortcutsService.runShortcut(named: name)
                }
            }
        case .runShell:
            if !shellCommand.isEmpty {
                let command = shellCommand
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = store.runShellCommand(command)
                }
            }
        case .openApp:
            let bundleID = appBundleID, name = appName
            DispatchQueue.global(qos: .userInitiated).async {
                store.openApplication(bundleID: bundleID, name: name)
            }
        case .openURL:
            if !urlString.isEmpty, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .sendKey:
            if !toKey.isEmpty {
                store.postKeyCombo(modifiers: toModifiers, keyID: toKey)
            }
        case .setVariable:
            if !variableName.isEmpty {
                store.engine.setVariable(name: variableName, value: variableValue)
                store.objectWillChange.send()
            }
        case .toggleVariable:
            if !variableName.isEmpty {
                let current = store.engine.variables[variableName] ?? "false"
                let newValue = current == "true" ? "false" : "true"
                store.engine.setVariable(name: variableName, value: newValue)
                store.objectWillChange.send()
            }
        case .incrementVariable:
            if !variableName.isEmpty {
                let current = Double(store.engine.variables[variableName] ?? "0") ?? 0
                let step = Double(variableValue) ?? 1
                let newValue = current + step
                let formatted = newValue == newValue.rounded() ? String(Int(newValue)) : String(newValue)
                store.engine.setVariable(name: variableName, value: formatted)
                store.objectWillChange.send()
            }
        case .setNotification:
            if !notificationMessage.isEmpty {
                store.showNotificationMessage(notificationMessage)
            }
        case .openFile:
            if !filePath.isEmpty {
                let expanded = (filePath as NSString).expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            }
        case .runAppleScript:
            if !scriptBody.isEmpty {
                let source = scriptBody
                DispatchQueue.global(qos: .userInitiated).async {
                    var error: NSDictionary?
                    if let script = NSAppleScript(source: source) {
                        script.executeAndReturnError(&error)
                    }
                    if let error {
                        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                        Task { @MainActor in
                            store.showNotificationMessage("AppleScript error: \(message)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Menu Bar Item

/// A single item in the Anvil menu bar menu.
/// Can be a simple action item, a separator, or a submenu with children.
struct MenuBarItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "New Menu Item"
    var icon: String = "star"
    var isEnabled: Bool = true
    var isSeparator: Bool = false
    var children: [MenuBarItem] = []
    /// Sub-items shown by the right-click menu (when Right Click = Show Menu).
    var rightChildren: [MenuBarItem] = []
    var leftClickAction: MenuBarItemAction?
    var rightClickAction: MenuBarItemAction?

    /// Memberwise init, kept explicit because the custom decoder below would
    /// otherwise suppress it.
    init(id: UUID = UUID(), name: String = "New Menu Item", icon: String = "star",
         isEnabled: Bool = true, isSeparator: Bool = false,
         children: [MenuBarItem] = [], rightChildren: [MenuBarItem] = [],
         leftClickAction: MenuBarItemAction? = nil, rightClickAction: MenuBarItemAction? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isEnabled = isEnabled
        self.isSeparator = isSeparator
        self.children = children
        self.rightChildren = rightChildren
        self.leftClickAction = leftClickAction
        self.rightClickAction = rightClickAction
    }

    /// Custom decoder so configs saved before `rightChildren` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Menu Item"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "star"
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isSeparator = try c.decodeIfPresent(Bool.self, forKey: .isSeparator) ?? false
        children = try c.decodeIfPresent([MenuBarItem].self, forKey: .children) ?? []
        rightChildren = try c.decodeIfPresent([MenuBarItem].self, forKey: .rightChildren) ?? []
        leftClickAction = try c.decodeIfPresent(MenuBarItemAction.self, forKey: .leftClickAction)
        rightClickAction = try c.decodeIfPresent(MenuBarItemAction.self, forKey: .rightClickAction)
    }

    /// "Has a runnable action" — Show Menu is a click behavior, not an action.
    var hasLeftAction: Bool {
        guard let action = leftClickAction else { return false }
        return action.kind != .none && action.kind != .showMenu
    }

    var hasRightAction: Bool {
        guard let action = rightClickAction else { return false }
        return action.kind != .none && action.kind != .showMenu
    }

    var summary: String {
        if isSeparator { return "Separator" }
        var parts: [String] = []
        if hasLeftAction { parts.append(leftClickAction?.summary ?? "") }
        if leftClickAction?.kind == .showMenu { parts.append("Left: menu") }
        if hasRightAction { parts.append("Right: \(rightClickAction?.summary ?? "")") }
        if rightClickAction?.kind == .showMenu { parts.append("Right: menu") }
        let subCount = children.count + rightChildren.count
        if subCount > 0 {
            parts.append("\(subCount) sub-item\(subCount == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "No action" }
        return parts.joined(separator: " | ")
    }

    static let availableIcons: [String] = [
        "star", "star.fill", "heart", "heart.fill", "flag", "flag.fill",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "bell", "bell.fill",
        "folder", "folder.fill", "doc", "doc.fill", "note.text",
        "list.bullet", "checkmark", "xmark",
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "plus", "minus", "gearshape", "gearshape.fill",
        "slider.horizontal.3", "switch.2",
        "play", "pause", "stop", "forward", "backward",
        "speaker", "speaker.wave.2", "speaker.slash",
        "sun.max", "moon", "moon.fill", "sparkles",
        "person", "person.fill", "macmini", "display",
        "keyboard", "keyboard.fill", "cursorarrow", "cursorarrow.click",
        "square.on.square", "rectangle.on.rectangle", "arrow.up.arrow.down",
        "clock", "clock.fill", "calendar", "calendar.fill",
        "lock", "lock.fill", "lock.open", "lock.open.fill",
        "pencil", "scissors", "trash", "trash.fill",
        "terminal", "terminal.fill", "network", "wifi",
        "rectangle.3.group", "square.grid.2x2",
        "1.circle", "2.circle", "3.circle", "a.circle", "b.circle",
        "app", "app.fill",
        "message", "message.fill", "globe",
        "music.note", "music.note.list", "headphones",
        "house", "house.fill", "building", "building.fill",
        "lightbulb", "lightbulb.fill",
        "magnifyingglass", "camera", "camera.fill",
        "mic", "mic.fill", "waveform",
        "chart.pie", "chart.bar",
        "circle", "circle.fill", "square", "square.fill",
        "diamond", "diamond.fill", "triangle", "triangle.fill",
        "shield", "shield.fill",
        "paintpalette", "paintbrush",
        "apple.logo",
        "chevron.down", "chevron.up", "chevron.left", "chevron.right",
        "arrow.clockwise", "arrow.counterclockwise",
        "return", "escape", "power",
        "delete.backward", "delete.forward",
        "eject", "eject.fill",
    ]
}

// MARK: - Menu Bar Items Container (for JSON persistence)

struct MenuBarItemsConfig: Codable {
    var items: [MenuBarItem] = []
}

// MARK: - Defaults

extension MenuBarItem {
    /// Default menu bar items shown on first launch.
    static func defaults() -> [MenuBarItem] {
        [
            MenuBarItem(
                name: "Open Anvil",
                icon: "keyboard",
                isEnabled: true,
                leftClickAction: MenuBarItemAction(
                    kind: .runShell,
                    shellCommand: "open -a Anvil"
                ),
                rightClickAction: MenuBarItemAction(
                    kind: .setNotification,
                    notificationMessage: "Anvil is running"
                )
            ),
            MenuBarItem(
                name: "Quick Shortcuts",
                icon: "rectangle.3.group",
                isEnabled: true,
                children: [
                    MenuBarItem(
                        name: "Lock Screen",
                        icon: "lock",
                        leftClickAction: MenuBarItemAction(
                            kind: .runShell,
                            shellCommand: "\"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession\" -suspend"
                        )
                    ),
                    MenuBarItem(
                        name: "Show Desktop",
                        icon: "rectangle.on.rectangle",
                        leftClickAction: MenuBarItemAction(
                            kind: .runShell,
                            shellCommand: "open -b com.apple.exposelauncher --args 1"
                        )
                    ),
                    MenuBarItem(
                        name: "Empty Trash",
                        icon: "trash",
                        leftClickAction: MenuBarItemAction(
                            kind: .runAppleScript,
                            scriptBody: "tell application \"Finder\" to empty trash"
                        )
                    ),
                ]
            ),
            MenuBarItem(
                name: "Useful Links",
                icon: "link",
                isEnabled: true,
                children: [
                    MenuBarItem(
                        name: "GitHub",
                        icon: "chevron.left.forwardslash.chevron.right",
                        leftClickAction: MenuBarItemAction(
                            kind: .openURL,
                            urlString: "https://github.com"
                        )
                    ),
                    MenuBarItem(
                        name: "ChatGPT",
                        icon: "message",
                        leftClickAction: MenuBarItemAction(
                            kind: .openURL,
                            urlString: "https://chat.openai.com"
                        )
                    ),
                ]
            ),
        ]
    }
}
