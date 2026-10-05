import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Modifier

enum ModifierKey: String, CaseIterable, Identifiable, Hashable, Codable {
    case command
    case shift
    case option
    case control
    case capsLock = "caps_lock"
    case fn

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        case .capsLock: return "⇪"
        case .fn: return "fn"
        }
    }

    var longName: String {
        switch self {
        case .command: return "Command"
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        case .capsLock: return "Caps Lock"
        case .fn: return "Fn"
        }
    }

    var cgFlag: CGEventFlags? {
        switch self {
        case .command: return .maskCommand
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .capsLock: return .maskAlphaShift
        case .fn: return nil
        }
    }

    static var flagBased: [ModifierKey] {
        [.command, .shift, .option, .control, .capsLock]
    }


}

// MARK: - Consumer Key Code

enum ConsumerKeyCode: String, CaseIterable, Identifiable, Codable {
    case play
    case pause
    case next
    case previous
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case mute
    case brightnessUp = "brightness_up"
    case brightnessDown = "brightness_down"
    case rewind
    case fastForward = "fast_forward"
    case eject
    case power

    var id: String { rawValue }

    var label: String {
        switch self {
        case .play: return "Play"
        case .pause: return "Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .rewind: return "Rewind"
        case .fastForward: return "Fast Forward"
        case .eject: return "Eject"
        case .power: return "Power"
        }
    }

    var symbol: String {
        switch self {
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .volumeUp: return "speaker.wave.2.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .brightnessUp: return "sun.max.fill"
        case .brightnessDown: return "sun.min.fill"
        case .rewind: return "backward.end.fill"
        case .fastForward: return "forward.end.fill"
        case .eject: return "eject.fill"
        case .power: return "power"
        }
    }

    var nxKeyType: Int32 {
        switch self {
        case .play: return NX_KEYTYPE_PLAY
        case .pause: return NX_KEYTYPE_PLAY
        case .next: return NX_KEYTYPE_NEXT
        case .previous: return NX_KEYTYPE_PREVIOUS
        case .volumeUp: return NX_KEYTYPE_SOUND_UP
        case .volumeDown: return NX_KEYTYPE_SOUND_DOWN
        case .mute: return NX_KEYTYPE_MUTE
        case .brightnessUp: return NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown: return NX_KEYTYPE_BRIGHTNESS_DOWN
        case .rewind: return NX_KEYTYPE_REWIND
        case .fastForward: return NX_KEYTYPE_FF
        case .eject: return NX_KEYTYPE_EJECT
        case .power: return NX_KEYTYPE_POWER
        }
    }
}

// MARK: - Config Profile

/// A named configuration profile that holds a distinct set of manipulators.
/// Users can create multiple profiles for different contexts (work, gaming, writing, etc.)
/// and switch between them at runtime.
struct ConfigProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol name used as the profile's icon in the picker UI.
    var icon: String = "person"
    /// Color name for visual accent.
    var colorName: String = "accent"

    static let availableIcons: [String] = [
        "person", "briefcase", "gamecontroller", "pencil",
        "star", "heart", "flag", "book",
        "music.note", "film", "paintpalette", "wrench",
        "gearshape", "display", "laptopcomputer", "keyboard",
        "cursorarrow", "textformat.abc", "dock.rectangle", "terminal",
        "apple.logo", "sun.max", "moon", "sparkles"
    ]

    /// Available profile accent colors.
    static let availableColors: [(name: String, color: Color)] = [
        ("accent", .accentColor),
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("mint", .mint),
        ("teal", .teal),
        ("cyan", .cyan),
        ("blue", .blue),
        ("indigo", .indigo),
        ("purple", .purple),
        ("pink", .pink)
    ]

    /// Resolved color from colorName.
    var accentColor: Color {
        Self.availableColors.first(where: { $0.name == colorName })?.color ?? .accentColor
    }

    /// A default profile for initial use.
    static func `default`() -> ConfigProfile {
        ConfigProfile(name: "Default", icon: "person")
    }
}

/// Serializable manifest stored at `profiles.json`.
struct ProfilesManifest: Codable {
    var profiles: [ConfigProfile]
    var activeProfileID: UUID
}

/// Per-profile data stored on disk for each profile.
/// Each profile file contains both manipulators and menu bar items.
struct ProfileData: Codable {
    var manipulators: [Manipulator]
    var menuBarItems: [MenuBarItem]

    static func `default`() -> ProfileData {
        ProfileData(
            manipulators: [],
            menuBarItems: MenuBarItem.defaults()
        )
    }
}

/// Errors that can occur during profile operations.
enum ProfileError: LocalizedError {
    case cannotDeleteDefault

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefault:
            return "The Default profile cannot be deleted. Create another profile first."
        }
    }
}

// MARK: - Pointing Button

enum PointingButton: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case middle
    case back
    case forward
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Left Button"
        case .right: return "Right Button"
        case .middle: return "Middle Button"
        case .back: return "Back Button"
        case .forward: return "Forward Button"
        case .center: return "Center Button"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "cursorarrow.click"
        case .right: return "cursorarrow.click.2"
        case .middle: return "cursorarrow.click.3"
        case .back: return "arrow.left.to.line"
        case .forward: return "arrow.right.to.line"
        case .center: return "cursorarrow.click"
        }
    }

    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        case .back: return .center
        case .forward: return .center
        case .center: return .center
        }
    }
}

// MARK: - Trigger key type

enum TriggerKeyType: String, CaseIterable, Identifiable, Codable {
    case keyboard = "Keyboard Key"
    case consumer = "Consumer Key"
    case pointing = "Mouse Button"
    case any = "Any Key"
    case typedString = "Typed String"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .keyboard: return "keyboard"
        case .consumer: return "play.square"
        case .pointing: return "cursorarrow"
        case .any: return "asterisk"
        case .typedString: return "textformat.abc"
        }
    }
}

// MARK: - Typed String Match Mode

// MARK: - Simultaneous Order

enum SimultaneousOrder: String, CaseIterable, Identifiable, Codable {
    case insensitive
    case strict
    case strictInverse = "strict_inverse"

    var id: String { rawValue }
}

enum SimultaneousUpWhen: String, CaseIterable, Identifiable, Codable {
    case any
    case all

    var id: String { rawValue }
}

// MARK: - Simultaneous trigger

struct SimultaneousTrigger: Equatable, Codable {
    var keys: [KeyShortcut] = []
    var options: SimultaneousOptions = .init()

    var isValid: Bool { keys.count >= 2 && keys.allSatisfy { !$0.key.isEmpty } }
}

struct SimultaneousOptions: Equatable, Codable {
    var detectKeyDownUninterruptedly: Bool = false
    var keyDownOrder: SimultaneousOrder = .insensitive
    var keyUpOrder: SimultaneousOrder = .insensitive
    var keyUpWhen: SimultaneousUpWhen = .any
    var toAfterKeyUp: [Action] = []
}

// MARK: - Key shortcut

struct KeyShortcut: Equatable, Hashable, Codable {
    var mandatoryModifiers: Set<ModifierKey> = []
    var optionalModifiers: Set<ModifierKey> = []
    var key: String = ""

    static let empty = KeyShortcut()

    var isEmpty: Bool { key.isEmpty }

    var displayLabel: String {
        if key.isEmpty { return "Not recorded" }
        let ordered: [ModifierKey] = [.control, .option, .shift, .command, .capsLock, .fn]
        let mandatoryPrefix = ordered.filter { mandatoryModifiers.contains($0) }.map(\.symbol).joined()
        let optionalPrefix = ordered.filter { optionalModifiers.contains($0) }.map { "\($0.symbol)?" }.joined()
        let modifierStr: String
        if !optionalPrefix.isEmpty {
            modifierStr = "\(mandatoryPrefix)[\(optionalPrefix)]"
        } else {
            modifierStr = mandatoryPrefix
        }
        return modifierStr + KeyLibrary.label(for: key)
    }

    enum CodingKeys: String, CodingKey {
        case mandatoryModifiers, optionalModifiers, key, modifiers
    }

    init() {}

    init(mandatoryModifiers: Set<ModifierKey> = [], optionalModifiers: Set<ModifierKey> = [], key: String = "") {
        self.mandatoryModifiers = mandatoryModifiers
        self.optionalModifiers = optionalModifiers
        self.key = key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        if let mandatory = try? container.decodeIfPresent(Set<ModifierKey>.self, forKey: .mandatoryModifiers) {
            self.mandatoryModifiers = mandatory
        } else if let oldMods = try? container.decodeIfPresent(Set<ModifierKey>.self, forKey: .modifiers) {
            self.mandatoryModifiers = oldMods
        }
        self.optionalModifiers = try container.decodeIfPresent(Set<ModifierKey>.self, forKey: .optionalModifiers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mandatoryModifiers, forKey: .mandatoryModifiers)
        try container.encode(optionalModifiers, forKey: .optionalModifiers)
        try container.encode(key, forKey: .key)
    }
}

