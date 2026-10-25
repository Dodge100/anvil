import AppKit
import SwiftUI

/// Shared number formatter — `NumberFormatter()` init is expensive and was
/// previously constructed inline in `body` on every render.
extension NumberFormatter {
    static let sharedInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

// MARK: - Condition step row

struct ConditionStepRow: View {
    let condition: Condition
    let onChange: ((inout Condition) -> Void) -> Void
    let onDelete: () -> Void
    var onChangeKind: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil

    @State private var installedApps: [InstalledApp] = []

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(condition.kind.rawValue, systemImage: condition.kind.symbol)
                    
                    if condition.kind != .deviceExists && condition.kind != .expression && condition.kind != .eventChanged {
                        Picker("Comparison", selection: opBinding) {
                            ForEach(ComparisonOp.allCases) { op in
                                Text(op.rawValue).tag(op)
                            }
                        }
                        .labelsHidden()
                    }

                    Spacer()

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                // Value field based on condition type
                if condition.kind == .variable || condition.kind == .globalVariable {
                    TextField("Variable name", text: targetBinding)
                    if isBoolValue(condition.value) {
                        Toggle("Expected value", isOn: variableBoolBinding)
                    } else {
                        TextField("Expected value", text: variableValueBinding)
                    }
                    Button(isBoolValue(condition.value) ? "Use text value" : "Use true/false") {
                        let current = condition.value
                        var newValue: String
                        if isBoolValue(current) {
                            newValue = current == "true" ? "yes" : ""
                        } else {
                            newValue = current == "1" || current == "yes" ? "true" : "false"
                        }
                        onChange { $0.value = newValue }
                    }
                } else if condition.kind == .frontmostApp || condition.kind == .frontmostAppName {
                    TextField("Value", text: targetBinding, prompt: Text(condition.kind.placeholder))
                        .labelsHidden()
                    AppPicker(installedApps: installedApps) { app in
                        onChange { condition in
                            condition.target = condition.kind == .frontmostAppName
                                ? app.name
                                : app.bundleID
                        }
                    }
                    .onAppear(perform: loadInstalledApps)
                } else if condition.kind == .expression {
                    TextField("Expression", text: targetBinding, prompt: Text("e.g. my_var == \"hello\""))
                        .labelsHidden()
                } else if condition.kind == .eventChanged {
                    Picker("Event type", selection: targetBinding) {
                        Text("Keyboard Type").tag("keyboard_type")
                        Text("Device").tag("device")
                    }
                } else {
                    TextField("Value", text: targetBinding, prompt: Text(condition.kind.placeholder))
                        .labelsHidden()
                }

                Text(condition.kind.helpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Change Type…") { onChangeKind?() }
            if onMoveUp != nil || onMoveDown != nil {
                Divider()
                Button("Move Up", action: onMoveUp ?? {})
                Button("Move Down", action: onMoveDown ?? {})
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func loadInstalledApps() {
        Task(priority: .userInitiated) { @MainActor in
            installedApps = InstalledApp.allInstalledApps()
        }
    }

    private var kindBinding: Binding<ConditionKind> {
        Binding(
            get: { condition.kind },
            set: { newValue in onChange { $0.kind = newValue } }
        )
    }

    private var opBinding: Binding<ComparisonOp> {
        Binding(
            get: { condition.op },
            set: { newValue in onChange { $0.op = newValue } }
        )
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { condition.target },
            set: { newValue in onChange { $0.target = newValue } }
        )
    }

    private var variableValueBinding: Binding<String> {
        Binding(
            get: { condition.value },
            set: { newValue in onChange { $0.value = newValue } }
        )
    }

    private func isBoolValue(_ value: String) -> Bool {
        value == "true" || value == "false"
    }

    private var variableBoolBinding: Binding<Bool> {
        Binding(
            get: { condition.value == "true" },
            set: { newValue in onChange { $0.value = newValue ? "true" : "false" } }
        )
    }
}

// MARK: - App picker

private struct AppPicker: View {
    let installedApps: [InstalledApp]
    let onSelect: (InstalledApp) -> Void

    var body: some View {
        Menu("Choose app") {
            if installedApps.isEmpty {
                Text("Scanning applications…")
            } else {
                ForEach(installedApps) { app in
                    Button(app.name) {
                        onSelect(app)
                    }
                }
            }
        }
        .help("Choose an installed app")
    }
}

// MARK: - Action step row

struct ActionStepRow: View {
    @ObservedObject var store: RemapStore
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void
    let onDelete: () -> Void
    var onChangeKind: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                actionEditor
                actionModifiersSection
                fireModeSection
                
