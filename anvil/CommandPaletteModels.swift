import AppKit
import Foundation
import SwiftUI

// MARK: - Command Palette Style

/// The presentation style used to render a command palette.
enum CommandPaletteStyle: String, CaseIterable, Identifiable, Codable {
    /// Centered search overlay with a filterable list of commands (Spotlight/Alfred style).
    case spotlight = "Spotlight"
    /// Horizontal shelf of tiles docked to the bottom of the screen.
    case shelf = "Shelf"
    /// Radial palette with the commands arranged around a circle.
    case circular = "Circular"
    /// Grid of large tiles, like a launcher.
    case grid = "Grid"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spotlight: return "magnifyingglass"
        case .shelf: return "tray.full"
        case .circular: return "circle.hexagonpath"
        case .grid: return "square.grid.2x2"
        }
    }

    var helpText: String {
        switch self {
        case .spotlight: return "Search overlay: a collapsed pill that expands to show your commands. Each command is either a full-size row or a compact box in the strip under the search field."
        case .shelf: return "Square drop shelf beside the cursor (hotkey, or wiggle the cursor while dragging a file). With no commands it's a plain shelf for gathering files; add commands to turn them into actions for the files you drop."
        case .circular: return "Radial palette with the commands arranged around a circle."
        case .grid: return "Grid of large tiles, like a launcher."
        }
    }

    /// Whether the style shows a search field.
    var supportsSearch: Bool {
        switch self {
        case .spotlight, .grid: return true
        case .shelf, .circular: return false
        }
    }

    /// Default window size used when the palette is presented.
    var defaultSize: CGSize {
        switch self {
        case .spotlight: return CGSize(width: 640, height: 420)
        case .shelf: return CGSize(width: 260, height: 260)
        case .circular: return CGSize(width: 460, height: 460)
        case .grid: return CGSize(width: 720, height: 460)
        }
    }
}

// MARK: - Spawn Position

/// Where a palette panel appears when it is shown.
enum CommandPaletteSpawn: String, CaseIterable, Identifiable, Codable {
    /// Each style uses its natural spot: search overlays sit upper-centre,
    /// drop shelves appear beside the cursor.
    case standard = "Default"
    /// The panel is centred on the mouse position.
    case cursor = "At Cursor"
    /// Horizontally and vertically centred on the screen.
    case screenCenter = "Screen Center"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .standard: return "Each style uses its natural spot — Spotlight upper-centre, drop shelves at the cursor."
        case .cursor: return "The panel always appears centred on the mouse position."
        case .screenCenter: return "The panel appears centred on the screen."
        }
    }
}

// MARK: - Command Palette Action

/// Command palette items reuse the same lightweight action model as menu bar items,
/// so every action kind (shell, app, URL, key combo, variable, …) is available.
typealias CommandPaletteAction = MenuBarItemAction

// MARK: - Command Palette Item Look

/// How a command renders inside a Spotlight palette: a full-width result row,
/// or a compact box in the horizontal strip under the search field
/// (the way Spotlight presents apps).
enum CommandPaletteItemLook: String, CaseIterable, Identifiable, Codable {
    case row = "Row"
    case strip = "Strip Box"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .row: return "Full-width Spotlight result row."
        case .strip: return "Compact box in the strip under the search field."
        }
    }
}

// MARK: - Command Palette Item

/// A single command that can be launched from a command palette.
struct CommandPaletteItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "New Command"
    var icon: String = "star"
    var subtitle: String = ""
    /// Optional group shown as a tab in the Spotlight style.
    var category: String = ""
    /// Name of the accent colour used for the item's badge.
    var tint: String = "blue"
    /// Extra search terms matched in addition to the name and subtitle.
    var keywords: [String] = []
    var isEnabled: Bool = true
    /// How the item is presented in the Spotlight style.
    var look: CommandPaletteItemLook = .row
    /// The action performed when the item is triggered.
    var action: CommandPaletteAction = CommandPaletteAction(kind: .none)

    init(
        id: UUID = UUID(),
        name: String = "New Command",
        icon: String = "star",
        subtitle: String = "",
        category: String = "",
        tint: String = "blue",
        keywords: [String] = [],
        isEnabled: Bool = true,
        look: CommandPaletteItemLook = .row,
        action: CommandPaletteAction = CommandPaletteAction(kind: .none)
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.subtitle = subtitle
        self.category = category
        self.tint = tint
        self.keywords = keywords
        self.isEnabled = isEnabled
        self.look = look
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, subtitle, category, tint, keywords, isEnabled, look, action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = container.lenientUUID(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Command"
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "star"
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        self.tint = try container.decodeIfPresent(String.self, forKey: .tint) ?? "blue"
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.look = container.lenientEnum(forKey: .look, default: .row)
        self.action = try container.decodeIfPresent(CommandPaletteAction.self, forKey: .action)
            ?? CommandPaletteAction(kind: .none)
    }

    /// Short description of what the item does.
    var summary: String { action.summary }

    /// Text used by the palette search filter.
    var searchText: String {
        ([name, subtitle, category] + keywords).joined(separator: " ")
    }

    /// Accent colour used for the item's badge.
    var tintColor: Color {
        Color(commandPaletteTintName: tint)
    }

    /// Available badge colours.
    static let availableTints: [String] = [
        "blue", "indigo", "purple", "pink", "red", "orange", "yellow",
        "green", "mint", "teal", "cyan", "brown", "gray"
    ]
}

