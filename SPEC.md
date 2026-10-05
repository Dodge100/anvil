# Anvil / KeyCommand — macOS Productivity Suite

## 2. Part One: Keyboard Remappings

> System-level keyboard, mouse, and media key remapping with full Karabiner-Elements feature parity.

### 2.1 Trigger Events

| Feature | Status | Description | Source |
|---------|--------|-------------|--------|
| `key_code` trigger | ✅ | Match specific keyboard keys by string ID (e.g., `"space"`, `"a"`, `"left_arrow"`) | Anvil |
| `consumer_key_code` trigger | ✅ | Match media/consumer keys (volume, brightness, play/pause, eject, power) — 13 types | Anvil |
| `pointing_button` trigger | ✅ | Match mouse buttons (left, right, middle, back, forward, center) | Anvil |
| `any` key trigger | ✅ | Wildcard: matches ANY keyboard keypress | Anvil |
| Modifier key as trigger | ✅ | A modifier key itself as the trigger (caps_lock → escape, right ⌘ → …); dispatched from flagsChanged events | Anvil |
| Mandatory modifiers | ✅ | Must-have modifiers (command, shift, option, control, capsLock, fn) for trigger | Anvil |
| Optional modifiers | ✅ | Modifiers that may be present but aren't required | Anvil |
| Left/right modifier discrimination | ✅ | Separate tracking for left_command vs right_command, etc. | Anvil |
| Caps Lock tracking | ✅ | Explicit `capsLockActive` state and `maskAlphaShift` flag matching | Anvil |
| Fn key tracking | ✅ | `fnPressed` boolean tracked separately (fn has no CGEventFlag) | Anvil |
| Simultaneous chord trigger | ✅ | Match 2+ keys pressed together within threshold | Anvil |
| Simultaneous strict order | ✅ | `key_down_order`: insensitive, strict, strictInverse | Anvil |
| Simultaneous up order | ✅ | `key_up_order`: insensitive, strict, strictInverse | Anvil |
| Simultaneous up-when | ✅ | `key_up_when`: any (first key up) or all (last key up) | Anvil |
| Simultaneous `to_after_key_up` | ✅ | Actions that fire when chord keys are released | Anvil |
| Simultaneous detect key down uninterruptedly | ✅ | Option to require uninterrupted key-down detection | Anvil |
| Sequence trigger (multi-step) | ✅ | Sequential keypress match (a → b → c) with configurable timeout | Anvil |
| Sequence timeout | ✅ | Configurable via `simultaneousThresholdMilliseconds` (default 1500ms) | Anvil |
| Triggers with no steps | ✅ | Valid for `any` key and `mouseMotionToScroll` types | Anvil |
| `to_if_other_key_pressed` trigger | ✅ | Fire actions when another key is pressed while trigger is held | Karabiner |
| Typed String trigger | ✅ | Match a typed string sequence (e.g., "teh" → "the") | Keyboard Maestro |
| Typed String options | ✅ | Trigger on prefix, on full match, or immediately on any match | Keyboard Maestro |
| Hot Key trigger (hold/release/multi-tap) | ✅ | Trigger with configurable press, hold, release, and multi-tap behaviors | Keyboard Maestro |
| Named trigger | ✅ | Trigger by name from another macro/action | Keyboard Maestro |
| String trigger (app-specific) | ✅ | Typed string trigger scoped to a specific application | Keyboard Maestro |

### 2.2 Conditions

| Feature | Status | Description | Source |
|---------|--------|-------------|--------|
| `frontmostApplication` | ✅ | Match active app by bundle ID (e.g., `com.apple.Safari`) — cached, invalidated on app change | Anvil |
| `frontmostAppName` | ✅ | Match active app by display name (e.g., `Safari`) — cached, invalidated on app change | Anvil |
| `inputSource` | ✅ | Match current keyboard input source by ID — cached, invalidated on change | Anvil |
| `device` | ✅ | Match by `"built-in"`, `"external"`, or numeric product ID | Anvil |
| `variable` | ✅ | Match engine variable by name (set via `Set Variable`/`Toggle Variable` actions) | Anvil |
| `keyboardType` | ✅ | Match keyboard layout: `ansi`, `iso`, `jis` | Anvil |
| `deviceExists` | ✅ | Check if a device is connected (`"built-in"`, `"external"`, or product ID) | Anvil |
| `expression` | ✅ | Evaluate `variable_name == "value"` or `variable_name != "value"` expressions | Anvil |
| `eventChanged` | ✅ | Check if event changed due to `keyboard_type` or `device` switch | Anvil |
| Per-action conditions | ✅ | `to.conditions` — conditions applied to individual actions within a manipulator | Karabiner |

**Comparison operators**: `is` (equals), `is not` (not equals), `contains`, `matches` (regex)

#### Planned Conditions

| Feature | Status | Description | Source |
|---------|--------|-------------|--------|
| `screenCondition` | 🔄 | Match by screen size, resolution, or which screen is primary | Keyboard Maestro |
| `tokenCondition` | 🔄 | Evaluate expressions using tokens (e.g., `System:CurrentDate`, `FrontBrowser:URL`) | Keyboard Maestro |
| `pixelCondition` | 🔄 | Match a pixel color at a specific screen coordinate | Keyboard Maestro |
| `windowCondition` | 🔄 | Match by window title, position, size, or minimized/hidden state | Keyboard Maestro |
| `runningCondition` | 🔄 | Check if a specific application is running (by bundle ID or display name) | Keyboard Maestro |
| `globalVariableCondition` | 🔄 | Persistent variables that survive across macro restarts | Keyboard Maestro |
| `Named Clipboard condition` | 🔄 | Check contents of named clipboards | Keyboard Maestro |

### 2.3 Actions (To Events)

| # | Action Kind | Status | Description | Source |
|---|-------------|--------|-------------|--------|
| 1 | `sendKey` | ✅ | Press a single key with modifiers | Anvil |
| 2 | `sendText` | ✅ | Type a string of text (up to 64 UTF-16 code units) | Anvil |
| 3 | `setVariable` | ✅ | Save a value to a named engine variable | Anvil |
| 4 | `unsetVariable` | ✅ | Remove a named variable | Anvil |
| 5 | `toggleVariable` | ✅ | Flip a variable between `"true"` and `"false"` | Anvil |
| 6 | `runShell` | ✅ | Execute a shell command (`/bin/sh -c`) | Anvil |
| 7 | `openApp` | ✅ | Launch an application (by bundle ID or display name) | Anvil |
| 8 | `openURL` | ✅ | Open a URL via `NSWorkspace.shared.open()` | Anvil |
| 9 | `runShortcut` | ✅ | Run a macOS Shortcut via AppleScript bridge | Anvil |
| 10 | `runAppleScript` | ✅ | Execute an AppleScript snippet | Anvil |
| 11 | `delay` | ✅ | Wait before executing the next step | Anvil |
| 12 | `disable` | ✅ | Swallow the keypress entirely — do not pass to system | Anvil |
| 13 | `consumerKey` | ✅ | Send a media/consumer key event (play, pause, volume, brightness, etc.) | Anvil |
| 14 | `pointingButton` | ✅ | Send a mouse button click (left, right, middle, back, forward) | Anvil |
| 15 | `mouseKey` | ✅ | Move mouse cursor or send scroll wheel events | Anvil |
| 16 | `stickyModifier` | ✅ | Toggle a modifier key as sticky (latching behavior) | Anvil |
| 17 | `halt` | ✅ | Stop processing further actions in the manipulator | Anvil |
| 18 | `holdDown` | ✅ | Press a key and hold it for a specified duration | Anvil |
| 19 | `selectInputSource` | ✅ | Switch keyboard input source | Anvil |
| 20 | `setNotification` | ✅ | Show an on-screen macOS notification | Anvil |
| 21 | `fromEvent` | ✅ | Mirror/pass through the original trigger event | Anvil |
| 22 | `softwareFunction` | ✅ | Execute a system-level function (doubleClick/sleepSystem/setCursorPosition) | Anvil |
| 23 | `setMouseCursorPosition` | 🔄 | Set mouse cursor position to absolute coordinates | Karabiner |
| 24 | `openApplication` | 🔄 | Open application via software function | Karabiner |
| 25 | `sendUserCommand` | 🔄 | Send a user-defined command | Karabiner |