// MARK: - Script Language

enum ScriptLanguage: String, CaseIterable, Identifiable, Codable {
    case appleScript = "AppleScript"
    case javaScript = "JavaScript"

    var id: String { rawValue }
}

// MARK: - String Trigger Match Mode

/// Defines how a typed string trigger matches against accumulated keystrokes.
enum StringTriggerMatchMode: String, CaseIterable, Identifiable, Codable {
    /// Fires when the typed buffer exactly equals the target string.
    case fullMatch = "Full Match"
    /// Fires when the typed buffer starts with the target string.
    case prefix = "Prefix"
    /// Fires when the target string appears anywhere in the typed buffer.
    case anyMatch = "Any Match"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .fullMatch: return "text.alignleft"
        case .prefix: return "text.insert"
        case .anyMatch: return "text.magnifyingglass"
        }
    }

    var helpText: String {
        switch self {
        case .fullMatch: return "Triggers when the typed text exactly matches the target string."
        case .prefix: return "Triggers when the typed text starts with the target string."
        case .anyMatch: return "Triggers when the target string appears anywhere in the typed text."
        }
    }
}

// MARK: - String Trigger Options

/// Configuration for a typed-string trigger (inspired by Keyboard Maestro).
/// Accumulates keystrokes and fires when the buffer matches the target string.
struct StringTriggerOptions: Equatable, Codable {
    /// The string to match against typed characters.
    var string: String = ""
    /// How the typed buffer is compared to the target string.
    var matchMode: StringTriggerMatchMode = .fullMatch
    /// Seconds of inactivity after which the accumulated buffer is cleared.
    var timeoutSeconds: Double = 2.0
    /// Whether to automatically clear the typed buffer after a successful match.
    var clearOnMatch: Bool = true
    /// Optional bundle identifier of the app to scope this trigger to.
    /// When non-empty, the trigger only accumulates and fires when that app is frontmost.
    var appBundleID: String = ""

    var isValid: Bool { !string.isEmpty }
}

// MARK: - Trigger

struct ManipulatorTrigger: Equatable, Codable {
    var steps: [KeyShortcut] = []
    var keyType: TriggerKeyType = .keyboard
    var simultaneous: SimultaneousTrigger?
    var triggerName: String = ""
    var anyKey: Bool = false
    var stringTrigger: StringTriggerOptions?
    var hotKey: HotKeyTriggerConfig? = nil

    var isValid: Bool {
        if !triggerName.isEmpty { return true }
        if anyKey { return true }
        if let sim = simultaneous, sim.isValid { return true }
        if let str = stringTrigger, str.isValid { return true }
        if keyType == .consumer || keyType == .pointing { return !steps.isEmpty }
        return !steps.isEmpty && steps.allSatisfy { !$0.key.isEmpty }
    }

    var displayLabel: String {
        if !triggerName.isEmpty { return "🔖 \(triggerName)" }
        if let str = stringTrigger, str.isValid {
            var label = "Type \"\(str.string)\""
            if str.matchMode != .fullMatch {
                label += " (\(str.matchMode.rawValue))"
            }
            if !str.appBundleID.isEmpty {
                label += " [in: \(str.appBundleID)]"
            }
            if !steps.isEmpty {
                label += " → \(steps.map(\.displayLabel).joined(separator: "  →  "))"
            }
            return label
        }
        if anyKey { return "Any key" }
        if keyType == .consumer {
            if let consumer = steps.first?.key, let cc = ConsumerKeyCode(rawValue: consumer) {
                return cc.label
            }
            return "Consumer key"
        }
        if keyType == .pointing {
            if let btn = steps.first?.key, let pb = PointingButton(rawValue: btn) {
                return pb.label
            }
            return "Mouse button"
        }
        if let sim = simultaneous, sim.isValid {
            return sim.keys.map(\.displayLabel).joined(separator: " + ") + " (chord)"
        }
        if steps.isEmpty { return "Not recorded" }

        var label = steps.map(\.displayLabel).joined(separator: "  →  ")

        // Annotate with hot‑key multi‑tap / hold info
        if let hotKey {
            if hotKey.tapCount > 1 {
                label = "\(hotKey.tapCount)×Tap: \(label)"
            }
            if hotKey.holdRequired {
                label += " (hold \(hotKey.holdThresholdMilliseconds)ms)"
            }
        }

        return label
    }

    enum CodingKeys: String, CodingKey {
        case steps, key, exactModifiers, keyType, simultaneous, anyKey, triggerName, stringTrigger, hotKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let steps = try? container.decode([KeyShortcut].self, forKey: .steps) {
            self.steps = steps
        } else if let key = try? container.decode(String.self, forKey: .key), !key.isEmpty {
            let modifiers = (try? container.decode(Set<ModifierKey>.self, forKey: .exactModifiers)) ?? []
            self.steps = [KeyShortcut(mandatoryModifiers: modifiers, key: key)]
        } else {
            self.steps = []
        }
        self.keyType = try container.decodeIfPresent(TriggerKeyType.self, forKey: .keyType) ?? .keyboard
        self.simultaneous = try container.decodeIfPresent(SimultaneousTrigger.self, forKey: .simultaneous)
        self.anyKey = try container.decodeIfPresent(Bool.self, forKey: .anyKey) ?? false
        self.triggerName = try container.decodeIfPresent(String.self, forKey: .triggerName) ?? ""
        self.stringTrigger = try container.decodeIfPresent(StringTriggerOptions.self, forKey: .stringTrigger)
        self.hotKey = try container.decodeIfPresent(HotKeyTriggerConfig.self, forKey: .hotKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(keyType, forKey: .keyType)
        try container.encodeIfPresent(simultaneous, forKey: .simultaneous)
        try container.encode(anyKey, forKey: .anyKey)
        try container.encode(triggerName, forKey: .triggerName)
        try container.encodeIfPresent(stringTrigger, forKey: .stringTrigger)
        try container.encodeIfPresent(hotKey, forKey: .hotKey)
    }
}

extension ManipulatorTrigger {
    init(steps: [KeyShortcut] = [], keyType: TriggerKeyType = .keyboard, simultaneous: SimultaneousTrigger? = nil, anyKey: Bool = false, triggerName: String = "", stringTrigger: StringTriggerOptions? = nil, hotKey: HotKeyTriggerConfig? = nil) {
        self.steps = steps
        self.keyType = keyType
        self.simultaneous = simultaneous
        self.anyKey = anyKey
        self.triggerName = triggerName
        self.stringTrigger = stringTrigger
        self.hotKey = hotKey
    }
}

// MARK: - Hot Key Trigger Config

/// Configuration for multi-tap / hold hot key behavior.
/// When applied to a manipulator trigger, the trigger waits for the specified number
/// of quick taps (within `tapTimeoutMilliseconds`) before activating.
/// Optionally, the final tap can require a hold beyond `holdThresholdMilliseconds`.
struct HotKeyTriggerConfig: Equatable, Codable {
    /// Minimum number of taps that must occur within `tapTimeoutMilliseconds` for the trigger to activate.
    /// Range: 1–5. 1 means normal single-tap behavior.
    var tapCount: Int = 2

    /// Maximum time (in milliseconds) allowed between taps for them to count as part of a multi-tap sequence.
    var tapTimeoutMilliseconds: Int = 400

    /// If true, the final tap must be held down (beyond `holdThresholdMilliseconds`)
    /// for the trigger to fire. During the hold phase the existing `ifHeldDown` / `afterKeyUp`
    /// fire modes apply to the held key.
    var holdRequired: Bool = false

    /// Minimum duration (in milliseconds) the final tap must be held when `holdRequired` is true.
    var holdThresholdMilliseconds: Int = 500