                HStack {
                    if let onChangeKind = onChangeKind {
                        Button("Change Type…", action: onChangeKind)
                    }
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        } label: {
            Label(action.kind.rawValue, systemImage: action.kind.symbol)
            
            if !action.summary.isEmpty {
                Text(action.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button("Change Type…") { onChangeKind?() }
            if onMoveUp != nil || onMoveDown != nil || onDuplicate != nil {
                Divider()
                Button("Move Up", action: onMoveUp ?? {})
                Button("Move Down", action: onMoveDown ?? {})
                Button("Duplicate", action: onDuplicate ?? {})
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var actionEditor: some View {
        switch action.kind {
        case .sendKey: SendKeyEditor(store: store, action: action, onChange: onChange)
        case .sendText: SendTextEditor(action: action, onChange: onChange)
        case .setVariable: SetVariableEditor(action: action, onChange: onChange)
        case .unsetVariable: UnsetVariableEditor(action: action, onChange: onChange)
        case .toggleVariable: ToggleVariableEditor(action: action, onChange: onChange)
        case .runShell: RunShellEditor(action: action, onChange: onChange)
        case .openApp: OpenAppEditor(action: action, onChange: onChange)
        case .openURL: OpenURLEditor(action: action, onChange: onChange)
        case .runShortcut: RunShortcutEditor(action: action, onChange: onChange)
        case .runAppleScript: RunAppleScriptEditor(action: action, onChange: onChange)
        case .delay: DelayEditor(action: action, onChange: onChange)
        case .disable: Text("This action swallows the keypress entirely so the system never sees it.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .consumerKey: ConsumerKeyEditor(action: action, onChange: onChange)
        case .pointingButton: PointingButtonEditor(action: action, onChange: onChange)
        case .mouseKey: MouseKeyEditor(action: action, onChange: onChange)
        case .stickyModifier: StickyModifierEditor(action: action, onChange: onChange)
        case .halt: Text("Stops processing further actions in this manipulator. Useful with conditions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .holdDown: HoldDownEditor(store: store, action: action, onChange: onChange)
        case .selectInputSource: SelectInputSourceEditor(action: action, onChange: onChange)
        case .setNotification: SetNotificationEditor(action: action, onChange: onChange)
        case .fromEvent: Text("Mirrors the original trigger event. Sends whatever key was originally pressed.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .softwareFunction: SoftwareFunctionEditor(action: action, onChange: onChange)
        case .sendUserCommand: SendUserCommandEditor(action: action, onChange: onChange)
        case .executeNamedTrigger: ExecuteNamedTriggerEditor(action: action, onChange: onChange)
        case .setGlobalVariable: SetVariableEditor(action: action, onChange: onChange)
        case .unsetGlobalVariable: UnsetVariableEditor(action: action, onChange: onChange)
        case .showPalette:
            Text("Shows the floating macro palette.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .hidePalette:
            Text("Hides the floating macro palette.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .getSelectedText:
            Text("Gets the currently selected text from the frontmost application and stores it for use by later actions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .setClipboard:
            SetClipboardEditor(action: action, onChange: onChange)
        case .getClipboard:
            Text("Reads the current clipboard content and stores it for use by later actions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .clearClipboard:
            Text("Clears the system clipboard.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .activateApp, .hideApp, .unhideApp, .quitApp, .forceQuitApp:
            OpenAppEditor(action: action, onChange: onChange)
        case .activateLastApp:
            Text("Switches back to the previously active application.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .windowAction:
            WindowActionEditor(action: action, onChange: onChange)
        case .lockScreen:
            Text("Locks the screen (switches to the login window).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .showDesktop:
            Text("Shows the desktop by pushing all windows aside.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .missionControl:
            Text("Activates Mission Control.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .toggleDarkMode:
            Text("Toggles between Dark and Light appearance.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .setVolume:
            SetVolumeEditor(action: action, onChange: onChange)
        case .muteSystem:
            Text("Toggles system audio mute on/off.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .emptyTrash:
            Text("Empties the Trash via Finder.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .getBatteryState:
            Text("Stores battery level in `batteryLevel` and charging state in `batteryCharging` variables.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .getIPAddress:
            Text("Stores the current IP address in the `ipAddress` variable.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .toggleHiddenFiles:
            Text("Toggles hidden file visibility in Finder (restarts Finder).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .logOut:
            Text("Logs out the current user (asks for confirmation).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .restartSystem:
            Text("Restarts the Mac (asks for confirmation).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .shutdownSystem:
            Text("Shuts down the Mac (asks for confirmation).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .speakText:
            SendTextEditor(action: action, onChange: onChange)
        case .transformText:
            TransformTextEditor(action: action, onChange: onChange)
        case .calculateExpression:
            CalculateExpressionEditor(action: action, onChange: onChange)
        case .incrementVariable, .decrementVariable:
            StepVariableEditor(action: action, onChange: onChange)
        case .appendClipboard:
            SetClipboardEditor(action: action, onChange: onChange)
        case .pasteClipboard:
            Text("Pastes the current clipboard by sending ⌘V.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .httpRequest:
            HTTPRequestEditor(action: action, onChange: onChange)
        case .openFile, .openFolder:
            FilePathEditor(action: action, onChange: onChange)
        case .playSound:
            PlaySoundEditor(action: action, onChange: onChange)
        case .flashScreen:
            Text("Flashes the screen with a brief white overlay — useful as visual feedback for a macro.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var actionModifiersSection: some View {
        Group {
            Toggle("Lazy modifier", isOn: lazyBinding)
                .help("Modifier does not apply until another key is pressed")

            Picker("Key repeat", selection: repeatBinding) {
                Text("Default").tag(Optional<Bool>.none)
                Text("Enable").tag(Optional<Bool>.some(true))
                Text("Disable").tag(Optional<Bool>.some(false))
            }
            .help("Override key repeat behavior")
        }
    }

    private var fireModeSection: some View {
        Group {
            Picker("When", selection: fireModeBinding) {
                ForEach(ActionFireMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .help(action.fireMode.helpText)
            Text(action.fireMode.helpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var fireModeBinding: Binding<ActionFireMode> {
        Binding(
            get: { action.fireMode },
            set: { newValue in onChange { $0.fireMode = newValue } }
        )
    }

    private var lazyBinding: Binding<Bool> {
        Binding(
            get: { action.isLazy },
            set: { newValue in onChange { $0.isLazy = newValue } }
        )
    }

    private var repeatBinding: Binding<Bool?> {
        Binding(
            get: { action.isRepeatEnabled },
            set: { newValue in onChange { $0.isRepeatEnabled = newValue } }
        )
    }
}

// MARK: - New action editors

private struct ConsumerKeyEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Picker("Consumer Key", selection: consumerBinding) {
            Text("None").tag(Optional<ConsumerKeyCode>.none)
            ForEach(ConsumerKeyCode.allCases) { key in
                Text(key.label).tag(Optional.some(key))
            }
        }
    }

    private var consumerBinding: Binding<ConsumerKeyCode?> {
        Binding(
            get: { action.consumerKey },
            set: { newValue in onChange { $0.consumerKey = newValue } }
        )
    }
}

private struct PointingButtonEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Picker("Mouse Button", selection: buttonBinding) {
            Text("None").tag(Optional<PointingButton>.none)
            ForEach(PointingButton.allCases) { btn in
                Text(btn.label).tag(Optional.some(btn))
            }
        }
    }

    private var buttonBinding: Binding<PointingButton?> {
        Binding(
            get: { action.pointingButton },
            set: { newValue in onChange { $0.pointingButton = newValue } }
        )
    }
}

private struct MouseKeyEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("Move X", value: xBinding, formatter: NumberFormatter.sharedInteger)
            TextField("Move Y", value: yBinding, formatter: NumberFormatter.sharedInteger)
            TextField("Vertical scroll", value: vScrollBinding, formatter: NumberFormatter.sharedInteger)
            TextField("Horizontal scroll", value: hScrollBinding, formatter: NumberFormatter.sharedInteger)
            LabeledContent("Speed") {
                Slider(value: speedBinding, in: 0.1...10)
            }
        }
    }

    private var xBinding: Binding<Int> {
        Binding(
            get: { action.mouseKey.x },
            set: { newValue in onChange { $0.mouseKey.x = newValue } }
        )
    }

    private var yBinding: Binding<Int> {
        Binding(
            get: { action.mouseKey.y },
            set: { newValue in onChange { $0.mouseKey.y = newValue } }
        )
    }

    private var vScrollBinding: Binding<Int> {
        Binding(
            get: { action.mouseKey.verticalWheel },
            set: { newValue in onChange { $0.mouseKey.verticalWheel = newValue } }
        )
    }

    private var hScrollBinding: Binding<Int> {
        Binding(
            get: { action.mouseKey.horizontalWheel },
            set: { newValue in onChange { $0.mouseKey.horizontalWheel = newValue } }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { action.mouseKey.speedMultiplier },
            set: { newValue in onChange { $0.mouseKey.speedMultiplier = newValue } }
        )
    }
}

private struct StickyModifierEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            Picker("Modifier", selection: modBinding) {
                ForEach(ModifierKey.flagBased, id: \.self) { mod in
                    Text(mod.longName).tag(mod)
                }
            }

            Picker("Action", selection: kindBinding) {
                ForEach(StickyModifierKind.allCases) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
        }
    }

    private var modBinding: Binding<ModifierKey> {
        Binding(
            get: { action.stickyModifier.modifier },
            set: { newValue in onChange { $0.stickyModifier.modifier = newValue } }
        )
    }

    private var kindBinding: Binding<StickyModifierKind> {
        Binding(
            get: { action.stickyModifier.kind },
            set: { newValue in onChange { $0.stickyModifier.kind = newValue } }
        )
    }
}

private struct HoldDownEditor: View {
    @ObservedObject var store: RemapStore
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            LabeledContent("Key") {
                HStack {
                    KeyComboCaptureField(
                        isRecording: store.isCapturingToKey,
                        displayLabel: action.toKey.isEmpty ? "" : KeyShortcut(mandatoryModifiers: action.toModifiers, key: action.toKey).displayLabel,
                        onStart: { store.startSendKeyCapture(for: action.id) },
                        onStop: { store.stopToKeyCapture() }
                    )
                    KeyPickerMenu { picked in
                        onChange { action in
                            action.toKey = picked
                            action.toModifiers = []
                        }
                    }
                }
            }
            TextField("Hold duration (ms)", value: holdBinding, formatter: NumberFormatter.sharedInteger)
        }
    }

    private var holdBinding: Binding<Int> {
        Binding(
            get: { action.holdDownMilliseconds },
            set: { newValue in onChange { $0.holdDownMilliseconds = max(0, newValue) } }
        )
    }
}

private struct SelectInputSourceEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Input source ID (e.g. com.apple.keylayout.ABC)", text: inputBinding)
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { action.inputSourceID },
            set: { newValue in onChange { $0.inputSourceID = newValue } }
        )
    }
}

private struct SetNotificationEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Notification message", text: messageBinding)
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { action.notificationMessage },
            set: { newValue in onChange { $0.notificationMessage = newValue } }
        )
    }
}

private struct SoftwareFunctionEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            Picker("Function", selection: functionBinding) {
                ForEach(SoftwareFunctionKind.allCases) { fn in
                    Text(fn.rawValue).tag(fn)
                }
            }

            if action.softwareFunction == .openApplication {
                TextField("App bundle ID, path, or name", text: appPathBinding)
            }

            if action.softwareFunction == .setCursorPosition {
                TextField("X (screen coordinates)", value: cursorXBinding, formatter: NumberFormatter.sharedInteger)
                TextField("Y (screen coordinates)", value: cursorYBinding, formatter: NumberFormatter.sharedInteger)
            }
        }
    }

    private var functionBinding: Binding<SoftwareFunctionKind> {
        Binding(
            get: { action.softwareFunction },
            set: { newValue in onChange { $0.softwareFunction = newValue } }
        )
    }

    private var appPathBinding: Binding<String> {
        Binding(
            get: { action.appPath },
            set: { newValue in onChange { $0.appPath = newValue } }
        )
    }

    private var cursorXBinding: Binding<Int> {
        Binding(
            get: { action.cursorPositionX },
            set: { newValue in onChange { $0.cursorPositionX = newValue } }
        )
    }

    private var cursorYBinding: Binding<Int> {
        Binding(
            get: { action.cursorPositionY },
            set: { newValue in onChange { $0.cursorPositionY = newValue } }
        )
    }
}

// MARK: - Shared modifier toggles (native checkboxes)

struct ModifierToggles: View {
    let selected: Set<ModifierKey>
    let onChange: (Set<ModifierKey>) -> Void

    var body: some View {
        HStack {
            ForEach(ModifierKey.flagBased, id: \.self) { mod in
                Toggle(mod.symbol, isOn: binding(for: mod))
                    .toggleStyle(.checkbox)
                    .help(mod.longName)
            }
        }
    }

    private func binding(for mod: ModifierKey) -> Binding<Bool> {
        Binding(
            get: { selected.contains(mod) },
            set: { isOn in
                var newSet = selected
                if isOn {
                    newSet.insert(mod)
                } else {
                    newSet.remove(mod)
                }
                onChange(newSet)
            }
        )
    }
}

// MARK: - Existing action editors

private struct SendKeyEditor: View {
    @ObservedObject var store: RemapStore
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            LabeledContent("Key to send") {
                HStack {
                    KeyComboCaptureField(
                        isRecording: store.isCapturingToKey,
                        displayLabel: action.toKey.isEmpty ? "" : KeyShortcut(mandatoryModifiers: action.toModifiers, key: action.toKey).displayLabel,
                        onStart: { store.startSendKeyCapture(for: action.id) },
                        onStop: { store.stopToKeyCapture() }
                    )
                    if !action.toKey.isEmpty {
                        Button("Clear", role: .destructive) {
                            onChange { action in
                                action.toKey = ""
                                action.toModifiers = []
                            }
                        }
                        .help("Clear key")
                    }
                    KeyPickerMenu { picked in
                        onChange { action in
                            action.toKey = picked
                        }
                    }
                }
            }
            LabeledContent("Modifiers") {
                ModifierToggles(selected: action.toModifiers) { newSet in
                    onChange { $0.toModifiers = newSet }
                }
            }
        }
    }
}

private struct SendTextEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Type this text", text: textBinding, axis: .vertical)
            .lineLimit(1...4)
    }

    private var textBinding: Binding<String> {
        Binding(get: { action.text }, set: { newValue in onChange { $0.text = newValue } })
    }
}

private struct SetClipboardEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Clipboard text", text: textBinding, axis: .vertical)
            .lineLimit(1...4)
    }

    private var textBinding: Binding<String> {
        Binding(get: { action.text }, set: { newValue in onChange { $0.text = newValue } })
    }
}

private struct SetVariableEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    private var isBool: Bool {
        action.variableValue == "true" || action.variableValue == "false"
    }

    var body: some View {
        Group {
            TextField("Variable name", text: nameBinding)
            if isBool {
                Toggle("Value", isOn: boolBinding)
            } else {
                TextField("Value", text: valueBinding)
            }
            Button(isBool ? "Use text value" : "Use true/false") {
                let current = action.variableValue
                if current == "true" || current == "false" {
                    onChange { $0.variableValue = current == "true" ? "yes" : "" }
                } else {
                    let boolVal = current == "1" || current == "yes"
                    onChange { $0.variableValue = boolVal ? "true" : "false" }
                }
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }

    private var valueBinding: Binding<String> {
        Binding(get: { action.variableValue }, set: { newValue in onChange { $0.variableValue = newValue } })
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { action.variableValue == "true" },
            set: { newValue in onChange { $0.variableValue = newValue ? "true" : "false" } }
        )
    }
}

private struct UnsetVariableEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Variable name", text: nameBinding)
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }
}

private struct ToggleVariableEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("Variable name", text: nameBinding)
            Toggle("Initial value", isOn: initialBinding)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }

    private var initialBinding: Binding<Bool> {
        Binding(
            get: { action.toggleInitialState },
            set: { newValue in onChange { $0.toggleInitialState = newValue } }
        )
    }
}

private struct RunShellEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("Shell command", text: commandBinding, axis: .vertical)
            .lineLimit(1...4)
    }

    private var commandBinding: Binding<String> {
        Binding(get: { action.shellCommand }, set: { newValue in onChange { $0.shellCommand = newValue } })
    }
}

private struct OpenAppEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("App name (e.g. Safari)", text: nameBinding)
            TextField("Bundle ID (e.g. com.apple.Safari)", text: bundleBinding)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.appName }, set: { newValue in onChange { $0.appName = newValue } })
    }

    private var bundleBinding: Binding<String> {
        Binding(get: { action.appBundleID }, set: { newValue in onChange { $0.appBundleID = newValue } })
    }
}