### 2.4 Action Fire Modes

| Fire Mode | Status | Description | Source |
|-----------|--------|-------------|--------|
| `onKeyDown` | ✅ | Fires immediately when the trigger key is pressed | Anvil |
| `ifAlone` | ✅ | Fires only if the trigger key is released within `to_if_alone_timeout` | Anvil |
| `ifHeldDown` | ✅ | Fires once the key has been held longer than `to_if_held_down_threshold` | Anvil |
| `ifHeldDownInvoked` | ✅ | Fires after `to_delayed_action_delay` if key is still held uninterrupted | Anvil |
| `ifHeldDownCanceled` | ✅ | Fires if another key is pressed before the delay elapses | Anvil |
| `afterKeyUp` | ✅ | Fires when the trigger key is released | Anvil |
| `ifOtherKeyPressed` | ✅ | Fire actions when another key is pressed while trigger is held | Karabiner |

**Timing parameters**: `to_if_alone_timeout` (1000ms), `to_if_held_down_threshold` (500ms), `to_delayed_action_delay` (0ms), `simultaneous_threshold` (1500ms)

### 2.5 Manipulator Types

| Type | Status | Description | Source |
|------|--------|-------------|--------|
| `basic` | ✅ | Standard keyboard remapping (default) | Anvil |
| `mouseBasic` | ✅ | Mouse button remapping — intercepts mouse clicks | Anvil |
| `mouseMotionToScroll` | ✅ | Converts mouse movement into scroll events (swap cursor → scroll) | Anvil |

### 2.6 Manipulator Parameters

| Parameter | Status | Default | Description |
|-----------|--------|---------|-------------|
| `to_if_alone_timeout` | ✅ | 1000 ms | Timeout for if-alone press resolution |
| `to_if_held_down_threshold` | ✅ | 500 ms | Threshold for if-held-down detection |
| `to_delayed_action_delay` | ✅ | 0 ms | Delay before invoked/canceled actions |
| `simultaneous_threshold` | ✅ | 1500 ms | Timeout for chord/sequence matching |
| `mouse_motion_to_scroll_speed` | ✅ | 1.0 | Speed multiplier for mouse-motion-to-scroll |
| `mouse_key_x/y_speed` | 🔄 | Part of `speedMultiplier` | Named differently, same function |

### 2.7 To-Event Options

| Option | Status | Description | Source |
|--------|--------|-------------|--------|
| `lazy` modifier | ✅ | Lazy modifier application — only applies if not already pressed | Karabiner |
| `repeat` control | ✅ | Disable repeat on held keys | Karabiner |
| `halt` | ✅ | Stop processing further actions | Karabiner |
| `hold_down_milliseconds` | ✅ | Hold a key for a specified duration then release | Karabiner |
| `to.conditions` | ✅ | Per-action conditions — only send event if conditions are met | Karabiner |

### 2.8 Remap Vision

| Feature | Status | Description |
|---------|--------|-------------|
| Visual keyboard editor | ✅ | Interactive on-screen keyboard for trigger selection |
| Record mode | 🔄 | Record keystrokes and auto-generate manipulators |
| Code editor (JSON editor) | ✅ | Direct config.json editing within the app |
| Visual workflow builder | ✅ | Drag-and-drop action/condition flow builder |
| Manipulator import/export | 🔄 | Share individual manipulators as files |
| Manipulator library (community) | ❌ | Download pre-built manipulators |
| Config profiles | 🔄 | Multiple config profiles for different contexts |
| Undo/redo | 🔄 | Full undo/redo support for manipulator changes |
| Cloud sync | ❌ | iCloud or other cloud config sync |
| Global macro palette | ❌ | Floating palette for triggering macros by click |
| Status menu trigger | ❌ | Add macros to system status menu for click activation |
| Multiple simultaneous triggers | ❌ | More than one trigger per macro with different conditions |

---

## 3. Part Two: Automation Engine

> A comprehensive automation engine combining the power of Keyboard Maestro actions, Keyboard Cowboy commands, and Apple Shortcuts actions — all accessible from keyboard remappings, menu bar items, widgets, and Shortcuts app.

### 3.1 Application Control

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `openApp` | ✅ | Launch an application | Anvil |
| `activateApp` | ✅ | Bring an application to foreground | Keyboard Cowboy |
| `hideApp` | ✅ | Hide a specific application | Keyboard Cowboy |
| `unhideApp` | ✅ | Unhide a hidden application | Keyboard Cowboy |
| `quitApp` | ✅ | Quit a specific application | Keyboard Cowboy |
| `forceQuitApp` | ✅ | Force-quit a specific application | Keyboard Cowboy |
| `peekApp` | ❌ | Open app; hide again when keys released if held >1s | Keyboard Cowboy |
| `ifNotRunning` | ❌ | Only launch if not already running | Keyboard Cowboy |
| `waitForAppLaunch` | ❌ | Wait for app to fully launch before next action | Keyboard Cowboy |
| `appFocus` | ❌ | Bring all windows of an app to front, optionally hide others | Keyboard Cowboy |
| `setKeyboardLayout` | ❌ | Set keyboard layout for an application | Keyboard Maestro |
| `selectMenuItem` | ❌ | Select or show a menu item in an application | Keyboard Maestro |
| `pressButton` | ❌ | Press a UI button in an application | Keyboard Maestro |
| `getRunningApps` | ❌ | List all currently running applications | Keyboard Maestro |
| `getActiveApp` | ❌ | Get the currently active/frontmost application | — |
| `getAppWindows` | ❌ | List all windows of a specific application | — |
| `activateLastApp` | ✅ | Switch to the previously active application | Keyboard Cowboy |
| `toggleAppVisibility` | ❌ | Toggle app between visible/hidden states | Keyboard Cowboy |

### 3.2 Window Management

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `manipulateWindow` | ✅ | Move, resize, minimize, maximize, close, center window | Keyboard Maestro |
| `moveWindow` | ❌ | Move window to absolute position | Keyboard Maestro |
| `resizeWindow` | ❌ | Resize window to specific dimensions | Keyboard Maestro |
| `moveAndResizeWindow` | ❌ | Move and resize in one action | Keyboard Maestro |
| `centerWindow` | ✅ | Center the frontmost window on screen | — |
| `windowToLeft` | ✅ | Snap window to left half | Keyboard Cowboy |
| `windowToRight` | ✅ | Snap window to right half | Keyboard Cowboy |
| `windowToTop` | ✅ | Snap window to top half | Keyboard Cowboy |
| `windowToBottom` | ✅ | Snap window to bottom half | Keyboard Cowboy |
| `windowToTopLeft` | ✅ | Snap window to top-left quarter | Keyboard Cowboy |
| `windowToTopRight` | ✅ | Snap window to top-right quarter | Keyboard Cowboy |
| `windowToBottomLeft` | ✅ | Snap window to bottom-left quarter | Keyboard Cowboy |
| `windowToBottomRight` | ✅ | Snap window to bottom-right quarter | Keyboard Cowboy |
| `windowFill` | ✅ | Fill screen without entering fullscreen | Keyboard Cowboy |
| `windowZoom` | ❌ | Zoom window to fill available space | Keyboard Cowboy |
| `windowTileLeftRight` | ❌ | Tile windows left and right | Keyboard Cowboy |
| `windowTileTopBottom` | ❌ | Tile windows top and bottom | Keyboard Cowboy |
| `windowTileQuarters` | ❌ | Arrange windows in quarters | Keyboard Cowboy |
| `windowTileLeftQuarters` | ❌ | Left + quarters arrangement | Keyboard Cowboy |
| `windowTileDynamicQuarters` | ❌ | Dynamic arrangement based on window count | Keyboard Cowboy |
| `minimizeWindow` | ✅ | Minimize the frontmost window | Keyboard Maestro |
| `minimizeAllWindows` | ❌ | Minimize all open windows | Keyboard Cowboy |
| `closeWindow` | ✅ | Close the frontmost window | Keyboard Maestro |
| `maximizeWindow` | ✅ | Maximize the frontmost window | Keyboard Maestro |
| `toggleWindowFullscreen` | ❌ | Toggle fullscreen mode | — |
| `keepWindowOnTop` | ❌ | Toggle always-on-top for the frontmost window | — |
| `getWindowSize` | ❌ | Get current window dimensions into variables | Keyboard Maestro |
| `getWindowTitle` | ❌ | Get the title of the frontmost window | Keyboard Maestro |
| `focusWindowUp` | ❌ | Move focus to window above | Keyboard Cowboy |
| `focusWindowDown` | ❌ | Move focus to window below | Keyboard Cowboy |
| `focusWindowLeft` | ❌ | Move focus to window on left | Keyboard Cowboy |
| `focusWindowRight` | ❌ | Move focus to window on right | Keyboard Cowboy |
| `focusWindowUpperLeft` | ❌ | Move focus to upper-left quarter | Keyboard Cowboy |
| `focusWindowUpperRight` | ❌ | Move focus to upper-right quarter | Keyboard Cowboy |
| `focusWindowLowerLeft` | ❌ | Move focus to lower-left quarter | Keyboard Cowboy |
| `focusWindowLowerRight` | ❌ | Move focus to lower-right quarter | Keyboard Cowboy |
| `focusWindowCenter` | ❌ | Move focus to center window | Keyboard Cowboy |
| `focusNextWindow` | ❌ | Move focus to next window | Keyboard Cowboy |
| `focusPreviousWindow` | ❌ | Move focus to previous window | Keyboard Cowboy |
| `focusNextWindowApp` | ❌ | Move focus to next window of active application | Keyboard Cowboy |
| `focusPreviousWindowApp` | ❌ | Move focus to previous window of active application | Keyboard Cowboy |
| `focusNextWindowAll` | ❌ | Move focus to next window including hidden/minimized | Keyboard Cowboy |
| `focusPreviousWindowAll` | ❌ | Move focus to previous window including hidden/minimized | Keyboard Cowboy |

