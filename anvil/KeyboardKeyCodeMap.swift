import CoreGraphics
import Carbon.HIToolbox

enum KeyboardKeyCodeMap {
    private static let map: [String: CGKeyCode] = [
        "a": 0,
        "s": 1,
        "d": 2,
        "f": 3,
        "h": 4,
        "g": 5,
        "z": 6,
        "x": 7,
        "c": 8,
        "v": 9,
        "b": 11,
        "q": 12,
        "w": 13,
        "e": 14,
        "r": 15,
        "y": 16,
        "t": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "equal": 24,
        "9": 25,
        "7": 26,
        "minus": 27,
        "8": 28,
        "0": 29,
        "right_bracket": 30,
        "o": 31,
        "u": 32,
        "left_bracket": 33,
        "i": 34,
        "p": 35,
        "return": 36,
        "l": 37,
        "j": 38,
        "quote": 39,
        "k": 40,
        "semicolon": 41,
        "backslash": 42,
        "comma": 43,
        "slash": 44,
        "n": 45,
        "m": 46,
        "period": 47,
        "tab": 48,
        "space": 49,
        "grave": 50,
        "delete": 51,
        "escape": 53,
        "left_command": 55,
        "left_shift": 56,
        "caps_lock": 57,
        "left_option": 58,
        "left_control": 59,
        "right_shift": 60,
        "right_option": 61,
        "right_control": 62,
        "fn": 63,
        "f17": 64,
        "f18": 79,
        "f19": 80,
        "f20": 90,
        "f5": 96,
        "f6": 97,
        "f7": 98,
        "f3": 99,
        "f8": 100,
        "f9": 101,
        "f11": 103,
        "f13": 105,
        "f16": 106,
        "f14": 107,
        "f10": 109,
        "f12": 111,
        "f15": 113,
        "help": 114,
        "home": 115,
        "pageup": 116,
        "forward_delete": 117,
        "f4": 118,
        "end": 119,
        "f2": 120,
        "pagedown": 121,
        "f1": 122,
        "left_arrow": 123,
        "right_arrow": 124,
        "down_arrow": 125,
        "up_arrow": 126,
        "right_command": 54,
        "numlock": 71,
        "numpad_divide": 75,
        "numpad_multiply": 67,
        "numpad_minus": 78,
        "numpad_plus": 69,
        "numpad_enter": 76,
        "numpad_decimal": 65,
        "numpad_0": 82,
        "numpad_1": 83,
        "numpad_2": 84,
        "numpad_3": 85,
        "numpad_4": 86,
        "numpad_5": 87,
        "numpad_6": 88,
        "numpad_7": 89,
        "numpad_8": 91,
        "numpad_9": 92,
        "f21": 65,
        "f22": 66,
        "f23": 68,
        "f24": 70,
        "numpad_equal": 81,
        "numpad_clear": 71,
        "international1": 94,
        "international2": 95,
        "international3": 101,
        "international4": 102,
        "international5": 104,
        "international6": 108,
        "international7": 110,
        "international8": 112,
        "international9": 93,
        "lang1": 105,
        "lang2": 108,
        "iso_section": 10,
        "jis_eisu": 102,
        "jis_kana": 104,
    ]

    private static let consumerMap: [String: UInt16] = [
        "vk_consumer_play": UInt16(NX_KEYTYPE_PLAY),
        "vk_consumer_pause": UInt16(NX_KEYTYPE_PLAY),
        "vk_consumer_next": UInt16(NX_KEYTYPE_NEXT),
        "vk_consumer_prev": UInt16(NX_KEYTYPE_PREVIOUS),
        "vk_consumer_volume_up": UInt16(NX_KEYTYPE_SOUND_UP),
        "vk_consumer_volume_down": UInt16(NX_KEYTYPE_SOUND_DOWN),
        "vk_consumer_mute": UInt16(NX_KEYTYPE_MUTE),
        "vk_consumer_brightness_up": UInt16(NX_KEYTYPE_BRIGHTNESS_UP),
        "vk_consumer_brightness_down": UInt16(NX_KEYTYPE_BRIGHTNESS_DOWN),
        "vk_consumer_rewind": UInt16(NX_KEYTYPE_REWIND),
        "vk_consumer_fast_forward": UInt16(NX_KEYTYPE_FF),
        "vk_consumer_eject": UInt16(NX_KEYTYPE_EJECT),
        "vk_consumer_power": UInt16(NX_KEYTYPE_POWER),
    ]

    private static let reverseMap: [CGKeyCode: String] = {
        var result: [CGKeyCode: String] = [:]
        for (id, code) in map {
            result[code] = id
        }
        return result
    }()

    static func code(for keyID: String) -> CGKeyCode? {
        map[keyID]
    }

    static func id(for keyCode: CGKeyCode) -> String? {
        reverseMap[keyCode]
    }

    static func isConsumerKeyID(_ keyID: String) -> Bool {
        consumerMap[keyID] != nil
    }

    static func consumerCode(for keyID: String) -> UInt16? {
        consumerMap[keyID]
    }

    static func hasConsumerCode(_ code: UInt16) -> String? {
        consumerMap.first(where: { $0.value == code })?.key
    }

    private static let modifierIDs: Set<String> = [
        "left_command", "right_command",
        "left_shift", "right_shift",
        "left_option", "right_option",
        "left_control", "right_control",
        "caps_lock", "fn"
    ]

    static func isModifierKeyID(_ keyID: String) -> Bool {
        modifierIDs.contains(keyID)
    }

    static func modifierKeyIDs(for modifier: ModifierKey) -> Set<String> {
        switch modifier {
        case .command: return ["left_command", "right_command"]
        case .shift: return ["left_shift", "right_shift"]
        case .option: return ["left_option", "right_option"]
        case .control: return ["left_control", "right_control"]
        case .capsLock: return ["caps_lock"]
        case .fn: return ["fn"]
        }
    }
}

// MARK: - NX Key Type constants (from IOKit/hidsystem/ev_keymap.h)

let NX_KEYTYPE_PLAY: Int32 = 16
let NX_KEYTYPE_NEXT: Int32 = 17
let NX_KEYTYPE_PREVIOUS: Int32 = 18
let NX_KEYTYPE_SOUND_UP: Int32 = 0
let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
let NX_KEYTYPE_MUTE: Int32 = 7
let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
let NX_KEYTYPE_REWIND: Int32 = 19
let NX_KEYTYPE_FF: Int32 = 20
let NX_KEYTYPE_EJECT: Int32 = 14
let NX_KEYTYPE_POWER: Int32 = 22