private struct OpenURLEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        TextField("URL", text: urlBinding, prompt: Text("https://example.com"))
    }

    private var urlBinding: Binding<String> {
        Binding(get: { action.urlString }, set: { newValue in onChange { $0.urlString = newValue } })
    }
}

private struct RunShortcutEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void
    @State private var suggestions: [ShortcutInfo] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            HStack {
                TextField("Shortcut name", text: nameBinding)
                Button("Reload") {
                    loadSuggestions()
                }
                .help("Reload installed Shortcuts")
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(suggestions) { info in
                        Button(info.name) {
                            onChange { $0.shortcutName = info.name }
                        }
                    }
                }
            } else if hasLoaded {
                Text("No installed Shortcuts found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadSuggestions() }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.shortcutName }, set: { newValue in onChange { $0.shortcutName = newValue } })
    }

    private func loadSuggestions() {
        hasLoaded = true
        suggestions = ShortcutsService.availableShortcuts()
    }
}

// MARK: - Manipulator parameters editor (kept for compatibility)

struct ManipulatorParametersEditor: View {
    let parameters: ManipulatorParameters
    let onChange: (ManipulatorParameters) -> Void

    var body: some View {
        Group {
            parameterField(
                title: "To If Alone Timeout (ms)",
                help: "How long a key can be held before being treated as held rather than tapped.",
                binding: intBinding(
                    get: { parameters.toIfAloneTimeoutMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toIfAloneTimeoutMilliseconds, newValue)) }
                )
            )
            parameterField(
                title: "To If Held Down Threshold (ms)",
                help: "Minimum hold duration for the key to be considered held down.",
                binding: intBinding(
                    get: { parameters.toIfHeldDownThresholdMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toIfHeldDownThresholdMilliseconds, newValue)) }
                )
            )
            parameterField(
                title: "To Delay Action Delay (ms)",
                help: "Delay before the delayed action is executed.",
                binding: intBinding(
                    get: { parameters.toDelayActionDelayMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toDelayActionDelayMilliseconds, newValue)) }
                )
            )
            parameterField(
                title: "Simultaneous Threshold (ms)",
                help: "Maximum gap between key presses in a sequence trigger.",
                binding: intBinding(
                    get: { parameters.simultaneousThresholdMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.simultaneousThresholdMilliseconds, newValue)) }
                )
            )
            LabeledContent("Mouse Motion Scroll Speed") {
                HStack {
                    Slider(value: logSpeedBinding, in: Self.logMinSpeed...Self.logMaxSpeed)
                        .frame(maxWidth: 140)
                    TextField("Speed", value: speedBinding, format: .number.precision(.fractionLength(0...2)))
                        .labelsHidden()
                        .frame(maxWidth: 64)
                        .multilineTextAlignment(.trailing)
                    Text("×")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Multiplier for mouse motion to scroll conversion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func parameterField(title: String, help: String, binding: Binding<String>) -> some View {
        Group {
            TextField(title, text: binding)
            Text(help)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }


    private func intBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<String> {
        Binding(
            get: { String(get()) },
            set: { newValue in
                let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(cleaned) {
                    set(max(val, 0))
                }
            }
        )
    }

    private func intWithKey(_ params: ManipulatorParameters, _ keyPath: WritableKeyPath<ManipulatorParameters, Int>, _ value: Int) -> ManipulatorParameters {
        var p = params
        p[keyPath: keyPath] = max(value, 0)
        return p
    }

    static let minSpeed: Double = 0.1
    static let maxSpeed: Double = 10
    static let logMinSpeed: Double = -1 // log10(0.1)
    static let logMaxSpeed: Double = 1 // log10(10)

    private var speedBinding: Binding<Double> {
        Binding(
            get: { self.parameters.mouseMotionToScrollSpeed },
            set: { newValue in
                let clamped = min(max(newValue, Self.minSpeed), Self.maxSpeed)
                self.onChange(self.doubleWithKey(self.parameters, \.mouseMotionToScrollSpeed, clamped))
            }
        )
    }

    /// Slider position in log space so each half of the travel covers one
    /// decade (0.1–1, 1–10) instead of cramming all fine control at the left.
    private var logSpeedBinding: Binding<Double> {
        Binding(
            get: { log10(max(self.parameters.mouseMotionToScrollSpeed, Self.minSpeed)) },
            set: { newValue in
                let clamped = min(max(newValue, Self.logMinSpeed), Self.logMaxSpeed)
                self.onChange(self.doubleWithKey(self.parameters, \.mouseMotionToScrollSpeed, pow(10, clamped)))
            }
        )
    }

    private func doubleWithKey(_ params: ManipulatorParameters, _ keyPath: WritableKeyPath<ManipulatorParameters, Double>, _ value: Double) -> ManipulatorParameters {
        var p = params
        p[keyPath: keyPath] = max(value, 0.1)
        return p
    }
}

// MARK: - Contextual parameters editor (new)

struct ContextualParametersEditor: View {
    let manipulator: Manipulator
    @Binding var parameters: ManipulatorParameters

    var body: some View {
        Group {
            switch triggerKind {
            case .keyboard:
                VStack(alignment: .leading, spacing: 12) {
                    parameterField(
                        title: "To If Alone Timeout (ms)",
                        help: "How long a key can be held before being treated as held rather than tapped.",
                        binding: intBinding(
                            get: { parameters.toIfAloneTimeoutMilliseconds },
                            set: { newValue in parameters.toIfAloneTimeoutMilliseconds = max(newValue, 0) }
                        )
                    )
                    parameterField(
                        title: "To If Held Down Threshold (ms)",
                        help: "Minimum hold duration for the key to be considered held down.",
                        binding: intBinding(
                            get: { parameters.toIfHeldDownThresholdMilliseconds },
                            set: { newValue in parameters.toIfHeldDownThresholdMilliseconds = max(newValue, 0) }
                        )
                    )
                    parameterField(
                        title: "To Delay Action Delay (ms)",
                        help: "Delay before the delayed action is executed.",
                        binding: intBinding(
                            get: { parameters.toDelayActionDelayMilliseconds },
                            set: { newValue in parameters.toDelayActionDelayMilliseconds = max(newValue, 0) }
                        )
                    )
                    if manipulator.trigger.simultaneous != nil {
                        parameterField(
                            title: "Simultaneous Threshold (ms)",
                            help: "Maximum gap between key presses in a sequence trigger.",
                            binding: intBinding(
                                get: { parameters.simultaneousThresholdMilliseconds },
                                set: { newValue in parameters.simultaneousThresholdMilliseconds = max(newValue, 0) }
                            )
                        )
                    }
                }
            case .mouseMotionToScroll:
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Mouse Motion Scroll Speed") {
                        HStack {
                            Slider(value: logSpeedBinding, in: ManipulatorParametersEditor.logMinSpeed...ManipulatorParametersEditor.logMaxSpeed)
                                .frame(maxWidth: 140)
                            TextField("Speed", value: speedBinding, format: .number.precision(.fractionLength(0...2)))
                                .labelsHidden()
                                .frame(maxWidth: 64)
                                .multilineTextAlignment(.trailing)
                            Text("×")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Multiplier for mouse motion to scroll conversion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
    }

    private func parameterField(title: String, help: String, binding: Binding<Int>) -> some View {
        Group {
            TextField(title, value: binding, formatter: NumberFormatter.sharedInteger)
            Text(help)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func intBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(
            get: get,
            set: { newValue in set(max(newValue, 0)) }
        )
    }

    /// The trigger kind, resolved from the manipulator type + trigger key type.
    private enum TriggerKind {
        case keyboard, consumer, pointing, typedString, any, mouseMotionToScroll
    }

    private var triggerKind: TriggerKind {
        if manipulator.manipulatorType == .mouseMotionToScroll { return .mouseMotionToScroll }
        switch manipulator.trigger.keyType {
        case .keyboard: return .keyboard
        case .consumer: return .consumer
        case .pointing: return .pointing
        case .typedString: return .typedString
        case .any: return .any
        }
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { parameters.mouseMotionToScrollSpeed },
            set: { newValue in
                let clamped = min(max(newValue, ManipulatorParametersEditor.minSpeed), ManipulatorParametersEditor.maxSpeed)
                parameters.mouseMotionToScrollSpeed = clamped
            }
        )
    }

    private var logSpeedBinding: Binding<Double> {
        Binding(
            get: { log10(max(parameters.mouseMotionToScrollSpeed, ManipulatorParametersEditor.minSpeed)) },
            set: { newValue in
                let clamped = min(max(newValue, ManipulatorParametersEditor.logMinSpeed), ManipulatorParametersEditor.logMaxSpeed)
                parameters.mouseMotionToScrollSpeed = pow(10, clamped)
            }
        )
    }
}

// MARK: - Shared apple script editor

private struct RunAppleScriptEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: 100)
            .onAppear { text = action.scriptBody }
            .onChange(of: text) { _, newValue in
                if newValue != action.scriptBody {
                    onChange { $0.scriptBody = newValue }
                }
            }
            .onChange(of: action.scriptBody) { _, newValue in
                if newValue != text { text = newValue }
            }
    }
}

private struct DelayEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var initialized = false

    var body: some View {
        LabeledContent("Wait") {
            HStack {
                TextField("Seconds", text: $text)
                    .labelsHidden()
                    .focused($isFocused)
                    .onChange(of: action.delaySeconds) { _, _ in
                        if !isFocused { syncFromModel() }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitToModel() }
                    }
                Text("seconds")
            }
        }
        .onAppear { syncFromModel() }
    }

    private func syncFromModel() {
        if !initialized || !isFocused {
            text = String(format: "%.2f", action.delaySeconds)
            initialized = true
        }
    }

    private func commitToModel() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let val = Double(cleaned) {
            let truncated = (val * 100).rounded(.towardZero) / 100
            let final = max(truncated, 0)
            onChange { $0.delaySeconds = final }
            text = String(format: "%.2f", final)
        } else {
            text = String(format: "%.2f", action.delaySeconds)
        }
    }
}