### 3.3 System Controls

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `sleepSystem` | ✅ | Put the Mac to sleep | Anvil |
| `restartSystem` | ✅ | Restart the Mac | Keyboard Maestro |
| `shutdownSystem` | ✅ | Shut down the Mac | Keyboard Maestro |
| `logOut` | ✅ | Log out the current user | Keyboard Maestro |
| `lockScreen` | ✅ | Lock the screen | — |
| `fastUserSwitch` | ❌ | Switch to the login window / fast user switching | Keyboard Maestro |
| `showDesktop` | ✅ | Show desktop / minimize all windows | Keyboard Cowboy |
| `missionControl` | ✅ | Activate Mission Control | Keyboard Cowboy |
| `applicationWindows` | ❌ | Show application windows in Mission Control | Keyboard Cowboy |
| `showNotification` | ✅ | Show a macOS notification | Anvil |
| `setVolume` | ✅ | Set system volume (0-100) | Keyboard Maestro |
| `getVolume` | ❌ | Get current system volume | — |
| `muteSystem` | ✅ | Mute/unmute system audio | Keyboard Maestro |
| `setBrightness` | ❌ | Set display brightness (0-100) | Keyboard Maestro |
| `getBrightness` | ❌ | Get current display brightness | — |
| `toggleDoNotDisturb` | ❌ | Toggle Do Not Disturb mode | — |
| `toggleWiFi` | ❌ | Toggle WiFi on/off | — |
| `toggleBluetooth` | ❌ | Toggle Bluetooth on/off | — |
| `toggleDarkMode` | ✅ | Toggle Dark/Light appearance | — |
| `getDarkMode` | ❌ | Check if Dark Mode is active | — |
| `toggleHiddenFiles` | ✅ | Toggle visibility of hidden files in Finder | — |
| `emptyTrash` | ✅ | Empty the Trash | Keyboard Maestro |
| `getBatteryState` | ✅ | Get battery level, charging state, time remaining | — |
| `getIPAddress` | ✅ | Get current IP address | — |

### 3.4 Text Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `sendText` | ✅ | Type a string of text (up to 64 UTF-16 code units) | Anvil |
| `insertTextByTyping` | ❌ | Type text character by character | Keyboard Maestro |
| `insertTextByPasting` | ❌ | Paste text from clipboard | Keyboard Maestro |
| `getSelectedText` | ✅ | Get selected text from frontmost app via Accessibility API | — |
| `setSelectedText` | ❌ | Set/replace selected text in frontmost app | — |
| `upperCase` | ✅ | Convert text to uppercase | — |
| `lowerCase` | ✅ | Convert text to lowercase | — |
| `capitalize` | ✅ | Capitalize first letter of each word | — |
| `camelCase` | ✅ | Convert to camelCase | — |
| `snakeCase` | ✅ | Convert to snake_case | — |
| `kebabCase` | ✅ | Convert to kebab-case | — |
| `pascalCase` | ✅ | Convert to PascalCase | — |
| `trimWhitespace` | ✅ | Trim leading/trailing whitespace | — |
| `stripHTML` | ❌ | Remove HTML tags from text | — |
| `slugify` | ✅ | Convert text to URL-safe slug | — |
| `replaceText` | ❌ | Find and replace text (optionally with regex) | Keyboard Maestro |
| `matchRegex` | ❌ | Match text against regular expression | — |
| `extractRegex` | ❌ | Extract text matching a regex pattern | — |
| `encodeBase64` | ✅ | Encode text as Base64 | — |
| `decodeBase64` | ✅ | Decode Base64 text | — |
| `encodeURL` | ✅ | URL-encode text | — |
| `decodeURL` | ✅ | URL-decode text | — |
| `calculateExpression` | ✅ | Evaluate a math expression (`NSExpression`) | — |
| `speakText` | ✅ | Speak text using text-to-speech | Keyboard Maestro |
| `promptForInput` | ❌ | Show a dialog prompt and capture user input | Keyboard Maestro |
| `displayTextLarge` | ❌ | Display text in large overlay on screen | Keyboard Maestro |

### 3.5 Clipboard Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `getClipboard` | ✅ | Get current clipboard text content | — |
| `setClipboard` | ✅ | Set clipboard to specific text | Keyboard Maestro |
| `clearClipboard` | ✅ | Clear the clipboard | — |
| `pasteClipboard` | ✅ | Paste current clipboard content | — |
| `appendClipboard` | ✅ | Append text to clipboard | Keyboard Maestro |
| `namedClipboard` | ❌ | Named clipboard slots for storing multiple clipboard items | Keyboard Maestro |
| `clipboardHistory` | ❌ | Access clipboard history | — |
| `copyNamedClipboard` | ❌ | Copy named clipboard to system clipboard | Keyboard Maestro |
| `setNamedClipboard` | ❌ | Set named clipboard from system clipboard | Keyboard Maestro |
| `searchClipboard` | ❌ | Search clipboard history | Keyboard Maestro |
| `deleteClipboard` | ❌ | Delete a specific clipboard entry | Keyboard Maestro |
| `styleClipboard` | ❌ | Apply styling to clipboard content | Keyboard Maestro |
| `filterClipboard` | ❌ | Filter clipboard content | Keyboard Maestro |
| `replaceClipboard` | ❌ | Find and replace in clipboard content | Keyboard Maestro |

### 3.6 File System Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `openFile` | ✅ | Open a file with default or specified app | Keyboard Maestro |
| `openFolder` | ✅ | Open a folder in Finder | — |
| `createFile` | ❌ | Create a new file with content | Keyboard Maestro |
| `writeToFile` | ❌ | Write text to a file (overwrite or append) | Keyboard Maestro |
| `readFile` | ❌ | Read file contents into variable | Keyboard Maestro |
| `deleteFile` | ❌ | Delete a file (move to Trash) | Keyboard Maestro |
| `duplicateFile` | ❌ | Duplicate a file | Keyboard Maestro |
| `renameFile` | ❌ | Rename a file | Keyboard Maestro |
| `moveFile` | ❌ | Move a file to a new location | Keyboard Maestro |
| `getFileInfo` | ❌ | Get file metadata (size, date, type) | Keyboard Maestro |
| `getFolderPath` | ❌ | Get system folder paths (Home, Documents, Downloads, etc.) | Keyboard Maestro |
| `listFolder` | ❌ | List contents of a folder | Keyboard Maestro |
| `getFinderFolder` | ❌ | Get the current Finder folder | Keyboard Maestro |
| `setFinderFolder` | ❌ | Set the current Finder folder | Keyboard Maestro |
| `trashFile` | ❌ | Move file to Trash | Keyboard Maestro |
| `getFileSize` | ❌ | Get file size in bytes | — |
| `getFileIcon` | ❌ | Get the icon of a file | — |
| `setFileIcon` | ❌ | Set a custom icon for a file | — |

