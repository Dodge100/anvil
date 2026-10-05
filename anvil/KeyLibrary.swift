import Foundation

enum KeyCategory: String, CaseIterable, Identifiable {
    case letters = "Letters"
    case numbers = "Numbers"
    case functionKeys = "Function Keys"
    case modifiers = "Modifiers"
    case navigation = "Navigation"
    case symbols = "Symbols"
    case numpad = "Numeric Keypad"
    case media = "Media"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .letters: return "textformat.abc"
        case .numbers: return "number"
        case .functionKeys: return "fn"
        case .modifiers: return "command"
        case .navigation: return "arrow.up.and.down.and.arrow.left.and.right"
        case .symbols: return "ellipsis.rectangle"
        case .numpad: return "rectangle.3.offgrid"
        case .media: return "playpause"
        case .other: return "questionmark.circle"
        }
    }

    var displayOrder: Int {
        switch self {
        case .modifiers: return 0
        case .functionKeys: return 1
        case .letters: return 2
        case .numbers: return 3
        case .navigation: return 4
        case .symbols: return 5
        case .numpad: return 6
        case .media: return 7
        case .other: return 8
        }
    }
}

struct KeyDescriptor: Identifiable, Hashable {
    let id: String
    let label: String
    let category: KeyCategory
}

enum KeyLibrary {
    static let all: [KeyDescriptor] = modifiers + functionKeys + letters + numbers + navigation + symbols + numpad + media + other

    static let modifiers: [KeyDescriptor] = [
        KeyDescriptor(id: "left_command", label: "Left ⌘", category: .modifiers),
        KeyDescriptor(id: "right_command", label: "Right ⌘", category: .modifiers),
        KeyDescriptor(id: "left_shift", label: "Left ⇧", category: .modifiers),
        KeyDescriptor(id: "right_shift", label: "Right ⇧", category: .modifiers),
        KeyDescriptor(id: "left_option", label: "Left ⌥", category: .modifiers),
        KeyDescriptor(id: "right_option", label: "Right ⌥", category: .modifiers),
        KeyDescriptor(id: "left_control", label: "Left ⌃", category: .modifiers),
        KeyDescriptor(id: "right_control", label: "Right ⌃", category: .modifiers),
        KeyDescriptor(id: "caps_lock", label: "Caps Lock", category: .modifiers),
        KeyDescriptor(id: "fn", label: "fn", category: .modifiers)
    ]

    static let functionKeys: [KeyDescriptor] = [
        KeyDescriptor(id: "escape", label: "Escape", category: .functionKeys),
        KeyDescriptor(id: "f1", label: "F1", category: .functionKeys),
        KeyDescriptor(id: "f2", label: "F2", category: .functionKeys),
        KeyDescriptor(id: "f3", label: "F3", category: .functionKeys),
        KeyDescriptor(id: "f4", label: "F4", category: .functionKeys),
        KeyDescriptor(id: "f5", label: "F5", category: .functionKeys),
        KeyDescriptor(id: "f6", label: "F6", category: .functionKeys),
        KeyDescriptor(id: "f7", label: "F7", category: .functionKeys),
        KeyDescriptor(id: "f8", label: "F8", category: .functionKeys),
        KeyDescriptor(id: "f9", label: "F9", category: .functionKeys),
        KeyDescriptor(id: "f10", label: "F10", category: .functionKeys),
        KeyDescriptor(id: "f11", label: "F11", category: .functionKeys),
        KeyDescriptor(id: "f12", label: "F12", category: .functionKeys)
    ]

    static let letters: [KeyDescriptor] = "abcdefghijklmnopqrstuvwxyz".map {
        KeyDescriptor(id: String($0), label: String($0).uppercased(), category: .letters)
    }

    static let numbers: [KeyDescriptor] = "0123456789".map {
        KeyDescriptor(id: String($0), label: String($0), category: .numbers)
    }

    static let navigation: [KeyDescriptor] = [
        KeyDescriptor(id: "up_arrow", label: "↑ Up", category: .navigation),
        KeyDescriptor(id: "down_arrow", label: "↓ Down", category: .navigation),
        KeyDescriptor(id: "left_arrow", label: "← Left", category: .navigation),
        KeyDescriptor(id: "right_arrow", label: "→ Right", category: .navigation),
        KeyDescriptor(id: "home", label: "Home", category: .navigation),
        KeyDescriptor(id: "end", label: "End", category: .navigation),
        KeyDescriptor(id: "pageup", label: "Page Up", category: .navigation),
        KeyDescriptor(id: "pagedown", label: "Page Down", category: .navigation),
        KeyDescriptor(id: "tab", label: "Tab", category: .navigation),
        KeyDescriptor(id: "return", label: "Return", category: .navigation),
        KeyDescriptor(id: "delete", label: "Delete", category: .navigation),
        KeyDescriptor(id: "forward_delete", label: "Forward Delete", category: .navigation),
        KeyDescriptor(id: "space", label: "Space", category: .navigation)
    ]