// MARK: - Execute Named Trigger Editor

private struct ExecuteNamedTriggerEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void
    var body: some View {
        Group {
            TextField("Trigger name (e.g. my_subroutine)", text: nameBinding)

            Text("Executes a manipulator that has this trigger name. Make sure the target manipulator is enabled.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { action.namedTrigger },
            set: { newValue in onChange { $0.namedTrigger = newValue } }
        )
    }
}

// MARK: - Send User Command Editor

private struct SendUserCommandEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void
    var body: some View {
        Group {
            TextField("User command", text: commandBinding, axis: .vertical)
                .lineLimit(1...4)

            Text("Executes a user-defined command via /bin/sh -c.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: { action.userCommand },
            set: { newValue in onChange { $0.userCommand = newValue } }
        )
    }
}

struct AdditionalTriggerCard: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let trigger: AdditionalTrigger

    var body: some View {
        DisclosureGroup {
            AdditionalTriggerEditorView(store: store, manipulator: manipulator, trigger: trigger)
        } label: {
            HStack {
                Label("Extra trigger", systemImage: "arrow.triangle.branch")
                Text(trigger.trigger.displayLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Delete", role: .destructive) {
                    store.removeAdditionalTrigger(trigger.id, from: manipulator.id)
                }
            }
        }
    }
}