### 3.7 URL & Web Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `openURL` | ✅ | Open a URL | Anvil |
| `openURLInBrowser` | ❌ | Open URL in specific browser | — |
| `openURLInPrivateWindow` | ❌ | Open URL in private/incognito window | — |
| `downloadURL` | ❌ | Download a URL to a file | Keyboard Maestro |
| `httpRequest` | ✅ | Make an HTTP request (GET/POST/PUT/DELETE) | — |
| `getActiveBrowserTab` | ❌ | Get URL and title of active browser tab | — |
| `runJavaScriptInBrowser` | ❌ | Execute JavaScript in active browser tab | — |
| `selectBrowserTab` | ❌ | Switch to a specific browser tab | Keyboard Maestro |
| `clickBrowserLink` | ❌ | Click a link on the current web page | Keyboard Maestro |
| `setBrowserField` | ❌ | Set a form field value | Keyboard Maestro |
| `setBrowserCheckbox` | ❌ | Set a checkbox state | Keyboard Maestro |
| `setBrowserRadioButton` | ❌ | Select a radio button | Keyboard Maestro |
| `focusBrowserField` | ❌ | Focus a form field | Keyboard Maestro |
| `searchWeb` | ❌ | Search the web using a search engine | — |
| `previousBrowserTab` | ❌ | Switch to previous browser tab | Keyboard Maestro |

### 3.8 Scripting Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `runShell` | ✅ | Execute a shell command (`/bin/sh -c`) | Anvil |
| `runAppleScript` | ✅ | Execute an AppleScript snippet | Anvil |
| `runJavaScript` | ❌ | Execute JavaScript for Automation (JXA) | — |
| `runShellScript` | ❌ | Execute shell script with chosen interpreter | Keyboard Maestro |
| `runShellWithResult` | ❌ | Execute shell command and capture stdout | — |
| `executeRemoteTrigger` | ❌ | Trigger a webhook/remote URL | Keyboard Maestro |

### 3.9 Input Simulation Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `sendKey` | ✅ | Press a key combo | Anvil |
| `consumerKey` | ✅ | Send media key | Anvil |
| `pointingButton` | ✅ | Send mouse click | Anvil |
| `mouseKey` | ✅ | Move mouse / scroll | Anvil |
| `holdDown` | ✅ | Hold a key for duration | Anvil |
| `typeKeystroke` | ❌ | Type a keystroke with optional modifiers | Keyboard Maestro |
| `typeString` | ❌ | Type a string with configurable speed (typing/instant) | Keyboard Cowboy |
| `moveOrClickMouse` | ❌ | Move mouse to coordinates and/or click | Keyboard Maestro |
| `mouseButton` | ❌ | Advanced mouse button control (click/doubleClick/press/release) | — |
| `scrollWheel` | ❌ | Scroll wheel control | — |
| `moveMouse` | ❌ | Move mouse cursor (absolute or relative) | — |
| `clickAtLocation` | ❌ | Click at specific screen coordinates | Keyboard Maestro |

### 3.10 Variable & State Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `setVariable` | ✅ | Set a variable value | Anvil |
| `unsetVariable` | ✅ | Remove a variable | Anvil |
| `toggleVariable` | ✅ | Toggle a boolean variable | Anvil |
| `incrementVariable` | ✅ | Increment a numeric variable | Keyboard Maestro |
| `decrementVariable` | ✅ | Decrement a numeric variable | Keyboard Maestro |
| `setGlobalVariable` | ✅ | Set a persistent global variable (survives restarts) | Keyboard Maestro |
| `getGlobalVariable` | ✅ | Read a persistent global variable | Keyboard Maestro |
| `setNamedClipboard` | ❌ | Set a named clipboard value | Keyboard Maestro |
| `getNamedClipboard` | ❌ | Get a named clipboard value | Keyboard Maestro |
| `calculateVariable` | ❌ | Calculate and store result of expression | Keyboard Maestro |
| `readVariableFromFile` | ❌ | Read variable value from file | Keyboard Maestro |
| `writeVariableToFile` | ❌ | Write variable value to file | Keyboard Maestro |

### 3.11 Control Flow Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `halt` | ✅ | Stop processing further actions | Anvil |
| `delay` | ✅ | Pause before next action | Anvil |
| `disable` | ✅ | Swallow the event | Anvil |
| `ifThenElse` | ❌ | Conditional branching with then/else | Keyboard Maestro |
| `whileLoop` | ❌ | Loop while condition is true | Keyboard Maestro |
| `repeatNTimes` | ❌ | Repeat actions N times | Keyboard Maestro |
| `forEach` | ❌ | Iterate over a list of items | Keyboard Maestro |
| `until` | ❌ | Repeat until condition becomes true | Keyboard Maestro |
| `cancel` | ❌ | Cancel the current macro execution | Keyboard Maestro |
| `pause` | ❌ | Pause macro execution | Keyboard Maestro |
| `executeMacro` | ❌ | Execute another macro by name | Keyboard Maestro |
| `triggerMacro` | ❌ | Trigger a macro by name | Keyboard Maestro |
| `setMacroEnable` | ❌ | Enable or disable a macro | Keyboard Maestro |
| `setMacroGroupEnable` | ❌ | Enable or disable a macro group | Keyboard Maestro |
| `showPalette` | 🔄 | Show a floating macro palette | Keyboard Maestro |
| `hidePalette` | 🔄 | Hide a floating macro palette | Keyboard Maestro |
| `showHUD` | ❌ | Show a heads-up display overlay | Keyboard Maestro |

### 3.12 Image & Screen Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `findImageOnScreen` | ❌ | Find an image on screen and return coordinates | Keyboard Maestro |
| `captureScreen` | ❌ | Capture a screenshot | Keyboard Maestro |
| `captureWindow` | ❌ | Capture a specific window | Keyboard Maestro |
| `cropImage` | ❌ | Crop an image to a rectangle | Keyboard Maestro |
| `annotateImage` | ❌ | Add text annotation to an image | Keyboard Maestro |
| `displayImage` | ❌ | Display an image overlay on screen | Keyboard Maestro |
| `clickAtImage` | ❌ | Click at the location of a found image | Keyboard Maestro |
| `moveMouseToImage` | ❌ | Move mouse to the location of a found image | Keyboard Maestro |
| `readImage` | ❌ | Read text from an image (OCR) | Keyboard Maestro |
| `writeImage` | ❌ | Write an image to a file | Keyboard Maestro |

### 3.13 Notification Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `showNotification` | ✅ | Show a notification (title, subtitle, message) | Anvil |
| `sendEmail` | ❌ | Send an email | — |
| `sendiMessage` | ❌ | Send an iMessage | — |
| `playSound` | ✅ | Play a sound file | Keyboard Maestro |
| `flashScreen` | ✅ | Flash the screen with a color overlay | — |
| `clearNotification` | ❌ | Clear the top notification | — |

### 3.14 Menu Bar Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `selectMenuItem` | ❌ | Select a menu item by path | Keyboard Maestro |
| `clickMenuBarItem` | ❌ | Click a menu bar item with optional deep navigation | Keyboard Cowboy |
| `triggerMenuBarItem` | ❌ | Click a menu bar item by name (accessibility API) | — |
| `getMenuBarItems` | ❌ | List all menu bar items | — |