    static let symbols: [KeyDescriptor] = [
        KeyDescriptor(id: "grave", label: "` grave", category: .symbols),
        KeyDescriptor(id: "minus", label: "- minus", category: .symbols),
        KeyDescriptor(id: "equal", label: "= equal", category: .symbols),
        KeyDescriptor(id: "left_bracket", label: "[ left bracket", category: .symbols),
        KeyDescriptor(id: "right_bracket", label: "] right bracket", category: .symbols),
        KeyDescriptor(id: "backslash", label: "\\ backslash", category: .symbols),
        KeyDescriptor(id: "semicolon", label: "; semicolon", category: .symbols),
        KeyDescriptor(id: "quote", label: "' quote", category: .symbols),
        KeyDescriptor(id: "comma", label: ", comma", category: .symbols),
        KeyDescriptor(id: "period", label: ". period", category: .symbols),
        KeyDescriptor(id: "slash", label: "/ slash", category: .symbols)
    ]

    static let numpad: [KeyDescriptor] = [
        KeyDescriptor(id: "numpad_0", label: "Numpad 0", category: .numpad),
        KeyDescriptor(id: "numpad_1", label: "Numpad 1", category: .numpad),
        KeyDescriptor(id: "numpad_2", label: "Numpad 2", category: .numpad),
        KeyDescriptor(id: "numpad_3", label: "Numpad 3", category: .numpad),
        KeyDescriptor(id: "numpad_4", label: "Numpad 4", category: .numpad),
        KeyDescriptor(id: "numpad_5", label: "Numpad 5", category: .numpad),
        KeyDescriptor(id: "numpad_6", label: "Numpad 6", category: .numpad),
        KeyDescriptor(id: "numpad_7", label: "Numpad 7", category: .numpad),
        KeyDescriptor(id: "numpad_8", label: "Numpad 8", category: .numpad),
        KeyDescriptor(id: "numpad_9", label: "Numpad 9", category: .numpad),
        KeyDescriptor(id: "numpad_divide", label: "Numpad /", category: .numpad),
        KeyDescriptor(id: "numpad_multiply", label: "Numpad *", category: .numpad),
        KeyDescriptor(id: "numpad_minus", label: "Numpad -", category: .numpad),
        KeyDescriptor(id: "numpad_plus", label: "Numpad +", category: .numpad),
        KeyDescriptor(id: "numpad_enter", label: "Numpad Enter", category: .numpad),
        KeyDescriptor(id: "numpad_decimal", label: "Numpad .", category: .numpad)
    ]

    static let media: [KeyDescriptor] = [
        KeyDescriptor(id: "vk_consumer_play", label: "Play", category: .media),
        KeyDescriptor(id: "vk_consumer_pause", label: "Pause", category: .media),
        KeyDescriptor(id: "vk_consumer_next", label: "Next Track", category: .media),
        KeyDescriptor(id: "vk_consumer_prev", label: "Previous Track", category: .media),
        KeyDescriptor(id: "vk_consumer_volume_up", label: "Volume Up", category: .media),
        KeyDescriptor(id: "vk_consumer_volume_down", label: "Volume Down", category: .media),
        KeyDescriptor(id: "vk_consumer_mute", label: "Mute", category: .media),
        KeyDescriptor(id: "vk_consumer_brightness_up", label: "Brightness Up", category: .media),
        KeyDescriptor(id: "vk_consumer_brightness_down", label: "Brightness Down", category: .media),
        KeyDescriptor(id: "vk_consumer_rewind", label: "Rewind", category: .media),
        KeyDescriptor(id: "vk_consumer_fast_forward", label: "Fast Forward", category: .media),
        KeyDescriptor(id: "vk_consumer_eject", label: "Eject", category: .media),
        KeyDescriptor(id: "vk_consumer_power", label: "Power", category: .media)
    ]

    static let other: [KeyDescriptor] = [
        KeyDescriptor(id: "help", label: "Help", category: .other)
    ]

    static let byID: [String: KeyDescriptor] = {
        var result: [String: KeyDescriptor] = [:]
        for key in all {
            result[key.id] = key
        }
        return result
    }()

    static func label(for id: String) -> String {
        byID[id]?.label ?? id
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

}