private struct AdditionalTriggerEditorView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let trigger: AdditionalTrigger

    var body: some View {
        Group {
            Picker("Type", selection: keyTypeBinding) {
                ForEach(TriggerKeyType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            switch trigger.trigger.keyType {
            case .keyboard:
                if trigger.trigger.steps.isEmpty {
                    Text("No keys recorded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(trigger.trigger.steps.enumerated()), id: \.offset) { index, step in
                        TriggerStepBadge(step: step) {
                            var steps = trigger.trigger.steps
                            if steps.indices.contains(index) {
                                steps.remove(at: index)
                                store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                                    $0.trigger.steps = steps
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button("Record") {
                        store.startTriggerRecordingForAdditionalTrigger(trigger.id, in: manipulator.id)
                    }
                    KeyPickerMenu { picked in
                        store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                            $0.trigger.steps = [KeyShortcut(key: picked)]
                        }
                    }
                }

            case .consumer:
                Picker("Consumer key", selection: consumerKeyBinding) {
                    Text("Select...").tag("")
                    ForEach(ConsumerKeyCode.allCases) { key in
                        Text(key.label).tag(key.rawValue)
                    }
                }

            case .pointing:
                Picker("Mouse button", selection: pointingButtonBinding) {
                    Text("Select...").tag("")
                    ForEach(PointingButton.allCases) { btn in
                        Text(btn.label).tag(btn.rawValue)
                    }
                }

            case .typedString:
                TextField("Match string", text: stringTriggerBinding)

            case .any:
                Text("Matches any key press")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings

    private var keyTypeBinding: Binding<TriggerKeyType> {
        Binding(
            get: { trigger.trigger.keyType },
            set: { newValue in
                store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                    $0.trigger.keyType = newValue
                    if newValue == .any { $0.trigger.anyKey = true }
                    else { $0.trigger.anyKey = false }
                }
            }
        )
    }

    private var consumerKeyBinding: Binding<String> {
        Binding(
            get: { trigger.trigger.steps.first?.key ?? "" },
            set: { newValue in
                store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                    $0.trigger.steps = newValue.isEmpty ? [] : [KeyShortcut(key: newValue)]
                }
            }
        )
    }

    private var pointingButtonBinding: Binding<String> {
        Binding(
            get: { trigger.trigger.steps.first?.key ?? "" },
            set: { newValue in
                store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                    $0.trigger.steps = newValue.isEmpty ? [] : [KeyShortcut(key: newValue)]
                }
            }
        )
    }

    private var stringTriggerBinding: Binding<String> {
        Binding(
            get: { trigger.trigger.stringTrigger?.string ?? "" },
            set: { newValue in
                store.updateAdditionalTrigger(trigger.id, in: manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.string = newValue
                }
            }
        )
    }
}

// MARK: - New-feature action editors

private struct WindowActionEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Picker("Window action", selection: kindBinding) {
            ForEach(WindowActionKind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
    }

    private var kindBinding: Binding<WindowActionKind> {
        Binding(
            get: { action.windowActionKind ?? .leftHalf },
            set: { newValue in onChange { $0.windowActionKind = newValue } }
        )
    }
}

private struct TransformTextEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            Picker("Transform", selection: kindBinding) {
                ForEach(TextTransformKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            Text("Transforms the current clipboard text in place.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var kindBinding: Binding<TextTransformKind> {
        Binding(
            get: { action.textTransformKind ?? .upperCase },
            set: { newValue in onChange { $0.textTransformKind = newValue } }
        )
    }
}

private struct SetVolumeEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        LabeledContent("Volume") {
            HStack {
                Slider(value: volumeBinding, in: 0...100, step: 5)
                Text("\(action.numberValue ?? 50)%")
            }
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(action.numberValue ?? 50) },
            set: { newValue in onChange { $0.numberValue = Int(newValue) } }
        )
    }
}

private struct CalculateExpressionEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("Variable name", text: nameBinding)
            TextField("Expression (e.g. 2 + 3 * 4)", text: expressionBinding)
            Text("Evaluates the expression (NSExpression syntax) and stores the result in the variable.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }

    private var expressionBinding: Binding<String> {
        Binding(get: { action.variableValue }, set: { newValue in onChange { $0.variableValue = newValue } })
    }
}

private struct StepVariableEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("Variable name", text: nameBinding)
            TextField("Step (default 1)", text: stepBinding)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }

    private var stepBinding: Binding<String> {
        Binding(get: { action.variableValue }, set: { newValue in onChange { $0.variableValue = newValue } })
    }
}