### 3.15 Interface Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `pressButton` | ❌ | Press a UI button in the frontmost app | Keyboard Maestro |
| `selectFrontBrowserField` | ❌ | Select a field in the front browser | Keyboard Maestro |
| `setFrontBrowserField` | ❌ | Set a field value in the front browser | Keyboard Maestro |
| `setFrontBrowserCheckbox` | ❌ | Set a checkbox state in the front browser | Keyboard Maestro |
| `setFrontBrowserRadioButton` | ❌ | Select a radio button in the front browser | Keyboard Maestro |
| `focusFrontBrowserField` | ❌ | Focus a field in the front browser | Keyboard Maestro |
| `previousFrontBrowserTab` | ❌ | Switch to previous browser tab | Keyboard Maestro |
| `selectFrontBrowserTab` | ❌ | Select a specific browser tab | Keyboard Maestro |
| `clickFrontBrowserLink` | ❌ | Click a link in the front browser | Keyboard Maestro |

### 3.16 Music Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `playTrack` | ❌ | Play a specific track | Keyboard Maestro |
| `pauseMusic` | ❌ | Pause currently playing music | Keyboard Maestro |
| `nextTrack` | ❌ | Skip to next track | Keyboard Maestro |
| `previousTrack` | ❌ | Go to previous track | Keyboard Maestro |
| `fastForward` | ❌ | Fast forward playback | Keyboard Maestro |
| `rewind` | ❌ | Rewind playback | Keyboard Maestro |
| `setMusicVolume` | ❌ | Set Music/iTunes volume | Keyboard Maestro |
| `getNowPlaying` | ❌ | Get current track info | — |

### 3.17 Debugger Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `breakpoint` | ❌ | Pause macro execution at this point | Keyboard Maestro |
| `stepOver` | ❌ | Step over the next action | Keyboard Maestro |
| `stepInto` | ❌ | Step into the next action | Keyboard Maestro |
| `stepOut` | ❌ | Step out of the current action group | Keyboard Maestro |

### 3.18 Stream Deck Integration

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `setStreamDeckKey` | ❌ | Set a Stream Deck key display | Keyboard Maestro |
| `controlStreamDeck` | ❌ | Control Stream Deck device | Keyboard Maestro |

### 3.19 MIDI Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `sendMIDINote` | ❌ | Send a MIDI note | Keyboard Maestro |
| `sendMIDIControlChange` | ❌ | Send a MIDI control change | Keyboard Maestro |
| `sendMIDIPacket` | ❌ | Send arbitrary MIDI data | Keyboard Maestro |

### 3.20 Third-Party Plugin Actions

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `executePluginAction` | ❌ | Execute a third-party plugin action | Keyboard Maestro |

### 3.21 Workspaces & Bundled Commands

| Action | Status | Description | Source |
|--------|--------|-------------|--------|
| `createWorkspace` | ❌ | Bundle multiple apps into a workspace with window arrangement | Keyboard Cowboy |
| `appFocusWithTiling` | ❌ | Focus app with window tiling support (macOS Sequoia) | Keyboard Cowboy |

### 3.22 Token System

| Token Category | Status | Examples | Description |
|---------------|--------|----------|-------------|
| `System` tokens | ❌ | `System:CurrentDate`, `System:CurrentTime`, `System:UserName` | System information tokens |
| `Front` tokens | ❌ | `Front:Application`, `Front:BundleID`, `Front:Name` | Frontmost application tokens |
| `FrontBrowser` tokens | ❌ | `FrontBrowser:URL`, `FrontBrowser:Title` | Front browser tokens |
| `Window` tokens | ❌ | `Window:Title`, `Window:Position`, `Window:Size` | Window information tokens |
| `Clipboard` tokens | ❌ | `Clipboard`, `Clipboard:Length` | Clipboard content tokens |
| `Variable` tokens | ❌ | `Variable:MyVar` | Variable value tokens |
| `Path` tokens | ❌ | `Path:Home`, `Path:Documents`, `Path:Desktop` | System path tokens |
| `Calculation` tokens | ❌ | `Calculate:Expression` | Math expression evaluation tokens |

### 3.23 Macro Groups

| Feature | Status | Description |
|---------|--------|-------------|
| `MacroGroup` | ❌ | A collection of macros that share activation conditions |
| `activeWhen` | ❌ | Conditions under which the group is active (always, app-specific, typed string) |
| `availableWhen` | ❌ | When macros in the group are available to be triggered |
| `deactivateOtherGroups` | ❌ | Whether activating this group deactivates others |

---

## 4. Part Three: Menu Bar & Widget Support

> Custom menu bar items with custom icons, dynamic menus populated from the automation engine, and custom HTML widgets for the desktop.

### 4.1 Menu Bar Item Configuration

| Feature | Status | Description |
|---------|--------|-------------|
| Custom menu bar item creation | ❌ | Create multiple custom menu bar items within the app |
| Custom icon (SF Symbol) | ❌ | Choose from the SF Symbols library for menu bar icon |
| Custom icon (Image file) | ❌ | Import a custom image file as menu bar icon (PNG/SVG, 16x16 recommended) |
| Custom icon (Monogram text) | ❌ | Use a text character/emoji as the menu bar icon |
| Custom icon color | ❌ | Tint the menu bar icon with a custom color |
| Custom menu bar title text | ❌ | Optional text displayed next to the icon |
| Menu bar item visibility rules | ❌ | Show/hide menu bar items based on conditions (app running, time of day, variable state) |
| Menu bar item grouping | ❌ | Group related menu bar items into sections |
| Menu bar item reorder | ❌ | Drag to reorder menu bar items |
| Global hotkey to toggle menu | ❌ | Keyboard shortcut to show/hide a menu bar item's dropdown |

### 4.2 Menu Item Types

| Menu Item Type | Status | Description |
|---------------|--------|-------------|
| Execute Automation Action | ❌ | Run any action from the automation engine (Part Two) |
| Run Shortcut | ❌ | Execute an Apple Shortcut |
| Run Workflow | ❌ | Execute a saved automation workflow |
| Toggle Variable | ❌ | Toggle a variable and show state in menu |
| Separator | ❌ | Visual separator line between menu items |
| Submenu | ❌ | Nested submenu with its own items |
| Dynamic Submenu | ❌ | Auto-populated submenu (running apps, recent files, recent shortcuts) |
| Menu Item with State | ❌ | Menu item that shows checkmark when variable is true |
| Menu Item with Badge | ❌ | Menu item showing a count/value badge |
| Disabled Menu Item | ❌ | Grayed-out menu item with tooltip explaining why |
| URL Link | ❌ | Open a URL when clicked |
| Run AppleScript | ❌ | Execute AppleScript and show result |
| Run Shell Command | ❌ | Execute shell command and show result |
| Widget Trigger | ❌ | Open/show a specific widget |
| Show Notification | ❌ | Show a notification when clicked |

### 4.3 Dynamic Menu Content

| Content Source | Status | Description |
|---------------|--------|-------------|
| Running Applications | ❌ | Auto-populated list of running apps with activate/hide/quit actions |
| Recent Shortcuts | ❌ | Recently executed shortcuts from the automation engine |
| Recent Files | ❌ | Recently opened files |
| Recent Folders | ❌ | Recently accessed folders |
| Clipboard History | ❌ | Recent clipboard items |
| Active Variables | ❌ | Show current variable states |
| Engine Status | ❌ | Show engine running/stopped state, active manipulator count |
| Window List | ❌ | List of windows for the frontmost app |
| Custom List | ❌ | User-defined dynamic list from a script or data source |

### 4.4 Menu Appearance

| Feature | Status | Description |
|---------|--------|-------------|
| Custom menu width | ❌ | Set the dropdown menu width |
| Custom menu background color | ❌ | Theme the dropdown background |
| Icon in menu items | ❌ | Add icons to individual menu items |
| Keyboard shortcuts in menu | ❌ | Display keyboard shortcut next to menu items |
| Searchable menu | ❌ | Add a search/filter field at top of dropdown |
| Menu item tooltip | ❌ | Hover tooltip for menu items |
| Menu item detail text | ❌ | Subtitle/detail text below menu item name |

### 4.5 Widget System