    var isValid: Bool {
        tapCount >= 1 && tapCount <= 5 && tapTimeoutMilliseconds > 0
    }
}

// MARK: - Conditions

enum ConditionKind: String, CaseIterable, Identifiable, Codable {
    case frontmostApp = "Frontmost App"
    case frontmostAppName = "App Name"
    case inputSource = "Input Source"
    case device = "Device"
    case variable = "Variable"
    case globalVariable = "Global Variable"
    case keyboardType = "Keyboard Type"
    case deviceExists = "Device Exists"
    case expression = "Expression"
    case eventChanged = "Event Changed"
    case window = "Window"
    case token = "Token"
    case namedClipboard = "Named Clipboard"
    case screen = "Screen"
    case runningCondition = "App Running"
    case pixelCondition = "Pixel Color"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .frontmostApp: return "app.badge.checkmark"
        case .frontmostAppName: return "textformat"
        case .inputSource: return "globe"
        case .device: return "keyboard"
        case .variable: return "function"
        case .globalVariable: return "tray.full"
        case .keyboardType: return "rectangle.3.group"
        case .deviceExists: return "keyboard.badge.plus"
        case .expression: return "x.squareroot"
        case .eventChanged: return "arrow.triangle.branch"
        case .window: return "macwindow"
        case .token: return "dollarsign.circle"
        case .namedClipboard: return "clipboard"
        case .screen: return "display"
        case .runningCondition: return "play.circle"
        case .pixelCondition: return "target"
        }
    }

    var placeholder: String {
        switch self {
        case .frontmostApp: return "com.apple.finder"
        case .frontmostAppName: return "Finder"
        case .inputSource: return "com.apple.keylayout.ABC"
        case .device: return "built-in | external | product-id"
        case .variable: return "Variable name"
        case .globalVariable: return "Variable name"
        case .keyboardType: return "ansi | iso | jis"
        case .deviceExists: return "built-in | external | product-id"
        case .expression: return "variable_name == \"value\""
        case .eventChanged: return "keyboard_type | device"
        case .window: return "title | minimized | hidden | visible"
        case .token: return "System:CurrentDate | FrontBrowser:URL | System:UserName"
        case .namedClipboard: return "Clipboard name"
        case .screen: return "primary | retina | 1920x1080"
        case .runningCondition: return "com.apple.Safari"
        case .pixelCondition: return "x, y"
        }
    }

    var helpText: String {
        switch self {
        case .frontmostApp: return "Bundle identifier of the active app, e.g. com.apple.Safari."
        case .frontmostAppName: return "Display name of the active app, e.g. Safari."
        case .inputSource: return "Input source identifier, e.g. com.apple.keylayout.ABC."
        case .device: return "Use 'built-in', 'external', or a numeric product ID."
        case .variable: return "Name of a variable set by another manipulator."
        case .globalVariable: return "Persistent variable that survives across engine restarts."
        case .keyboardType: return "ansi, iso, or jis."
        case .deviceExists: return "Check if a device is connected."
        case .expression: return "Simple expression: variable == value, variable != value."
        case .eventChanged: return "Check if the event changed due to keyboard/device switch."
        case .window: return "Match by frontmost window title, or window state: minimized, hidden, visible."
        case .token: return "Evaluate a token expression. Supported: System:CurrentDate, System:CurrentTime, System:UserName, FrontBrowser:URL, FrontBrowser:Title, Front:Application, Front:BundleID."
        case .namedClipboard: return "Check contents of a named clipboard; target is the clipboard name, value is the expected content."
        case .screen: return "Match by screen: \"primary\" for main display, \"retina\" for HiDPI, or a resolution like \"1920x1080\"."
        case .runningCondition: return "Check if a specific application is running (by bundle ID or display name)."
        case .pixelCondition: return "Match a pixel color at a screen coordinate. Set target to \"x,y\" and value to hex color like #FF0000."
        }
    }
}

enum ComparisonOp: String, CaseIterable, Identifiable, Codable {
    case isEqual = "is"
    case isNotEqual = "is not"
    case contains = "contains"
    case matches = "matches"

    var id: String { rawValue }
}

struct Condition: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: ConditionKind = .frontmostApp
    var op: ComparisonOp = .isEqual
    var target: String = ""
    var value: String = ""

    var summary: String {
        let opText = op.rawValue
        if kind == .variable || kind == .globalVariable || kind == .token || kind == .namedClipboard || kind == .pixelCondition {
            return "\(kind.rawValue) \(target.isEmpty ? "…" : target) \(opText) \(value.isEmpty ? "…" : value)"
        }
        return "\(kind.rawValue) \(opText) \(target.isEmpty ? "…" : target)"
    }
}

// MARK: - Action kinds

enum ActionKind: String, CaseIterable, Identifiable, Codable {
    case sendKey = "Send Key"
    case sendText = "Send Text"
    case setVariable = "Set Variable"
    case unsetVariable = "Unset Variable"
    case toggleVariable = "Toggle Variable"
    case runShell = "Run Shell"
    case openApp = "Open App"
    case openURL = "Open URL"
    case runShortcut = "Run Shortcut"
    case runAppleScript = "Run AppleScript"
    case delay = "Wait"
    case disable = "Disable Key"
    case consumerKey = "Consumer Key"
    case pointingButton = "Mouse Button"
    case mouseKey = "Mouse Key"
    case stickyModifier = "Sticky Modifier"
    case halt = "Halt"
    case holdDown = "Hold Down"
    case selectInputSource = "Select Input Source"
    case setNotification = "Show Notification"
    case fromEvent = "Mirror Event"
    case softwareFunction = "Software Function"
    case executeNamedTrigger = "Execute Named Trigger"
    case sendUserCommand = "Send User Command"
    case setGlobalVariable = "Set Global Variable"
    case unsetGlobalVariable = "Unset Global Variable"
    case showPalette = "Show Macro Palette"
    case hidePalette = "Hide Macro Palette"
    case getSelectedText = "Get Selected Text"
    case setClipboard = "Set Clipboard"
    case getClipboard = "Get Clipboard"
    case clearClipboard = "Clear Clipboard"

    // Application control
    case activateApp = "Activate App"
    case hideApp = "Hide App"
    case unhideApp = "Unhide App"
    case quitApp = "Quit App"
    case forceQuitApp = "Force Quit App"
    case activateLastApp = "Activate Last App"

    // Window management
    case windowAction = "Window Action"

    // System controls
    case lockScreen = "Lock Screen"
    case showDesktop = "Show Desktop"
    case missionControl = "Mission Control"
    case toggleDarkMode = "Toggle Dark Mode"
    case setVolume = "Set Volume"
    case muteSystem = "Toggle Mute"
    case emptyTrash = "Empty Trash"
    case getBatteryState = "Get Battery State"
    case getIPAddress = "Get IP Address"
    case toggleHiddenFiles = "Toggle Hidden Files"
    case logOut = "Log Out"
    case restartSystem = "Restart System"
    case shutdownSystem = "Shut Down System"

    // Text
    case speakText = "Speak Text"
    case transformText = "Transform Text"
    case calculateExpression = "Calculate Expression"

    // Variables
    case incrementVariable = "Increment Variable"
    case decrementVariable = "Decrement Variable"

    // Clipboard
    case appendClipboard = "Append to Clipboard"
    case pasteClipboard = "Paste Clipboard"

    // Web & files
    case httpRequest = "HTTP Request"
    case openFile = "Open File"
    case openFolder = "Open Folder"