private struct HTTPRequestEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        Group {
            TextField("URL", text: urlBinding, prompt: Text("https://api.example.com/data"))
            TextField("Response variable", text: variableBinding)
        }
    }

    private var urlBinding: Binding<String> {
        Binding(get: { action.urlString }, set: { newValue in onChange { $0.urlString = newValue } })
    }

    private var variableBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }
}

private struct FilePathEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        HStack {
            TextField(action.kind == .openFolder ? "Folder" : "File", text: pathBinding)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = action.kind != .openFolder
                panel.canChooseDirectories = action.kind == .openFolder
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    onChange { $0.appPath = url.path }
                }
            }
        }
    }

    private var pathBinding: Binding<String> {
        Binding(get: { action.appPath }, set: { newValue in onChange { $0.appPath = newValue } })
    }
}

private struct PlaySoundEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    private static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var body: some View {
        Group {
            HStack {
                TextField("Sound name or file path", text: soundBinding)
                Menu("System") {
                    ForEach(Self.systemSounds, id: \.self) { name in
                        Button(name) { onChange { $0.text = name } }
                    }
                }
            }
            Text("A system sound name (e.g. Ping) or a path to a sound file.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var soundBinding: Binding<String> {
        Binding(get: { action.text }, set: { newValue in onChange { $0.text = newValue } })
    }
}