| Feature | Status | Description |
|---------|--------|-------------|
| Custom widget creation | ❌ | Create widgets from within the app |
| Widget templates | ❌ | Pre-built widget templates (clock, system info, quick actions, etc.) |
| Widget placement | ❌ | Place widgets on desktop or in Notification Center |
| Widget refresh interval | ❌ | Configurable auto-refresh (1s, 5s, 30s, 1m, 5m, manual) |
| Widget click actions | ❌ | Configure what happens when widget is clicked (run action, open URL, etc.) |

### 4.6 Custom HTML Widgets

| Feature | Status | Description |
|---------|--------|-------------|
| HTML/CSS/JS widget editor | ❌ | Built-in code editor for writing custom widget HTML |
| Live preview | ❌ | Real-time preview of widget as you edit |
| Variable binding | ❌ | Bind automation engine variables to HTML template variables |
| Action binding | ❌ | Bind HTML element clicks/events to automation engine actions |
| CSS themes | ❌ | Pre-built CSS themes for widgets (dark, light, transparent, etc.) |
| JavaScript API | ❌ | JS API to interact with the automation engine from within the widget |
| `Anvil.getVariable(name)` | ❌ | JS function to read an engine variable |
| `Anvil.setVariable(name, value)` | ❌ | JS function to set an engine variable |
| `Anvil.runAction(action)` | ❌ | JS function to execute an automation action |
| `Anvil.runShortcut(name)` | ❌ | JS function to run a shortcut |
| `Anvil.onVariableChange(name, callback)` | ❌ | JS callback when a variable changes |
| `Anvil.showNotification(message)` | ❌ | JS function to show a notification |
| `Anvil.getClipboard()` | ❌ | JS function to read clipboard |
| `Anvil.setClipboard(text)` | ❌ | JS function to set clipboard |
| Import HTML file | ❌ | Import an external HTML file as a widget |
| Export widget | ❌ | Export a widget as a shareable `.anvil-widget` file |
| Widget store | ❌ | Community widget marketplace |
| Widget iframe sandboxing | ❌ | Each widget runs in an isolated iframe for security |
| Widget local storage | ❌ | Persistent storage for widget state via localStorage |
| Widget fetch API | ❌ | Allow widgets to make HTTP requests to external APIs |
| Widget resize handle | ❌ | Drag to resize widget on desktop |
| Widget always-on-top | ❌ | Keep widget above other windows |

### 4.7 Widget Templates

| Template | Status | Description |
|----------|--------|-------------|
| System Monitor | ❌ | CPU, memory, disk, network usage display |
| Clock / Calendar | ❌ | Customizable clock with date |
| Weather | ❌ | Weather display using external API |
| Quick Actions | ❌ | Grid of buttons that run automation actions |
| Clipboard Manager | ❌ | Recent clipboard items with search |
| Shortcut Launcher | ❌ | Grid of shortcuts to run |
| Variable Display | ❌ | Show current state of engine variables |
| Now Playing | ❌ | Currently playing music track info |
| Battery Monitor | ❌ | Battery level and charging state |
| Todo List | ❌ | Simple todo list with variable persistence |
| Pomodoro Timer | ❌ | Focus timer with automation actions |
| Custom HTML | ❌ | Blank template for custom HTML/CSS/JS |

---

## 5. Part Four: Shortcuts & AppleScript Integration

> Expose the automation engine to Apple's Shortcuts app via native App Intents and to other macOS apps via an AppleScript dictionary, allowing Anvil to be controlled from Shortcuts, Automator, Script Editor, and any other app that supports AppleScript.

### 5.1 Current Implementation

| Feature | Status | Description |
|---------|--------|-------------|
| `OpenKeyEditorIntent` | ✅ | Siri/Shortcuts integration — phrase: "Open KeyCommand" |
| `ShortcutsService` | ✅ | AppleScript bridge for running/listening shortcuts |
| `runShortcut` action | ✅ | Run a macOS Shortcut from within the remap engine |

### 5.2 Limitations

- ❌ **Fragile AppleScript bridge**: Relies on process execution (`osascript`), not native Shortcuts API
- ❌ **Synchronous execution**: Blocks on AppleScript completion (dispatched to background queue)
- ❌ **No input/output passing**: Can run shortcuts but cannot pass input or receive output
- ❌ **No Shortcuts action provider**: Anvil cannot expose actions TO the Shortcuts app
- ❌ **No Shortcuts trigger source**: Anvil events cannot trigger Shortcuts automations
- ❌ **No two-way integration**: Shortcuts cannot read or modify Anvil state
- ❌ **No AppleScript dictionary**: No scripting interface for external app integration

### 5.3 Anvil as a Shortcuts Action Provider

#### Remap Engine Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `SetRemapVariable` | ❌ | `name`, `value` | — | Set a variable in the remap engine |
| `GetRemapVariable` | ❌ | `name` | `value` | Get a variable from the remap engine |
| `ToggleRemapVariable` | ❌ | `name` | `newValue` | Toggle a boolean variable |
| `GetEngineStatus` | ❌ | — | `running`, `activeManipulators` | Get engine status |
| `SetEngineEnabled` | ❌ | `enabled` | — | Enable/disable the remap engine |
| `GetActiveManipulators` | ❌ | — | `[Manipulator]` | List all active manipulators |
| `EnableManipulator` | ❌ | `id` | — | Enable a specific manipulator |
| `DisableManipulator` | ❌ | `id` | — | Disable a specific manipulator |

#### Application Control Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `OpenApplication` | ❌ | `app` | — | Launch an application |
| `ActivateApplication` | ❌ | `app` | — | Bring app to foreground |
| `HideApplication` | ❌ | `app` | — | Hide an application |
| `QuitApplication` | ❌ | `app` | — | Quit an application |
| `GetRunningApplications` | ❌ | — | `[App]` | List running applications |
| `AppFocus` | ❌ | `app`, `hideOthers` | — | Focus app with window management |

#### Window Management Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `MoveWindow` | ❌ | `x`, `y` | — | Move frontmost window |
| `ResizeWindow` | ❌ | `width`, `height` | — | Resize frontmost window |
| `CenterWindow` | ❌ | — | — | Center the frontmost window |
| `TileWindow` | ❌ | `position` | — | Tile window (left/right/top/bottom/quarters) |
| `MinimizeWindow` | ❌ | — | — | Minimize the frontmost window |
| `CloseWindow` | ❌ | — | — | Close the frontmost window |
| `GetWindowSize` | ❌ | — | `width`, `height` | Get frontmost window size |
| `GetWindowTitle` | ❌ | — | `title` | Get frontmost window title |

#### System Control Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `SetSystemVolume` | ❌ | `level` | — | Set system volume |
| `GetSystemVolume` | ❌ | — | `level` | Get system volume |
| `ToggleMute` | ❌ | — | `muted` | Toggle mute |
| `SetBrightness` | ❌ | `level` | — | Set display brightness |
| `ToggleDarkMode` | ❌ | — | `darkMode` | Toggle Dark/Light mode |
| `LockScreen` | ❌ | — | — | Lock the screen |
| `SleepSystem` | ❌ | — | — | Put Mac to sleep |
| `GetBatteryState` | ❌ | — | `level`, `charging` | Get battery info |

#### Text & Clipboard Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `GetSelectedText` | ❌ | — | `text` | Get selected text from frontmost app |
| `TransformText` | ❌ | `text`, `operation` | `result` | Transform text (upper, lower, camel, snake, etc.) |
| `ReplaceText` | ❌ | `text`, `find`, `replace` | `result` | Find and replace text |
| `CalculateExpression` | ❌ | `expression` | `result` | Evaluate a math expression |
| `GetClipboardText` | ❌ | — | `text` | Get clipboard text |
| `SetClipboardText` | ❌ | `text` | — | Set clipboard text |

#### File, Web & Scripting Intents

| Shortcuts Intent | Status | Input | Output | Description |
|------------------|--------|-------|--------|-------------|
| `ReadFile` | ❌ | `path` | `content` | Read file contents |
| `WriteToFile` | ❌ | `path`, `content` | — | Write content to file |
| `ListFolder` | ❌ | `path` | `[FileItem]` | List folder contents |
| `OpenURL` | ❌ | `url`, `browser` | — | Open URL in browser |
| `HttpRequest` | ❌ | `url`, `method`, `headers`, `body` | `response` | Make HTTP request |
| `RunShellCommand` | ❌ | `command` | `output` | Execute shell command |
| `RunAppleScript` | ❌ | `script` | `result` | Execute AppleScript |
| `ShowAnvilNotification` | ❌ | `title`, `message` | — | Show a notification |
| `TriggerMenuBarItem` | ❌ | `itemName` | — | Click a menu bar item |