    // Feedback
    case playSound = "Play Sound"
    case flashScreen = "Flash Screen"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .sendKey: return "keyboard"
        case .sendText: return "text.cursor"
        case .setVariable: return "equal.square"
        case .unsetVariable: return "xmark.square"
        case .toggleVariable: return "arrow.triangle.2.circlepath"
        case .runShell: return "terminal"
        case .openApp: return "app"
        case .openURL: return "link"
        case .runShortcut: return "bolt"
        case .runAppleScript: return "applescript"
        case .delay: return "clock"
        case .disable: return "nosign"
        case .consumerKey: return "play.square"
        case .pointingButton: return "cursorarrow.click"
        case .mouseKey: return "cursorarrow.motion"
        case .stickyModifier: return "pin"
        case .halt: return "stop"
        case .holdDown: return "timer"
        case .selectInputSource: return "globe"
        case .setNotification: return "bell"
        case .fromEvent: return "arrow.triangle.swap"
        case .softwareFunction: return "gearshape.2"
        case .executeNamedTrigger: return "tag"
        case .setGlobalVariable: return "tray.and.arrow.down"
        case .sendUserCommand: return "text.command"
        case .unsetGlobalVariable: return "tray.and.arrow.up"
        case .showPalette: return "rectangle.3.group"
        case .hidePalette: return "rectangle.3.group.fill"
        case .getSelectedText: return "doc.on.clipboard"
        case .setClipboard: return "doc.on.clipboard"
        case .getClipboard: return "doc.on.clipboard"
        case .clearClipboard: return "xmark.circle"
        case .activateApp: return "macwindow.on.rectangle"
        case .hideApp: return "eye.slash"
        case .unhideApp: return "eye"
        case .quitApp: return "xmark.app"
        case .forceQuitApp: return "exclamationmark.octagon"
        case .activateLastApp: return "arrow.uturn.backward.square"
        case .windowAction: return "macwindow"
        case .lockScreen: return "lock"
        case .showDesktop: return "menubar.dock.rectangle"
        case .missionControl: return "square.grid.3x2"
        case .toggleDarkMode: return "circle.lefthalf.filled"
        case .setVolume: return "speaker.wave.3"
        case .muteSystem: return "speaker.slash"
        case .emptyTrash: return "trash"
        case .getBatteryState: return "battery.75"
        case .getIPAddress: return "network"
        case .toggleHiddenFiles: return "eye.trianglebadge.exclamationmark"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .restartSystem: return "arrow.clockwise.circle"
        case .shutdownSystem: return "power.circle"
        case .speakText: return "speaker.wave.2.bubble.left"
        case .transformText: return "textformat"
        case .calculateExpression: return "function"
        case .incrementVariable: return "plus.square"
        case .decrementVariable: return "minus.square"
        case .appendClipboard: return "doc.badge.plus"
        case .pasteClipboard: return "doc.on.doc"
        case .httpRequest: return "arrow.up.arrow.down.circle"
        case .openFile: return "doc"
        case .openFolder: return "folder"
        case .playSound: return "music.note"
        case .flashScreen: return "bolt.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .sendKey: return "Press a single key"
        case .sendText: return "Type a string of text"
        case .setVariable: return "Save a value to a named variable"
        case .unsetVariable: return "Remove a named variable"
        case .toggleVariable: return "Flip a variable between true and false"
        case .runShell: return "Execute a shell command"
        case .openApp: return "Launch an application"
        case .openURL: return "Open a URL"
        case .runShortcut: return "Run a macOS Shortcut"
        case .runAppleScript: return "Run an AppleScript snippet"
        case .delay: return "Pause before the next step"
        case .disable: return "Swallow the keypress entirely"
        case .consumerKey: return "Send a media/consumer key event"
        case .pointingButton: return "Send a mouse button event"
        case .mouseKey: return "Move mouse or scroll"
        case .stickyModifier: return "Toggle a modifier as sticky"
        case .halt: return "Stop processing further actions"
        case .holdDown: return "Hold the key down for a duration"
        case .selectInputSource: return "Switch keyboard input source"
        case .setNotification: return "Show an on-screen notification"
        case .fromEvent: return "Mirror the original trigger event"
        case .softwareFunction: return "Run a system software function"
        case .executeNamedTrigger: return "Trigger a named manipulator by name"
        case .setGlobalVariable: return "Save a value to a persistent global variable"
        case .sendUserCommand: return "Execute a user-defined command"
        case .unsetGlobalVariable: return "Remove a persistent global variable"
        case .showPalette: return "Show the floating macro palette"
        case .hidePalette: return "Hide the floating macro palette"
        case .getSelectedText: return "Get selected text from frontmost app"
        case .setClipboard: return "Set clipboard to specific text"
        case .getClipboard: return "Get clipboard text content"
        case .clearClipboard: return "Clear the clipboard"
        case .activateApp: return "Bring an application to the foreground"
        case .hideApp: return "Hide an application"
        case .unhideApp: return "Unhide a hidden application"
        case .quitApp: return "Quit an application"
        case .forceQuitApp: return "Force-quit an application"
        case .activateLastApp: return "Switch to the previously active app"
        case .windowAction: return "Move, resize, snap, or close the frontmost window"
        case .lockScreen: return "Lock the screen"
        case .showDesktop: return "Show the desktop"
        case .missionControl: return "Activate Mission Control"
        case .toggleDarkMode: return "Toggle Dark/Light appearance"
        case .setVolume: return "Set system volume (0–100)"
        case .muteSystem: return "Toggle system audio mute"
        case .emptyTrash: return "Empty the Trash"
        case .getBatteryState: return "Store battery level and charging state in variables"
        case .getIPAddress: return "Store the current IP address in a variable"
        case .toggleHiddenFiles: return "Toggle hidden file visibility in Finder"
        case .logOut: return "Log out the current user"
        case .restartSystem: return "Restart the Mac"
        case .shutdownSystem: return "Shut down the Mac"
        case .speakText: return "Speak text using text-to-speech"
        case .transformText: return "Transform the clipboard text (case, encoding, …)"
        case .calculateExpression: return "Evaluate a math expression into a variable"
        case .incrementVariable: return "Increment a numeric variable"
        case .decrementVariable: return "Decrement a numeric variable"
        case .appendClipboard: return "Append text to the clipboard"
        case .pasteClipboard: return "Paste the current clipboard (⌘V)"
        case .httpRequest: return "Make an HTTP GET request, store the response"
        case .openFile: return "Open a file with its default app"
        case .openFolder: return "Reveal a folder in Finder"
        case .playSound: return "Play a system sound or sound file"
        case .flashScreen: return "Flash the screen with a brief overlay"
        }
    }
}

// MARK: - Software function

enum SoftwareFunctionKind: String, CaseIterable, Identifiable, Codable {
    case doubleClick = "Double Click"
    case sleepSystem = "Sleep System"
    case setCursorPosition = "Set Cursor Position"
    case openApplication = "Open Application"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .doubleClick: return "cursorarrow.click.2"
        case .sleepSystem: return "moon.zzz"
        case .setCursorPosition: return "move.3d"
        case .openApplication: return "app.badge"
        }
    }
}

// MARK: - Window action

enum WindowActionKind: String, CaseIterable, Identifiable, Codable {
    case leftHalf = "Left Half"
    case rightHalf = "Right Half"
    case topHalf = "Top Half"
    case bottomHalf = "Bottom Half"
    case topLeftQuarter = "Top Left Quarter"
    case topRightQuarter = "Top Right Quarter"
    case bottomLeftQuarter = "Bottom Left Quarter"
    case bottomRightQuarter = "Bottom Right Quarter"
    case center = "Center"
    case maximize = "Maximize (Fill Screen)"
    case minimize = "Minimize"
    case close = "Close"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleft.filled"
        case .topRightQuarter: return "rectangle.inset.topright.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleft.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomright.filled"
        case .center: return "rectangle.center.inset.filled"
        case .maximize: return "rectangle.inset.filled"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .close: return "xmark.circle"
        }
    }
}

// MARK: - Text transform

enum TextTransformKind: String, CaseIterable, Identifiable, Codable {
    case upperCase = "UPPERCASE"
    case lowerCase = "lowercase"
    case capitalize = "Capitalize Words"
    case camelCase = "camelCase"
    case pascalCase = "PascalCase"
    case snakeCase = "snake_case"
    case kebabCase = "kebab-case"
    case trimWhitespace = "Trim Whitespace"
    case slugify = "Slugify"
    case encodeBase64 = "Encode Base64"
    case decodeBase64 = "Decode Base64"
    case encodeURL = "URL Encode"
    case decodeURL = "URL Decode"

    var id: String { rawValue }
}

// MARK: - Mouse key action

struct MouseKeyAction: Equatable, Codable {
    var x: Int = 0
    var y: Int = 0
    var verticalWheel: Int = 0
    var horizontalWheel: Int = 0
    var speedMultiplier: Double = 1.0
}

// MARK: - Sticky modifier

enum StickyModifierKind: String, CaseIterable, Identifiable, Codable {
    case toggle
    case on
    case off

    var id: String { rawValue }
}

struct StickyModifierAction: Equatable, Codable {
    var modifier: ModifierKey = .command
    var kind: StickyModifierKind = .toggle
}

// MARK: - Action fire mode

enum ActionFireMode: String, CaseIterable, Identifiable, Codable {
    case onKeyDown = "On Key Down"
    case ifAlone = "If Tapped"
    case ifHeldDown = "If Held Down"
    case ifHeldDownInvoked = "If Held (After Delay)"
    case ifHeldDownCanceled = "If Held (Canceled)"
    case afterKeyUp = "After Key Up"
    case ifOtherKeyPressed = "If Other Key Pressed"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .onKeyDown: return "arrow.down.circle"
        case .ifAlone: return "hand.tap"
        case .ifHeldDown: return "hand.point.up.left"
        case .ifHeldDownInvoked: return "clock.badge.checkmark"
        case .ifHeldDownCanceled: return "clock.badge.xmark"
        case .afterKeyUp: return "arrow.up.circle"
        case .ifOtherKeyPressed: return "arrow.triangle.branch"
        }
    }

    var helpText: String {
        switch self {
        case .onKeyDown: return "Fires immediately when the trigger key is pressed."
        case .ifAlone: return "Fires only if the trigger key is released within the to_if_alone_timeout."
        case .ifHeldDown: return "Fires once the key has been held longer than the held-down threshold."
        case .ifHeldDownInvoked: return "Fires after to_delay_action_delay if the key is still held uninterrupted."
        case .ifHeldDownCanceled: return "Fires if another key is pressed before the delay elapses."
        case .afterKeyUp: return "Fires when the trigger key is released."
        case .ifOtherKeyPressed: return "Fires when another key is pressed while the trigger is held."
        }
    }
}

// MARK: - Copy-on-Write Action

/// Reference-type backing for the Action struct to avoid copying ~400 bytes
/// of properties when `[Action]` arrays are filtered, sorted, or snapshotted.
/// The Action struct itself remains a value type with the same public API.
final class ActionStorage: Codable, Equatable {
    var id = UUID()
    var kind: ActionKind = .sendKey
    var fireMode: ActionFireMode = .onKeyDown

    var toKey: String = ""
    var toModifiers: Set<ModifierKey> = []

    var consumerKey: ConsumerKeyCode? = nil
    var pointingButton: PointingButton? = nil