extension Color {
    /// Maps a badge colour name used by command palette items to a SwiftUI colour.
    init(commandPaletteTintName name: String) {
        switch name {
        case "red": self = .red
        case "orange": self = .orange
        case "yellow": self = .yellow
        case "green": self = .green
        case "mint": self = .mint
        case "teal": self = .teal
        case "cyan": self = .cyan
        case "blue": self = .blue
        case "indigo": self = .indigo
        case "purple": self = .purple
        case "pink": self = .pink
        case "brown": self = .brown
        case "gray": self = .gray
        default: self = .accentColor
        }
    }
}

// MARK: - Command Palette

/// A collection of commands presented in a chosen style.
struct CommandPalette: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "New Palette"
    var style: CommandPaletteStyle = .spotlight
    var icon: String = "command.square"
    var isEnabled: Bool = true
    var items: [CommandPaletteItem] = []
    /// Global hotkey that opens the palette. Empty when unset.
    var hotkey: KeyShortcut = KeyShortcut()
    /// Whether the palette is also exposed as a menu bar status item.
    var showInMenuBar: Bool = false
    /// Where the panel appears when the palette is shown.
    var spawn: CommandPaletteSpawn = .standard

    init(
        id: UUID = UUID(),
        name: String = "New Palette",
        style: CommandPaletteStyle = .spotlight,
        icon: String = "command.square",
        isEnabled: Bool = true,
        items: [CommandPaletteItem] = [],
        hotkey: KeyShortcut = KeyShortcut(),
        showInMenuBar: Bool = false,
        spawn: CommandPaletteSpawn = .standard
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.icon = icon
        self.isEnabled = isEnabled
        self.items = items
        self.hotkey = hotkey
        self.showInMenuBar = showInMenuBar
        self.spawn = spawn
    }

    enum CodingKeys: String, CodingKey {
        case id, name, style, icon, isEnabled, items, hotkey, showInMenuBar, spawn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = container.lenientUUID(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Palette"
        self.style = container.lenientEnum(forKey: .style, default: .spotlight)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "command.square"
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.items = try container.decodeIfPresent([CommandPaletteItem].self, forKey: .items) ?? []
        self.hotkey = try container.decodeIfPresent(KeyShortcut.self, forKey: .hotkey) ?? KeyShortcut()
        self.showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
        self.spawn = container.lenientEnum(forKey: .spawn, default: .standard)
    }

    /// Items that are eligible to be shown and triggered.
    var enabledItems: [CommandPaletteItem] {
        items.filter(\.isEnabled)
    }

    /// Whether a hotkey has been configured.
    var hasHotkey: Bool { !hotkey.isEmpty }

    var summary: String {
        let count = items.count
        return "\(count) command\(count == 1 ? "" : "s")"
    }
}

// MARK: - Defaults

extension CommandPalette {
    /// Starter palettes shown when a profile has none yet: a Spotlight search
    /// palette plus a shelf that starts as a plain file gatherer.
    static func defaults() -> [CommandPalette] {
        [
            CommandPalette(
                name: "Quick Actions",
                style: .spotlight,
                icon: "command.square",
                items: [
                    CommandPaletteItem(
                        name: "Lock Screen",
                        icon: "lock.fill",
                        subtitle: "Lock the Mac",
                        category: "System",
                        tint: "blue",
                        action: CommandPaletteAction(
                            kind: .runShell,
                            shellCommand: "\"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession\" -suspend"
                        )
                    ),
                    CommandPaletteItem(
                        name: "Show Desktop",
                        icon: "rectangle.on.rectangle",
                        subtitle: "Move windows aside",
                        category: "System",
                        tint: "indigo",
                        action: CommandPaletteAction(
                            kind: .runShell,
                            shellCommand: "open -b com.apple.exposelauncher --args 1"
                        )
                    ),
                    CommandPaletteItem(
                        name: "Empty Trash",
                        icon: "trash.fill",
                        subtitle: "Delete everything in the Trash",
                        category: "Files",
                        tint: "orange",
                        action: CommandPaletteAction(
                            kind: .runAppleScript,
                            scriptBody: "tell application \"Finder\" to empty trash"
                        )
                    ),
                ],
                hotkey: KeyShortcut(mandatoryModifiers: [.command, .shift], key: "space")
            ),
            CommandPalette(
                name: "Drop Shelf",
                style: .shelf,
                icon: "tray.and.arrow.down",
                items: []
            ),
        ]
    }
}