### 5.4 Anvil as a Shortcuts Trigger Source

| Trigger | Status | Parameters | Description |
|---------|--------|-----------|-------------|
| `WhenVariableChanges` | ❌ | `variableName` | Trigger when an engine variable changes value |
| `WhenManipulatorFires` | ❌ | `manipulatorID` | Trigger when a specific manipulator is activated |
| `WhenEngineStarts` | ❌ | — | Trigger when the remap engine starts |
| `WhenEngineStops` | ❌ | — | Trigger when the remap engine stops |
| `WhenAppBecomesFrontmost` | ❌ | `appBundleID` | Trigger when a specific app becomes frontmost |
| `WhenDeviceConnects` | ❌ | `deviceType` | Trigger when a keyboard/mouse connects |
| `WhenDeviceDisconnects` | ❌ | `deviceType` | Trigger when a keyboard/mouse disconnects |
| `WhenInputSourceChanges` | ❌ | `inputSourceID?` | Trigger when keyboard input source changes |
| `MenuBarItemClicked` | ❌ | `itemName` | Trigger when a custom menu bar item is clicked |
| `WidgetInteraction` | ❌ | `widgetID`, `event` | Trigger on widget events (click, hover, etc.) |

### 5.5 AppleScript Dictionary

> Expose Anvil's automation engine as an AppleScript scripting addition so other apps (Automator, Script Editor, FastScripts, hammerspoon, etc.) can programmatically control Anvil.

#### Engine Control

| Command | Status | Returns | Description |
|---------|--------|---------|-------------|
| `startEngine` | ❌ | `boolean` | Start the remap engine |
| `stopEngine` | ❌ | `boolean` | Stop the remap engine |
| `toggleEngine` | ❌ | `boolean` | Toggle engine on/off, returns new state |
| `engineStatus` | ❌ | `record {running, activeCount}` | Get engine running state |

#### Variable Management

| Command | Status | Returns | Description |
|---------|--------|---------|-------------|
| `setVariable "name" to "value"` | ❌ | `boolean` | Set a variable value |
| `getVariable "name"` | ❌ | `string` | Get a variable value |
| `toggleVariable "name"` | ❌ | `string` | Toggle a boolean variable, returns new value |
| `unsetVariable "name"` | ❌ | `boolean` | Remove a variable |
| `getAllVariables` | ❌ | `record` | Get all variables as a key-value record |
| `variableExists "name"` | ❌ | `boolean` | Check if a variable exists |

#### Manipulator Control

| Command | Status | Returns | Description |
|---------|--------|---------|-------------|
| `enableManipulator "id"` | ❌ | `boolean` | Enable a manipulator by ID |
| `disableManipulator "id"` | ❌ | `boolean` | Disable a manipulator by ID |
| `toggleManipulator "id"` | ❌ | `boolean` | Toggle a manipulator, returns new state |
| `manipulatorEnabled "id"` | ❌ | `boolean` | Check if a manipulator is enabled |
| `getManipulators` | ❌ | `list of records` | List all manipulators with id, name, enabled state |
| `enableAllManipulators` | ❌ | `integer` | Enable all manipulators, returns count |
| `disableAllManipulators` | ❌ | `integer` | Disable all manipulators, returns count |

#### Action Execution

| Command | Status | Returns | Description |
|---------|--------|---------|-------------|
| `runAction "name" withParameters {...}` | ❌ | `boolean` | Execute any automation engine action |
| `sendKey "a" withModifiers {command}` | ❌ | `boolean` | Send a key combination |
| `sendText "hello"` | ❌ | `boolean` | Type text |
| `openApp "com.apple.Safari"` | ❌ | `boolean` | Launch an application |
| `openURL "https://example.com"` | ❌ | `boolean` | Open a URL |
| `runShell "echo hello"` | ❌ | `string` | Execute shell command, return stdout |
| `runAppleScript "return \"hello\""` | ❌ | `string` | Execute AppleScript, return result |
| `showNotification "message"` | ❌ | `boolean` | Show a notification |
| `runShortcut "My Shortcut"` | ❌ | `boolean` | Run a macOS Shortcut |

#### Data Queries

| Command | Status | Returns | Description |
|---------|--------|---------|-------------|
| `getClipboard` | ✅ | `string` | Get clipboard text |
| `setClipboard "text"` | ❌ | `boolean` | Set clipboard text |
| `getSelectedText` | ✅ | `string` | Get selected text from frontmost app |
| `getFrontmostApp` | ❌ | `record {name, bundleID}` | Get frontmost application info |
| `getRunningApps` | ❌ | `list of records` | List running applications |
| `getActiveManipulators` | ❌ | `list of records` | List only enabled manipulators |

#### AppleScript Examples

```applescript
-- Toggle dark mode
tell application "Anvil"
    set currentMode to getVariable "darkMode"
    if currentMode is "true" then setVariable "darkMode" to "false" else setVariable "darkMode" to "true"
end tell

-- Launch app only if not running
tell application "Anvil"
    set runningApps to getRunningApps
    set appRunning to false
    repeat with appInfo in runningApps
        if bundleID of appInfo is "com.apple.Terminal" then set appRunning to true
    end repeat
    if not appRunning then openApp "com.apple.Terminal"
end tell

-- Run a shell command and notify
tell application "Anvil"
    set gitStatus to runShell "git status --short"
    if gitStatus is not "" then showNotification "Git repo has changes"
end tell

-- Conditional action based on variable state
tell application "Anvil"
    set workMode to getVariable "workMode"
    if workMode is "true" then
        openApp "com.apple.dt.Xcode"
        setVariable "focusLevel" to "high"
    else
        openApp "com.apple.Safari"
    end if
end tell
```

#### AppleScript Suites

| Suite | Commands | Description |
|-------|----------|-------------|
| `Engine` | `startEngine`, `stopEngine`, `toggleEngine`, `engineStatus` | Engine lifecycle control |
| `Variables` | `setVariable`, `getVariable`, `toggleVariable`, `unsetVariable`, `getAllVariables`, `variableExists` | Variable read/write |
| `Manipulators` | `enableManipulator`, `disableManipulator`, `toggleManipulator`, `manipulatorEnabled`, `getManipulators`, `enableAllManipulators`, `disableAllManipulators` | Manipulator management |
| `Actions` | `runAction`, `sendKey`, `sendText`, `openApp`, `openURL`, `runShell`, `runAppleScript`, `showNotification`, `runShortcut` | Execute automation actions |
| `Queries` | `getClipboard`, `setClipboard`, `getSelectedText`, `getFrontmostApp`, `getRunningApps`, `getActiveManipulators` | Read system/app state |

#### Implementation Notes

| Aspect | Status | Description |
|--------|--------|-------------|
| Scripting bridge definition (`.sdef`) | ❌ | Define the dictionary in `Anvil.sdef` |
| `NSAppleScript` handler support | ❌ | Implement `handleAppleScript:` in `NSApplicationDelegate` |
| Return value serialization | ❌ | Convert Swift types to `NSAppleEventDescriptor` |
| Error handling | ❌ | Return `NSError` with codes for invalid parameters |
| Thread safety | ❌ | All AppleScript calls route through `RemapStore` on main queue |
| Permission check | ❌ | Verify Accessibility permission before engine commands |

### 5.6 Shortcuts Phrases

| Phrase | Intent | Status |
|--------|--------|--------|
| "Open KeyCommand" | `OpenKeyEditorIntent` | ✅ |
| "Run [Shortcut Name]" | `RunShortcutIntent` | ❌ |
| "Set [Variable] to [Value]" | `SetRemapVariableIntent` | ❌ |
| "Get [Variable]" | `GetRemapVariableIntent` | ❌ |
| "Toggle engine" | `SetEngineEnabledIntent` | ❌ |
| "Show engine status" | `GetEngineStatusIntent` | ❌ |