    var mouseKey: MouseKeyAction = .init()
    var stickyModifier: StickyModifierAction = .init()
    var softwareFunction: SoftwareFunctionKind = .doubleClick
    var appPath: String = ""
    var inputSourceID: String = ""
    var notificationMessage: String = ""

    var text: String = ""

    var variableName: String = ""
    var variableValue: String = ""
    var toggleInitialState: Bool = true

    var shellCommand: String = ""

    var appBundleID: String = ""
    var appName: String = ""

    var urlString: String = ""

    var shortcutName: String = ""

    var scriptBody: String = ""

    var namedTrigger: String = ""
    var userCommand: String = ""
    var delaySeconds: Double = 0.1
    var holdDownMilliseconds: Int = 0
    var cursorPositionX: Int = 0
    var cursorPositionY: Int = 0

    var isLazy: Bool = false
    var isRepeatEnabled: Bool? = nil

    var windowActionKind: WindowActionKind? = nil
    var textTransformKind: TextTransformKind? = nil
    var numberValue: Int? = nil

    var tapCount: Int = 1

    var actionConditions: [Condition] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .sendKey
        fireMode = try container.decodeIfPresent(ActionFireMode.self, forKey: .fireMode) ?? .onKeyDown
        toKey = try container.decodeIfPresent(String.self, forKey: .toKey) ?? ""
        toModifiers = try container.decodeIfPresent(Set<ModifierKey>.self, forKey: .toModifiers) ?? []
        consumerKey = try container.decodeIfPresent(ConsumerKeyCode.self, forKey: .consumerKey)
        pointingButton = try container.decodeIfPresent(PointingButton.self, forKey: .pointingButton)
        mouseKey = try container.decodeIfPresent(MouseKeyAction.self, forKey: .mouseKey) ?? .init()
        stickyModifier = try container.decodeIfPresent(StickyModifierAction.self, forKey: .stickyModifier) ?? .init()
        softwareFunction = try container.decodeIfPresent(SoftwareFunctionKind.self, forKey: .softwareFunction) ?? .doubleClick
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath) ?? ""
        inputSourceID = try container.decodeIfPresent(String.self, forKey: .inputSourceID) ?? ""
        notificationMessage = try container.decodeIfPresent(String.self, forKey: .notificationMessage) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        variableName = try container.decodeIfPresent(String.self, forKey: .variableName) ?? ""
        variableValue = try container.decodeIfPresent(String.self, forKey: .variableValue) ?? ""
        toggleInitialState = try container.decodeIfPresent(Bool.self, forKey: .toggleInitialState) ?? true
        shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID) ?? ""
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? ""
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString) ?? ""
        shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName) ?? ""
        scriptBody = try container.decodeIfPresent(String.self, forKey: .scriptBody) ?? ""
        namedTrigger = try container.decodeIfPresent(String.self, forKey: .namedTrigger) ?? ""
        userCommand = try container.decodeIfPresent(String.self, forKey: .userCommand) ?? ""
        delaySeconds = try container.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 0.1
        holdDownMilliseconds = try container.decodeIfPresent(Int.self, forKey: .holdDownMilliseconds) ?? 0
        cursorPositionX = try container.decodeIfPresent(Int.self, forKey: .cursorPositionX) ?? 0
        cursorPositionY = try container.decodeIfPresent(Int.self, forKey: .cursorPositionY) ?? 0
        isLazy = try container.decodeIfPresent(Bool.self, forKey: .isLazy) ?? false
        isRepeatEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRepeatEnabled)
        windowActionKind = try container.decodeIfPresent(WindowActionKind.self, forKey: .windowActionKind)
        textTransformKind = try container.decodeIfPresent(TextTransformKind.self, forKey: .textTransformKind)
        numberValue = try container.decodeIfPresent(Int.self, forKey: .numberValue)
        tapCount = try container.decodeIfPresent(Int.self, forKey: .tapCount) ?? 1
        actionConditions = try container.decodeIfPresent([Condition].self, forKey: .actionConditions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(fireMode, forKey: .fireMode)
        try container.encode(toKey, forKey: .toKey)
        try container.encode(toModifiers, forKey: .toModifiers)
        try container.encodeIfPresent(consumerKey, forKey: .consumerKey)
        try container.encodeIfPresent(pointingButton, forKey: .pointingButton)
        try container.encode(mouseKey, forKey: .mouseKey)
        try container.encode(stickyModifier, forKey: .stickyModifier)
        try container.encode(softwareFunction, forKey: .softwareFunction)
        try container.encode(appPath, forKey: .appPath)
        try container.encode(inputSourceID, forKey: .inputSourceID)
        try container.encode(notificationMessage, forKey: .notificationMessage)
        try container.encode(text, forKey: .text)
        try container.encode(variableName, forKey: .variableName)
        try container.encode(variableValue, forKey: .variableValue)
        try container.encode(toggleInitialState, forKey: .toggleInitialState)
        try container.encode(shellCommand, forKey: .shellCommand)
        try container.encode(appBundleID, forKey: .appBundleID)
        try container.encode(appName, forKey: .appName)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(shortcutName, forKey: .shortcutName)
        try container.encode(scriptBody, forKey: .scriptBody)
        try container.encode(namedTrigger, forKey: .namedTrigger)
        try container.encode(userCommand, forKey: .userCommand)
        try container.encode(delaySeconds, forKey: .delaySeconds)
        try container.encode(holdDownMilliseconds, forKey: .holdDownMilliseconds)
        try container.encode(cursorPositionX, forKey: .cursorPositionX)
        try container.encode(cursorPositionY, forKey: .cursorPositionY)
        try container.encode(isLazy, forKey: .isLazy)
        try container.encodeIfPresent(isRepeatEnabled, forKey: .isRepeatEnabled)
        try container.encodeIfPresent(windowActionKind, forKey: .windowActionKind)
        try container.encodeIfPresent(textTransformKind, forKey: .textTransformKind)
        try container.encodeIfPresent(numberValue, forKey: .numberValue)
        try container.encode(tapCount, forKey: .tapCount)
        try container.encode(actionConditions, forKey: .actionConditions)
    }

    static func == (lhs: ActionStorage, rhs: ActionStorage) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.kind == rhs.kind else { return false }
        guard lhs.fireMode == rhs.fireMode else { return false }
        guard lhs.toKey == rhs.toKey else { return false }
        guard lhs.toModifiers == rhs.toModifiers else { return false }
        guard lhs.consumerKey == rhs.consumerKey else { return false }
        guard lhs.pointingButton == rhs.pointingButton else { return false }
        guard lhs.mouseKey == rhs.mouseKey else { return false }
        guard lhs.stickyModifier == rhs.stickyModifier else { return false }
        guard lhs.softwareFunction == rhs.softwareFunction else { return false }
        guard lhs.appPath == rhs.appPath else { return false }
        guard lhs.inputSourceID == rhs.inputSourceID else { return false }
        guard lhs.notificationMessage == rhs.notificationMessage else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.variableName == rhs.variableName else { return false }
        guard lhs.variableValue == rhs.variableValue else { return false }
        guard lhs.toggleInitialState == rhs.toggleInitialState else { return false }
        guard lhs.shellCommand == rhs.shellCommand else { return false }
        guard lhs.appBundleID == rhs.appBundleID else { return false }
        guard lhs.appName == rhs.appName else { return false }
        guard lhs.urlString == rhs.urlString else { return false }
        guard lhs.shortcutName == rhs.shortcutName else { return false }
        guard lhs.scriptBody == rhs.scriptBody else { return false }
        guard lhs.namedTrigger == rhs.namedTrigger else { return false }
        guard lhs.userCommand == rhs.userCommand else { return false }
        guard lhs.delaySeconds == rhs.delaySeconds else { return false }
        guard lhs.holdDownMilliseconds == rhs.holdDownMilliseconds else { return false }
        guard lhs.cursorPositionX == rhs.cursorPositionX else { return false }
        guard lhs.cursorPositionY == rhs.cursorPositionY else { return false }
        guard lhs.isLazy == rhs.isLazy else { return false }
        guard lhs.isRepeatEnabled == rhs.isRepeatEnabled else { return false }
        guard lhs.windowActionKind == rhs.windowActionKind else { return false }
        guard lhs.textTransformKind == rhs.textTransformKind else { return false }
        guard lhs.numberValue == rhs.numberValue else { return false }
        guard lhs.tapCount == rhs.tapCount else { return false }
        guard lhs.actionConditions == rhs.actionConditions else { return false }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, fireMode, toKey, toModifiers, consumerKey, pointingButton
        case mouseKey, stickyModifier, softwareFunction, appPath, inputSourceID
        case notificationMessage, text, variableName, variableValue, toggleInitialState
        case shellCommand, appBundleID, appName, urlString, shortcutName, scriptBody
        case namedTrigger, userCommand, delaySeconds, holdDownMilliseconds
        case cursorPositionX, cursorPositionY, isLazy, isRepeatEnabled
        case windowActionKind, textTransformKind, numberValue, tapCount, actionConditions
    }
}

/// Public value-type Action with COW backing.
/// Copying an Action only copies the 8-byte reference to the storage,
/// not the full ~400 bytes of properties.
struct Action: Identifiable, Equatable, Codable {
    private var _storage = ActionStorage()

    private mutating func copyIfNeeded() {
        if !isKnownUniquelyReferenced(&_storage) {
            let old = _storage
            _storage = ActionStorage()
            // Copy all properties
            _storage.id = old.id
            _storage.kind = old.kind
            _storage.fireMode = old.fireMode
            _storage.toKey = old.toKey
            _storage.toModifiers = old.toModifiers
            _storage.consumerKey = old.consumerKey
            _storage.pointingButton = old.pointingButton
            _storage.mouseKey = old.mouseKey
            _storage.stickyModifier = old.stickyModifier
            _storage.softwareFunction = old.softwareFunction
            _storage.appPath = old.appPath
            _storage.inputSourceID = old.inputSourceID
            _storage.notificationMessage = old.notificationMessage
            _storage.text = old.text
            _storage.variableName = old.variableName
            _storage.variableValue = old.variableValue
            _storage.toggleInitialState = old.toggleInitialState
            _storage.shellCommand = old.shellCommand
            _storage.appBundleID = old.appBundleID
            _storage.appName = old.appName
            _storage.urlString = old.urlString
            _storage.shortcutName = old.shortcutName
            _storage.scriptBody = old.scriptBody
            _storage.namedTrigger = old.namedTrigger
            _storage.userCommand = old.userCommand
            _storage.delaySeconds = old.delaySeconds
            _storage.holdDownMilliseconds = old.holdDownMilliseconds
            _storage.cursorPositionX = old.cursorPositionX
            _storage.cursorPositionY = old.cursorPositionY
            _storage.isLazy = old.isLazy
            _storage.isRepeatEnabled = old.isRepeatEnabled
            _storage.windowActionKind = old.windowActionKind
            _storage.textTransformKind = old.textTransformKind
            _storage.numberValue = old.numberValue
            _storage.tapCount = old.tapCount
            _storage.actionConditions = old.actionConditions
        }
    }

    var id: UUID {
        get { _storage.id }
        set { copyIfNeeded(); _storage.id = newValue }
    }

    var kind: ActionKind {
        get { _storage.kind }
        set { copyIfNeeded(); _storage.kind = newValue }
    }

    var fireMode: ActionFireMode {
        get { _storage.fireMode }
        set { copyIfNeeded(); _storage.fireMode = newValue }
    }

    var toKey: String {
        get { _storage.toKey }
        set { copyIfNeeded(); _storage.toKey = newValue }
    }

    var toModifiers: Set<ModifierKey> {
        get { _storage.toModifiers }
        set { copyIfNeeded(); _storage.toModifiers = newValue }
    }

    var consumerKey: ConsumerKeyCode? {
        get { _storage.consumerKey }
        set { copyIfNeeded(); _storage.consumerKey = newValue }
    }

    var pointingButton: PointingButton? {
        get { _storage.pointingButton }
        set { copyIfNeeded(); _storage.pointingButton = newValue }
    }

    var mouseKey: MouseKeyAction {
        get { _storage.mouseKey }
        set { copyIfNeeded(); _storage.mouseKey = newValue }
    }

    var stickyModifier: StickyModifierAction {
        get { _storage.stickyModifier }
        set { copyIfNeeded(); _storage.stickyModifier = newValue }
    }

    var softwareFunction: SoftwareFunctionKind {
        get { _storage.softwareFunction }
        set { copyIfNeeded(); _storage.softwareFunction = newValue }
    }

    var appPath: String {
        get { _storage.appPath }
        set { copyIfNeeded(); _storage.appPath = newValue }
    }

    var inputSourceID: String {
        get { _storage.inputSourceID }
        set { copyIfNeeded(); _storage.inputSourceID = newValue }
    }

    var notificationMessage: String {
        get { _storage.notificationMessage }
        set { copyIfNeeded(); _storage.notificationMessage = newValue }
    }

    var text: String {
        get { _storage.text }
        set { copyIfNeeded(); _storage.text = newValue }
    }

    var variableName: String {
        get { _storage.variableName }
        set { copyIfNeeded(); _storage.variableName = newValue }
    }

    var variableValue: String {
        get { _storage.variableValue }
        set { copyIfNeeded(); _storage.variableValue = newValue }
    }

    var toggleInitialState: Bool {
        get { _storage.toggleInitialState }
        set { copyIfNeeded(); _storage.toggleInitialState = newValue }
    }

    var shellCommand: String {
        get { _storage.shellCommand }
        set { copyIfNeeded(); _storage.shellCommand = newValue }
    }

    var appBundleID: String {
        get { _storage.appBundleID }
        set { copyIfNeeded(); _storage.appBundleID = newValue }
    }

    var appName: String {
        get { _storage.appName }
        set { copyIfNeeded(); _storage.appName = newValue }
    }

    var urlString: String {
        get { _storage.urlString }
        set { copyIfNeeded(); _storage.urlString = newValue }
    }

    var shortcutName: String {
        get { _storage.shortcutName }
        set { copyIfNeeded(); _storage.shortcutName = newValue }
    }

    var scriptBody: String {
        get { _storage.scriptBody }
        set { copyIfNeeded(); _storage.scriptBody = newValue }
    }

    var namedTrigger: String {
        get { _storage.namedTrigger }
        set { copyIfNeeded(); _storage.namedTrigger = newValue }
    }

    var userCommand: String {
        get { _storage.userCommand }
        set { copyIfNeeded(); _storage.userCommand = newValue }
    }

    var delaySeconds: Double {
        get { _storage.delaySeconds }
        set { copyIfNeeded(); _storage.delaySeconds = newValue }
    }

    var holdDownMilliseconds: Int {
        get { _storage.holdDownMilliseconds }
        set { copyIfNeeded(); _storage.holdDownMilliseconds = newValue }
    }

    var cursorPositionX: Int {
        get { _storage.cursorPositionX }
        set { copyIfNeeded(); _storage.cursorPositionX = newValue }
    }

    var cursorPositionY: Int {
        get { _storage.cursorPositionY }
        set { copyIfNeeded(); _storage.cursorPositionY = newValue }
    }

    var isLazy: Bool {
        get { _storage.isLazy }
        set { copyIfNeeded(); _storage.isLazy = newValue }
    }

    var isRepeatEnabled: Bool? {
        get { _storage.isRepeatEnabled }
        set { copyIfNeeded(); _storage.isRepeatEnabled = newValue }
    }

    var windowActionKind: WindowActionKind? {
        get { _storage.windowActionKind }
        set { copyIfNeeded(); _storage.windowActionKind = newValue }
    }

    var textTransformKind: TextTransformKind? {
        get { _storage.textTransformKind }
        set { copyIfNeeded(); _storage.textTransformKind = newValue }
    }

    var numberValue: Int? {
        get { _storage.numberValue }
        set { copyIfNeeded(); _storage.numberValue = newValue }
    }

    var tapCount: Int {
        get { _storage.tapCount }
        set { copyIfNeeded(); _storage.tapCount = newValue }
    }

    var actionConditions: [Condition] {
        get { _storage.actionConditions }
        set { copyIfNeeded(); _storage.actionConditions = newValue }
    }

    // MARK: - Initializers

    init() {}