---

## Appendix A: Default Test Manipulators

The app ships with **50 test manipulators** demonstrating:

| # | Name | Feature Demonstrated |
|---|------|---------------------|
| 1 | Consumer Key Trigger (Volume Down) | `consumer_key_code` as trigger |
| 2 | Pointing Button Trigger (Right Click) | `pointing_button` as trigger |
| 3 | Any Key Trigger | `any` key wildcard |
| 4 | Mandatory Modifier: Caps Lock | `caps_lock` modifier matching |
| 5 | Fn Modifier Trigger | `fn` modifier tracking |
| 6 | Optional Modifiers | Optional modifier matching |
| 7 | Simultaneous Chord Trigger | Basic chord (j+k) |
| 8 | Simultaneous Chord Strict Order | Strict key-down order |
| 9 | Consumer Key Action (Volume Up) | `consumerKey` action |
| 10 | Pointing Button Action (Left Click) | `pointingButton` action |
| 11 | Mouse Key Action (Move Right 50px) | `mouseKey` movement |
| 12 | Mouse Key Action (Scroll Down) | `mouseKey` scroll |
| 13 | Sticky Modifier Action | `stickyModifier` toggle |
| 14 | Halt Action | `halt` action ordering |
| 15 | Hold Down Action (500ms) | `holdDown` duration |
| 16 | Notification Action | `setNotification` |
| 17 | From Event Action (Mirror) | `fromEvent` pass-through |
| 18 | Software Function: Double Click | `softwareFunction` double-click |
| 19 | Software Function: Sleep System | `softwareFunction` sleep |
| 20 | Condition: Device Exists | `deviceExists` condition |
| 21 | Condition: Expression (Variable == Value) | `expression` condition |
| 22 | Condition: Event Changed (Keyboard Type) | `eventChanged` condition |
| 23 | Lazy Modifier Action | `isLazy` modifier behavior |
| 24 | Per-Action Conditions | `to.conditions` on individual actions |
| 25 | Select Input Source (ABC) | `selectInputSource` action |
| 26 | Mouse Basic (Middle Button Remap) | `mouseBasic` manipulator type |
| 27 | Mouse Motion to Scroll | `mouseMotionToScroll` type |
| 28 | Repeat Disabled Action | `isRepeatEnabled` = false |
| 29 | Variable Set + Toggle | `setVariable` + `toggleVariable` |
| 30 | Sequence Trigger (a → b → c) | Multi-step sequence trigger |
| 31 | String Trigger (teh → autocorrect) | Typed string full-match autocorrect |
| 32 | String Trigger (Safari-only) | App-specific typed string trigger |
| 33 | If Other Key Pressed (tap vs combo) | `ifOtherKeyPressed` + `ifAlone` fire modes |
| 34 | Named Trigger: Subroutine | `triggerName` for programmatic invocation |
| 35 | Execute Named Trigger | `executeNamedTrigger` action |
| 36 | Hot Key: Double-Tap 'z' | Multi-tap (tapCount=2) |
| 37 | Hot Key: Triple-Tap 'x' | Multi-tap (tapCount=3) |
| 38 | Hot Key: Tap Count Actions (1×copy 2×cut 3×paste) | Per-action tapCount |
| 39 | Hot Key: Double-Tap & Hold 'v' | Multi-tap + holdRequired |
| 40 | Modifier Key Trigger (Right Command) | Modifier key as trigger (flagsChanged dispatch fix) |
| 41 | Window Action (⌃⌥← → Left Half) | `windowAction` AX window snapping |
| 42 | Window Action (⌃⌥→ → Right Half) | `windowAction` second kind |
| 43 | Toggle Dark Mode (⌃⌥D) | `toggleDarkMode` action |
| 44 | Transform Clipboard to UPPERCASE (⌃⌥U) | `transformText` action |
| 45 | Set Volume 25% + Ping (⌃⌥V) | `setVolume` + `playSound` actions |
| 46 | Speak Text (⌃⌥S) | `speakText` text-to-speech |
| 47 | Increment Counter (⌃⌥I) | `incrementVariable` action |
| 48 | Battery & IP → Variables (⌃⌥B) | `getBatteryState` + `getIPAddress` actions |
| 49 | Flash Screen (⌃⌥F) | `flashScreen` visual feedback |
| 50 | Activate Last App (⌃⌥Tab) / HTTP Request (⌃⌥H) | `activateLastApp`, `httpRequest` actions |

---

## Appendix B: Feature Roadmap

### P0 (Next): Must-Have for MVP

| # | Feature | Part | Effort | Status |
|---|---------|------|--------|--------|
| 1 | FSEvents config watching (replace Timer polling) | Core | S | 🔄 |
| 2 | Accessibility permission better UX | Core | S | 🔄 |
| 3 | Drag and drop manipulator reordering | Remap | S | ❌ |
| 4 | Export/import individual manipulators | Remap | S | 🔄 |
| 5 | Undo/redo for manipulator edits | Remap | M | ❌ |
| 6 | `anvil://` URL scheme | Shortcuts | S | ❌ |
| 7 | AppleScript dictionary (`.sdef` + `handleAppleScript:`) | Shortcuts | M | ❌ |

### P1 (Soon): Important for Usability

| # | Feature | Part | Effort |
|---|---------|------|--------|
| 8 | **Get Selected Text** action | Automation | S |
| 9 | **Toggle Dark/Light Appearance** action | Automation | S |
| 10 | **Trigger Menu Bar Item** action | Automation | M |
| 11 | **Text Transform** actions | Automation | M |
| 12 | **HTTP Request** action | Automation | M |
| 13 | **Window Management** actions (tile, move, resize, zoom) | Automation | M |
| 14 | **Clipboard** actions (get, set, append) | Automation | S |
| 15 | **Audio Volume** actions (get, set, mute) | Automation | S |
| 16 | Native App Intents provider (beyond AppleScript) | Shortcuts | M |
| 17 | Shortcut input/output passing | Shortcuts | M |
| 18 | Manipulator groups/folders in sidebar | Remap | S |
| 19 | Custom menu bar items (SF Symbol icons) | Menu Bar | M |
| 20 | Menu bar items with automation actions | Menu Bar | M |
| 21 | Config profiles (switch between config sets) | Core | 🔄 |
| 22 | Unit tests for engine | Core | M |

### P2 (Later): Enhancement

| # | Feature | Part | Effort |
|---|---------|------|--------|
| 23 | Visual keyboard editor | Remap | ✅ Small |
| 24 | Record mode (keystroke recorder) | Remap | 🔄 L |
| 25 | Custom menu bar icons (image import) | Menu Bar | S |
| 26 | Dynamic menu content (running apps, recent files) | Menu Bar | M |
| 27 | Menu bar visibility rules | Menu Bar | M |
| 28 | Custom HTML widget editor | Widget | L |
| 29 | Widget JavaScript API | Widget | L |
| 30 | Widget templates | Widget | M |
| 31 | Two-way Shortcuts config sync | Shortcuts | L |
| 32 | Named Clipboard slots | Automation | S |
| 33 | File System actions | Automation | M |
| 34 | Debug panel | Core | M |
| 35 | Shortcuts trigger source | Shortcuts | L |
| 36 | Widget store (community widgets) | Widget | XL |

### P3 (Stretch): Vision

| # | Feature | Part | Effort |
|---|---------|------|--------|
| 37 | Command palette overlay (Raycast/Alfred-style) | Core | XL |
| 38 | Plugin/extension system (JavaScript/Python) | Core | XL |
| 39 | Visual workflow builder (drag-and-drop) | Core | XL |
| 40 | Community manipulator library | Remap | L |
| 41 | MIDI actions | Automation | M |
| 42 | Stream Deck integration | Automation | L |
| 43 | iCloud sync for config | Core | L |
| 44 | Macro Groups (Keyboard Maestro-style) | Automation | L |
| 45 | Token system | Automation | L |

---

*Generated from source code analysis and external research (Karabiner Elements, Keyboard Maestro, Keyboard Cowboy). Last updated: 2026-07-01.*