    init(kind: ActionKind = .sendKey, fireMode: ActionFireMode = .onKeyDown, toKey: String = "", toModifiers: Set<ModifierKey> = [], consumerKey: ConsumerKeyCode? = nil, pointingButton: PointingButton? = nil, mouseKey: MouseKeyAction = .init(), stickyModifier: StickyModifierAction = .init(), softwareFunction: SoftwareFunctionKind = .doubleClick, appPath: String = "", inputSourceID: String = "", notificationMessage: String = "", text: String = "", variableName: String = "", variableValue: String = "", toggleInitialState: Bool = true, shellCommand: String = "", appBundleID: String = "", appName: String = "", urlString: String = "", shortcutName: String = "", scriptBody: String = "", namedTrigger: String = "", userCommand: String = "", delaySeconds: Double = 0.1, holdDownMilliseconds: Int = 0, cursorPositionX: Int = 0, cursorPositionY: Int = 0, isLazy: Bool = false, isRepeatEnabled: Bool? = nil, windowActionKind: WindowActionKind? = nil, textTransformKind: TextTransformKind? = nil, numberValue: Int? = nil, tapCount: Int = 1, actionConditions: [Condition] = []) {
        _storage = ActionStorage()
        _storage.id = UUID()
        _storage.kind = kind
        _storage.fireMode = fireMode
        _storage.toKey = toKey
        _storage.toModifiers = toModifiers
        _storage.consumerKey = consumerKey
        _storage.pointingButton = pointingButton
        _storage.mouseKey = mouseKey
        _storage.stickyModifier = stickyModifier
        _storage.softwareFunction = softwareFunction
        _storage.appPath = appPath
        _storage.inputSourceID = inputSourceID
        _storage.notificationMessage = notificationMessage
        _storage.text = text
        _storage.variableName = variableName
        _storage.variableValue = variableValue
        _storage.toggleInitialState = toggleInitialState
        _storage.shellCommand = shellCommand
        _storage.appBundleID = appBundleID
        _storage.appName = appName
        _storage.urlString = urlString
        _storage.shortcutName = shortcutName
        _storage.scriptBody = scriptBody
        _storage.namedTrigger = namedTrigger
        _storage.userCommand = userCommand
        _storage.delaySeconds = delaySeconds
        _storage.holdDownMilliseconds = holdDownMilliseconds
        _storage.cursorPositionX = cursorPositionX
        _storage.cursorPositionY = cursorPositionY
        _storage.isLazy = isLazy
        _storage.isRepeatEnabled = isRepeatEnabled
        _storage.windowActionKind = windowActionKind
        _storage.textTransformKind = textTransformKind
        _storage.numberValue = numberValue
        _storage.tapCount = tapCount
        _storage.actionConditions = actionConditions
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        _storage = try ActionStorage(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try _storage.encode(to: encoder)
    }

    // MARK: - Equatable

    static func == (lhs: Action, rhs: Action) -> Bool {
        lhs._storage == rhs._storage
    }

    // MARK: - Duplicate

    /// Create a deep copy of this action (new storage, same values, new ID).
    func deepCopy() -> Action {
        var copy = Action()
        // Deep copy all properties into fresh storage
        let s = copy._storage
        s.id = UUID()
        s.kind = _storage.kind
        s.fireMode = _storage.fireMode
        s.toKey = _storage.toKey
        s.toModifiers = _storage.toModifiers
        s.consumerKey = _storage.consumerKey
        s.pointingButton = _storage.pointingButton
        s.mouseKey = _storage.mouseKey
        s.stickyModifier = _storage.stickyModifier
        s.softwareFunction = _storage.softwareFunction
        s.appPath = _storage.appPath
        s.inputSourceID = _storage.inputSourceID
        s.notificationMessage = _storage.notificationMessage
        s.text = _storage.text
        s.variableName = _storage.variableName
        s.variableValue = _storage.variableValue
        s.toggleInitialState = _storage.toggleInitialState
        s.shellCommand = _storage.shellCommand
        s.appBundleID = _storage.appBundleID
        s.appName = _storage.appName
        s.urlString = _storage.urlString
        s.shortcutName = _storage.shortcutName
        s.scriptBody = _storage.scriptBody
        s.namedTrigger = _storage.namedTrigger
        s.userCommand = _storage.userCommand
        s.delaySeconds = _storage.delaySeconds
        s.holdDownMilliseconds = _storage.holdDownMilliseconds
        s.cursorPositionX = _storage.cursorPositionX
        s.cursorPositionY = _storage.cursorPositionY
        s.isLazy = _storage.isLazy
        s.isRepeatEnabled = _storage.isRepeatEnabled
        s.windowActionKind = _storage.windowActionKind
        s.textTransformKind = _storage.textTransformKind
        s.numberValue = _storage.numberValue
        s.tapCount = _storage.tapCount
        s.actionConditions = _storage.actionConditions
        return copy
    }

    var isConfigured: Bool {
        switch kind {
        case .sendKey: return !toKey.isEmpty
        case .sendText: return !text.isEmpty
        case .consumerKey: return consumerKey != nil
        case .pointingButton: return pointingButton != nil
        case .mouseKey: return mouseKey.x != 0 || mouseKey.y != 0 || mouseKey.verticalWheel != 0 || mouseKey.horizontalWheel != 0
        case .stickyModifier: return true
        case .halt: return true
        case .holdDown: return !toKey.isEmpty && holdDownMilliseconds > 0
        case .selectInputSource: return !inputSourceID.isEmpty
        case .setNotification: return !notificationMessage.isEmpty
        case .fromEvent: return true
        case .softwareFunction:
            if softwareFunction == .openApplication {
                return !appPath.isEmpty
            }
            if softwareFunction == .setCursorPosition {
                return cursorPositionX != 0 || cursorPositionY != 0
            }
            return true
        case .setVariable: return !variableName.isEmpty
        case .unsetVariable: return !variableName.isEmpty
        case .toggleVariable: return !variableName.isEmpty
        case .runShell: return !shellCommand.isEmpty
        case .openApp: return !appBundleID.isEmpty || !appName.isEmpty
        case .openURL: return !urlString.isEmpty
        case .runShortcut: return !shortcutName.isEmpty
        case .runAppleScript: return !scriptBody.isEmpty
        case .executeNamedTrigger: return !namedTrigger.isEmpty
        case .sendUserCommand: return !userCommand.isEmpty
        case .setGlobalVariable: return !variableName.isEmpty
        case .unsetGlobalVariable: return !variableName.isEmpty
        case .showPalette: return true
        case .hidePalette: return true
        case .getSelectedText: return true
        case .setClipboard: return !text.isEmpty
        case .getClipboard: return true
        case .clearClipboard: return true
        case .activateApp, .hideApp, .unhideApp, .quitApp, .forceQuitApp:
            return !appBundleID.isEmpty || !appName.isEmpty
        case .activateLastApp: return true
        case .windowAction: return true
        case .lockScreen, .showDesktop, .missionControl, .toggleDarkMode,
             .muteSystem, .emptyTrash, .getBatteryState, .getIPAddress,
             .toggleHiddenFiles, .logOut, .restartSystem, .shutdownSystem,
             .pasteClipboard, .flashScreen, .transformText:
            return true
        case .setVolume: return true
        case .speakText: return !text.isEmpty
        case .calculateExpression: return !variableName.isEmpty && !variableValue.isEmpty
        case .incrementVariable, .decrementVariable: return !variableName.isEmpty
        case .appendClipboard: return !text.isEmpty
        case .httpRequest: return !urlString.isEmpty
        case .openFile, .openFolder: return !appPath.isEmpty
        case .playSound: return !text.isEmpty
        case .delay: return delaySeconds > 0
        case .disable: return true
        }
    }

    var summary: String {
        var prefix = ""
        if fireMode != .onKeyDown {
            prefix += "[\(fireMode.rawValue)] "
        }
        if tapCount > 1 {
            prefix += "\(tapCount)×Tap "
        }
        if isLazy { return prefix + "[Lazy] " + bodySummary }
        return prefix + bodySummary
    }

    private var bodySummary: String {
        switch kind {
        case .sendKey:
            let mods = toModifiers.sorted(by: { lhs, rhs in
                let order: [ModifierKey] = [.control, .option, .shift, .command, .capsLock, .fn]
                return order.firstIndex(of: lhs) ?? 0 < order.firstIndex(of: rhs) ?? 0
            })
            let prefix = mods.map(\.symbol).joined()
            return toKey.isEmpty ? "Press a key" : "\(prefix)\(KeyLibrary.label(for: toKey))"
        case .consumerKey:
            return consumerKey?.label ?? "Send consumer key"
        case .pointingButton:
            return pointingButton?.label ?? "Send mouse button"
        case .mouseKey:
            var parts: [String] = []
            if mouseKey.x != 0 || mouseKey.y != 0 { parts.append("(\(mouseKey.x), \(mouseKey.y))") }
            if mouseKey.verticalWheel != 0 { parts.append("scroll v:\(mouseKey.verticalWheel)") }
            if mouseKey.horizontalWheel != 0 { parts.append("scroll h:\(mouseKey.horizontalWheel)") }
            return parts.isEmpty ? "Move mouse" : parts.joined(separator: " ")
        case .stickyModifier:
            return "Sticky \(stickyModifier.modifier.longName) (\(stickyModifier.kind.rawValue))"
        case .halt:
            return "Halt further actions"
        case .holdDown:
            return "Hold \(KeyLibrary.label(for: toKey)) for \(holdDownMilliseconds)ms"
        case .selectInputSource:
            return inputSourceID.isEmpty ? "Select input source" : "Input: \(inputSourceID)"
        case .setNotification:
            return notificationMessage.isEmpty ? "Show notification" : "Notify: \(notificationMessage.prefix(28))"
        case .fromEvent:
            return "Mirror original event"
        case .softwareFunction:
            if softwareFunction == .openApplication {
                return appPath.isEmpty ? "Open App" : "Open \(appPath)"
            }
            if softwareFunction == .setCursorPosition {
                return "Cursor to (\(cursorPositionX), \(cursorPositionY))"
            }
            return "Software: \(softwareFunction.rawValue)"
        case .sendText:
            return text.isEmpty ? "Type text" : "Type \"\(text.prefix(28))\(text.count > 28 ? "…" : "")\""
        case .setVariable:
            return variableName.isEmpty ? "Set a variable" : "Set \(variableName) = \(variableValue.isEmpty ? "true" : variableValue)"
        case .unsetVariable:
            return variableName.isEmpty ? "Unset a variable" : "Unset \(variableName)"
        case .toggleVariable:
            return variableName.isEmpty ? "Toggle a variable" : "Toggle \(variableName)"
        case .runShell:
            return shellCommand.isEmpty ? "Run a shell command" : "Run \(shellCommand.prefix(28))"
        case .openApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Open an app" : "Open \(label)"
        case .openURL:
            return urlString.isEmpty ? "Open a URL" : "Open \(urlString.prefix(28))"
        case .runShortcut:
            return shortcutName.isEmpty ? "Run a Shortcut" : "Run Shortcut \"\(shortcutName)\""
        case .runAppleScript:
            return scriptBody.isEmpty ? "AppleScript" : "AppleScript (\(scriptBody.count) chars)"
        case .executeNamedTrigger:
            return namedTrigger.isEmpty ? "Execute named trigger" : "Trigger \"\(namedTrigger)\""
        case .sendUserCommand:
            return userCommand.isEmpty ? "Send user command" : "Cmd: \(userCommand.prefix(28))\(userCommand.count > 28 ? "\u{2026}" : "")"
        case .showPalette:
            return "Show macro palette"
        case .hidePalette:
            return "Hide macro palette"
        case .getSelectedText:
            return "Get selected text"
        case .setClipboard:
            return text.isEmpty ? "Set clipboard" : "Set clipboard: \(text.prefix(28))"
        case .getClipboard:
            return "Get clipboard text"
        case .clearClipboard:
            return "Clear clipboard"
        case .setGlobalVariable:
            return variableName.isEmpty ? "Set a global variable" : "Set global \(variableName) = \(variableValue.isEmpty ? "true" : variableValue)"
        case .unsetGlobalVariable:
            return variableName.isEmpty ? "Unset a global variable" : "Unset global \(variableName)"
        case .delay:
            return String(format: "Wait %.2fs", delaySeconds)
        case .disable:
            return "Swallow the keypress"
        case .activateApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Activate an app" : "Activate \(label)"
        case .hideApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Hide an app" : "Hide \(label)"
        case .unhideApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Unhide an app" : "Unhide \(label)"
        case .quitApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Quit an app" : "Quit \(label)"
        case .forceQuitApp:
            let label = !appName.isEmpty ? appName : appBundleID
            return label.isEmpty ? "Force quit an app" : "Force quit \(label)"
        case .activateLastApp:
            return "Activate last app"
        case .windowAction:
            return "Window: \((windowActionKind ?? .leftHalf).rawValue)"
        case .lockScreen: return "Lock screen"
        case .showDesktop: return "Show desktop"
        case .missionControl: return "Mission Control"
        case .toggleDarkMode: return "Toggle dark mode"
        case .setVolume: return "Set volume to \(numberValue ?? 50)%"
        case .muteSystem: return "Toggle mute"
        case .emptyTrash: return "Empty Trash"
        case .getBatteryState: return "Get battery state"
        case .getIPAddress: return "Get IP address"
        case .toggleHiddenFiles: return "Toggle hidden files"
        case .logOut: return "Log out"
        case .restartSystem: return "Restart Mac"
        case .shutdownSystem: return "Shut down Mac"
        case .speakText:
            return text.isEmpty ? "Speak text" : "Speak \"\(text.prefix(28))\(text.count > 28 ? "…" : "")\""
        case .transformText:
            return "Clipboard → \((textTransformKind ?? .upperCase).rawValue)"
        case .calculateExpression:
            return variableName.isEmpty ? "Calculate expression" : "\(variableName) = calc(\(variableValue.prefix(24)))"
        case .incrementVariable:
            return variableName.isEmpty ? "Increment a variable" : "\(variableName) += \(variableValue.isEmpty ? "1" : variableValue)"
        case .decrementVariable:
            return variableName.isEmpty ? "Decrement a variable" : "\(variableName) -= \(variableValue.isEmpty ? "1" : variableValue)"
        case .appendClipboard:
            return text.isEmpty ? "Append to clipboard" : "Append: \(text.prefix(28))"
        case .pasteClipboard: return "Paste clipboard"
        case .httpRequest:
            return urlString.isEmpty ? "HTTP request" : "GET \(urlString.prefix(32))"
        case .openFile:
            return appPath.isEmpty ? "Open a file" : "Open \(appPath.prefix(32))"
        case .openFolder:
            return appPath.isEmpty ? "Open a folder" : "Reveal \(appPath.prefix(32))"
        case .playSound:
            return text.isEmpty ? "Play a sound" : "Play \(text.prefix(28))"
        case .flashScreen: return "Flash screen"
        }
    }
}

// MARK: - Additional Trigger

struct AdditionalTrigger: Identifiable, Equatable, Codable {
    var id = UUID()
    var trigger: ManipulatorTrigger = .init()
    var conditions: [Condition] = []
}

// MARK: - Manipulator

struct ManipulatorParameters: Equatable, Codable {
    var toIfAloneTimeoutMilliseconds: Int = 1000
    var toIfHeldDownThresholdMilliseconds: Int = 500
    var toDelayActionDelayMilliseconds: Int = 0
    var simultaneousThresholdMilliseconds: Int = 1500
    var mouseMotionToScrollSpeed: Double = 1.0

    var sequenceTimeout: TimeInterval {
        TimeInterval(simultaneousThresholdMilliseconds) / 1000.0
    }
}

enum ManipulatorType: String, CaseIterable, Identifiable, Codable {
    case basic = "Basic"
    case mouseBasic = "Mouse Basic"
    case mouseMotionToScroll = "Mouse Motion to Scroll"

    var id: String { rawValue }
}

struct Manipulator: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String = "New Manipulator"
    var isStarred: Bool = false
    var notes: String = ""
    var folder: String = ""
    var isEnabled: Bool = true
    var tags: Set<String> = []
    var manipulatorType: ManipulatorType = .basic
    var trigger: ManipulatorTrigger = .init()
    var conditions: [Condition] = []
    var actions: [Action] = []
    var parameters: ManipulatorParameters = .init()
    var additionalTriggers: [AdditionalTrigger] = []

    // MARK: - Equatable (fast path: compare by ID for SwiftUI diffs)
    // SwiftUI only needs to know if the struct *changed*, not deep-compare
    // every nested array. The structural equality is enforced at mutation time.
    static func == (lhs: Manipulator, rhs: Manipulator) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.isStarred == rhs.isStarred
            && lhs.isEnabled == rhs.isEnabled
            && lhs.folder == rhs.folder
            && lhs.tags == rhs.tags
            && lhs.manipulatorType == rhs.manipulatorType
            && lhs.trigger == rhs.trigger
            && lhs.actions.count == rhs.actions.count
            && lhs.conditions.count == rhs.conditions.count
            && lhs.additionalTriggers.count == rhs.additionalTriggers.count
            && lhs.parameters == rhs.parameters
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: UUID = UUID(), name: String = "New Manipulator", notes: String = "", folder: String = "", isEnabled: Bool = true, tags: Set<String> = [], manipulatorType: ManipulatorType = .basic, trigger: ManipulatorTrigger = .init(), conditions: [Condition] = [], actions: [Action] = [], parameters: ManipulatorParameters = .init(), additionalTriggers: [AdditionalTrigger] = []) {
        self.id = id
        self.name = name
        self.notes = notes
        self.folder = folder
        self.isEnabled = isEnabled
        self.tags = tags
        self.manipulatorType = manipulatorType
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.parameters = parameters
        self.additionalTriggers = additionalTriggers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Manipulator"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        manipulatorType = try container.decodeIfPresent(ManipulatorType.self, forKey: .manipulatorType) ?? .basic
        trigger = try container.decodeIfPresent(ManipulatorTrigger.self, forKey: .trigger) ?? .init()
        conditions = try container.decodeIfPresent([Condition].self, forKey: .conditions) ?? []
        actions = try container.decodeIfPresent([Action].self, forKey: .actions) ?? []
        parameters = try container.decodeIfPresent(ManipulatorParameters.self, forKey: .parameters) ?? .init()
        additionalTriggers = try container.decodeIfPresent([AdditionalTrigger].self, forKey: .additionalTriggers) ?? []
    }

    var summary: String {
        let trigger = self.trigger.displayLabel
        let additionalSuffix: String
        if !additionalTriggers.isEmpty {
            additionalSuffix = " (+\\(additionalTriggers.count) more)"
        } else {
            additionalSuffix = ""
        }
        if conditions.isEmpty {
            if let first = actions.first {
                return "\(trigger)\(additionalSuffix) → \(first.summary)"
            }
            return "\(trigger)\(additionalSuffix) → No actions"
        }
        return "\(trigger)\(additionalSuffix) if \(conditions[0].summary) → \(actions.first?.summary ?? "…")"
    }
}


