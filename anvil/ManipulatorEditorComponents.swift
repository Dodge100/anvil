import AppKit
import SwiftUI

// MARK: - Condition step row

struct ConditionStepRow: View {
    let condition: Condition
    let onChange: ((inout Condition) -> Void) -> Void
    let onDelete: () -> Void
    var onChangeKind: (() -> Void)? = nil

    @State private var installedApps: [InstalledApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with kind selector and delete
            HStack(alignment: .center, spacing: 8) {
                // Kind label — click to replace
                Button {
                    onChangeKind?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: condition.kind.symbol)
                            .foregroundStyle(.orange)
                            .frame(width: 16)
                        Text(condition.kind.rawValue)
                            .font(.subheadline.weight(.medium))

                    }
                }
                .buttonStyle(.plain)
                .help("Click to change condition type")
                
                // Comparison operator (when applicable)
                if condition.kind != .deviceExists && condition.kind != .expression && condition.kind != .eventChanged {
                    Picker("Op", selection: opBinding) {
                        ForEach(ComparisonOp.allCases) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 72)
                }
                
                Spacer()
                
                // Delete button
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            
            // Value field based on condition type
            if condition.kind == .variable || condition.kind == .globalVariable {
                HStack(spacing: 6) {
                    TextField("Variable name", text: targetBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.subheadline, design: .monospaced))
                    Text("=")
                        .foregroundStyle(.secondary)
                    if isBoolValue(condition.value) {
                        Toggle("", isOn: variableBoolBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    } else {
                        TextField("Expected value", text: variableValueBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    Button(isBoolValue(condition.value) ? "Text" : "Bool") {
                        let current = condition.value
                        var newValue: String
                        if isBoolValue(current) {
                            newValue = current == "true" ? "yes" : ""
                        } else {
                            newValue = current == "1" || current == "yes" ? "true" : "false"
                        }
                        onChange { $0.value = newValue }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if condition.kind == .frontmostApp || condition.kind == .frontmostAppName {
                HStack(spacing: 8) {
                    TextField(condition.kind.placeholder, text: targetBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.subheadline, design: .monospaced))
                    AppPicker(installedApps: installedApps) { app in
                        onChange { condition in
                            condition.target = condition.kind == .frontmostAppName
                                ? app.name
                                : app.bundleID
                        }
                    }
                    .onAppear(perform: loadInstalledApps)
                }
            } else if condition.kind == .expression {
                TextField("e.g. my_var == \"hello\"", text: targetBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else if condition.kind == .eventChanged {
                Picker("Event type", selection: targetBinding) {
                    Text("Keyboard Type").tag("keyboard_type")
                    Text("Device").tag("device")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                TextField(condition.kind.placeholder, text: targetBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            
            // Help text
            Text(condition.kind.helpText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
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
        Menu {
            if installedApps.isEmpty {
                Text("Scanning applications\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(installedApps) { app in
                    Button {
                        onSelect(app)
                    } label: {
                        Text(app.name)
                    }
                }
            }
        } label: {
            Text("…").font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    actionEditor
                    actionModifiersSection
                    fireModeSection
                    actionConditionsSection
                }
                .padding(.top, 8)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            // Kind label — click to replace
            Button {
                onChangeKind?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: action.kind.symbol)
                        .foregroundStyle(.green)
                        .frame(width: 16)
                    Text(action.kind.rawValue)
                        .font(.subheadline.weight(.medium))

                }
            }
            .buttonStyle(.plain)
            .help("Click to change action type")

            // Summary as secondary text
            Text(action.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Expand/collapse and delete
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove action")
            }
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
            .font(.caption)
            .foregroundStyle(.secondary)
        case .consumerKey: ConsumerKeyEditor(action: action, onChange: onChange)
        case .pointingButton: PointingButtonEditor(action: action, onChange: onChange)
        case .mouseKey: MouseKeyEditor(action: action, onChange: onChange)
        case .stickyModifier: StickyModifierEditor(action: action, onChange: onChange)
        case .halt: Text("Stops processing further actions in this manipulator. Useful with conditions.")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .holdDown: HoldDownEditor(store: store, action: action, onChange: onChange)
        case .selectInputSource: SelectInputSourceEditor(action: action, onChange: onChange)
        case .setNotification: SetNotificationEditor(action: action, onChange: onChange)
        case .fromEvent: Text("Mirrors the original trigger event. Sends whatever key was originally pressed.")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .softwareFunction: SoftwareFunctionEditor(action: action, onChange: onChange)
        case .sendUserCommand: SendUserCommandEditor(action: action, onChange: onChange)
        case .executeNamedTrigger: ExecuteNamedTriggerEditor(action: action, onChange: onChange)
        case .setGlobalVariable: SetVariableEditor(action: action, onChange: onChange)
        case .unsetGlobalVariable: UnsetVariableEditor(action: action, onChange: onChange)
        case .showPalette:
            Text("Shows the floating macro palette.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .hidePalette:
            Text("Hides the floating macro palette.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .getSelectedText:
            Text("Gets the currently selected text from the frontmost application and stores it for use by later actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .setClipboard:
            SetClipboardEditor(action: action, onChange: onChange)
        case .getClipboard:
            Text("Reads the current clipboard content and stores it for use by later actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .clearClipboard:
            Text("Clears the system clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .activateApp, .hideApp, .unhideApp, .quitApp, .forceQuitApp:
            OpenAppEditor(action: action, onChange: onChange)
        case .activateLastApp:
            Text("Switches back to the previously active application.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .windowAction:
            WindowActionEditor(action: action, onChange: onChange)
        case .lockScreen:
            Text("Locks the screen (switches to the login window).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .showDesktop:
            Text("Shows the desktop by pushing all windows aside.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .missionControl:
            Text("Activates Mission Control.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .toggleDarkMode:
            Text("Toggles between Dark and Light appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .setVolume:
            SetVolumeEditor(action: action, onChange: onChange)
        case .muteSystem:
            Text("Toggles system audio mute on/off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .emptyTrash:
            Text("Empties the Trash via Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .getBatteryState:
            Text("Stores battery level in `batteryLevel` and charging state in `batteryCharging` variables.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .getIPAddress:
            Text("Stores the current IP address in the `ipAddress` variable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .toggleHiddenFiles:
            Text("Toggles hidden file visibility in Finder (restarts Finder).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .logOut:
            Text("Logs out the current user (asks for confirmation).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .restartSystem:
            Text("Restarts the Mac (asks for confirmation).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .shutdownSystem:
            Text("Shuts down the Mac (asks for confirmation).")
                .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
        case .httpRequest:
            HTTPRequestEditor(action: action, onChange: onChange)
        case .openFile, .openFolder:
            FilePathEditor(action: action, onChange: onChange)
        case .playSound:
            PlaySoundEditor(action: action, onChange: onChange)
        case .flashScreen:
            Text("Flashes the screen with a brief white overlay — useful as visual feedback for a macro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionModifiersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modifiers")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Toggle("Lazy", isOn: lazyBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Modifier does not apply until another key is pressed")

                Picker("Repeat", selection: repeatBinding) {
                    Text("Default").tag(Optional<Bool>.none)
                    Text("Enable").tag(Optional<Bool>.some(true))
                    Text("Disable").tag(Optional<Bool>.some(false))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
                .help("Override key repeat behavior")
            }
        }
    }

    @ViewBuilder
    private var actionConditionsSection: some View {
        if !action.actionConditions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Per-action conditions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(action.actionConditions) { cond in
                    HStack {
                        Text(cond.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            onChange { $0.actionConditions.removeAll { $0.id == cond.id } }
                        } label: {
                            Text("X").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var fireModeSection: some View {
        HStack(spacing: 8) {
            Picker("When", selection: fireModeBinding) {
                ForEach(ActionFireMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .help(action.fireMode.helpText)
            Text(action.fireMode.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
        .labelsHidden()
        .pickerStyle(.menu)
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
        .labelsHidden()
        .pickerStyle(.menu)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Movement").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("X", value: xBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        TextField("Y", value: yBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scroll").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("V", value: vScrollBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        TextField("H", value: hScrollBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed").font(.caption).foregroundStyle(.secondary)
                    Slider(value: speedBinding, in: 0.1...10)
                        .frame(width: 80)
                }
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
        HStack(spacing: 12) {
            Picker("Modifier", selection: modBinding) {
                ForEach(ModifierKey.flagBased, id: \.self) { mod in
                    Text(mod.longName).tag(mod)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Picker("Action", selection: kindBinding) {
                ForEach(StickyModifierKind.allCases) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Key")
                    .foregroundStyle(.secondary)
                Spacer()
                KeyComboCaptureField(
                    modifiers: action.toModifiers,
                    key: action.toKey,
                    isCapturing: store.isCapturingToKey,
                    onStart: { store.startSendKeyCapture(for: action.id) },
                    onCancel: { store.stopToKeyCapture() }
                )
            }
            HStack {
                Text("Hold duration")
                    .foregroundStyle(.secondary)
                TextField("ms", value: holdBinding, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("ms")
                    .foregroundStyle(.secondary)
            }
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
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
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
            .textFieldStyle(.roundedBorder)
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
        VStack(alignment: .leading, spacing: 8) {
            Picker("Function", selection: functionBinding) {
                ForEach(SoftwareFunctionKind.allCases) { fn in
                    Text(fn.rawValue).tag(fn)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if action.softwareFunction == .openApplication {
                TextField("App bundle ID, path, or name", text: appPathBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if action.softwareFunction == .setCursorPosition {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X").font(.caption).foregroundStyle(.secondary)
                        TextField("0", value: cursorXBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y").font(.caption).foregroundStyle(.secondary)
                        TextField("0", value: cursorYBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    Text("(screen coordinates)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Existing action editors

private struct SendKeyEditor: View {
    @ObservedObject var store: RemapStore
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Key to send")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    KeyComboCaptureField(
                        modifiers: action.toModifiers,
                        key: action.toKey,
                        isCapturing: store.isCapturingToKey,
                        onStart: { store.startSendKeyCapture(for: action.id) },
                        onCancel: { store.stopToKeyCapture() }
                    )
                    if !action.toKey.isEmpty {
                        Button {
                            onChange { action in
                                action.toKey = ""
                                action.toModifiers = []
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear key")
                    }
                }
                HStack(spacing: 4) {
                    Text("Modifiers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(ModifierKey.flagBased, id: \.self) { mod in
                        Button {
                            var newSet = action.toModifiers
                            if newSet.contains(mod) {
                                newSet.remove(mod)
                            } else {
                                newSet.insert(mod)
                            }
                            onChange { $0.toModifiers = newSet }
                        } label: {
                            Text(mod.symbol)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(action.toModifiers.contains(mod) ? Color(nsColor: .controlBackgroundColor).opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func modifierChips(for selected: Set<ModifierKey>, onChange: @escaping (Set<ModifierKey>) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(ModifierKey.flagBased, id: \.self) { mod in
                Button {
                    var newSet = selected
                    if newSet.contains(mod) {
                        newSet.remove(mod)
                    } else {
                        newSet.insert(mod)
                    }
                    onChange(newSet)
                } label: {
                    Text(mod.symbol)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selected.contains(mod) ? Color(nsColor: .controlBackgroundColor).opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
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
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }

    private var textBinding: Binding<String> {
        Binding(get: { action.text }, set: { newValue in onChange { $0.text = newValue } })
    }
}

private struct SetClipboardEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set clipboard to:")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Text to set", text: textBinding, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
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
        HStack {
            TextField("Name", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("=")
                .foregroundStyle(.secondary)
            if isBool {
                Toggle("", isOn: boolBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            } else {
                TextField("Value", text: valueBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            Button(isBool ? "Text" : "Bool") {
                let current = action.variableValue
                if current == "true" || current == "false" {
                    onChange { $0.variableValue = current == "true" ? "yes" : "" }
                } else {
                    let boolVal = current == "1" || current == "yes"
                    onChange { $0.variableValue = boolVal ? "true" : "false" }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
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
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }

    private var nameBinding: Binding<String> {
        Binding(get: { action.variableName }, set: { newValue in onChange { $0.variableName = newValue } })
    }
}

private struct ToggleVariableEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        HStack {
            TextField("Variable name", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Toggle("Initial value", isOn: initialBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
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
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }

    private var commandBinding: Binding<String> {
        Binding(get: { action.shellCommand }, set: { newValue in onChange { $0.shellCommand = newValue } })
    }
}

private struct OpenAppEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Name")
                    .frame(width: 80, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("App name (e.g. Safari)", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Bundle ID")
                    .frame(width: 80, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("com.apple.Safari", text: bundleBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
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
        TextField("https://example.com", text: urlBinding)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Shortcut name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                Button {
                    loadSuggestions()
                } label: {
                    Text("Reload").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Reload installed Shortcuts")
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(suggestions) { info in
                            Button {
                                onChange { $0.shortcutName = info.name }
                            } label: {
                                Text(info.name)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if hasLoaded {
                Text("No installed Shortcuts found.")
                    .font(.caption)
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

struct ManipulatorParametersEditor: View {
    let parameters: ManipulatorParameters
    let onChange: (ManipulatorParameters) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            parameterRow(
                icon: "timer",
                title: "To If Alone Timeout",
                help: "How long a key can be held before being treated as held rather than tapped.",
                unit: "ms",
                binding: intBinding(
                    get: { parameters.toIfAloneTimeoutMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toIfAloneTimeoutMilliseconds, newValue)) }
                )
            )
            parameterRow(
                icon: "hand.raised",
                title: "To If Held Down Threshold",
                help: "Minimum hold duration for the key to be considered held down.",
                unit: "ms",
                binding: intBinding(
                    get: { parameters.toIfHeldDownThresholdMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toIfHeldDownThresholdMilliseconds, newValue)) }
                )
            )
            parameterRow(
                icon: "clock.arrow.circlepath",
                title: "To Delay Action Delay",
                help: "Delay before the delayed action is executed.",
                unit: "ms",
                binding: intBinding(
                    get: { parameters.toDelayActionDelayMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.toDelayActionDelayMilliseconds, newValue)) }
                )
            )
            parameterRow(
                icon: "arrow.left.arrow.right",
                title: "Simultaneous Threshold",
                help: "Maximum gap between key presses in a sequence trigger.",
                unit: "ms",
                binding: intBinding(
                    get: { parameters.simultaneousThresholdMilliseconds },
                    set: { newValue in onChange(intWithKey(parameters, \.simultaneousThresholdMilliseconds, newValue)) }
                )
            )
            parameterSliderRow(
                icon: "cursorarrow.motionlines",
                title: "Mouse Motion Scroll Speed",
                help: "Multiplier for mouse motion to scroll conversion.",
                value: String(format: "%.1fx", parameters.mouseMotionToScrollSpeed),
                binding: speedBinding,
                range: 0.1...10,
                step: 0.1
            )
        }
    }

    private func parameterSliderRow(icon: String, title: String, help: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Slider(value: binding, in: range, step: step)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
            }
            .frame(width: 120)
        }
    }

    private func parameterRow(icon: String, title: String, help: String, unit: String, binding: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("value", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
            .frame(width: 120)
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

    private var speedBinding: Binding<Double> {
        Binding(
            get: { self.parameters.mouseMotionToScrollSpeed },
            set: { newValue in self.onChange(self.doubleWithKey(self.parameters, \.mouseMotionToScrollSpeed, newValue)) }
        )
    }

    private func doubleWithKey(_ params: ManipulatorParameters, _ keyPath: WritableKeyPath<ManipulatorParameters, Double>, _ value: Double) -> ManipulatorParameters {
        var p = params
        p[keyPath: keyPath] = max(value, 0.1)
        return p
    }
}

private struct RunAppleScriptEditor: View {
    let action: Action
    let onChange: ((inout Action) -> Void) -> Void

    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 1)
            )
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
        HStack {
            TextField("Seconds", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)
                .focused($isFocused)
                .onChange(of: action.delaySeconds) { _, _ in
                    if !isFocused { syncFromModel() }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitToModel() }
                }
            Text("s")
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 6) {
            TextField("Trigger name (e.g. my_subroutine)", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("Executes a manipulator that has this trigger name. Make sure the target manipulator is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 6) {
            TextField("User command", text: commandBinding, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("Executes a user-defined command via /bin/sh -c.")
                .font(.caption)
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
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(trigger.trigger.displayLabel)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    store.removeAdditionalTrigger(trigger.id, from: manipulator.id)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            if isExpanded {
                AdditionalTriggerEditorView(store: store, manipulator: manipulator, trigger: trigger)
            }
        }
        .padding(8)
    }
}

private struct AdditionalTriggerEditorView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let trigger: AdditionalTrigger

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Type", selection: keyTypeBinding) {
                ForEach(TriggerKeyType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch trigger.trigger.keyType {
            case .keyboard:
                if trigger.trigger.steps.isEmpty {
                    Text("No keys recorded")
                        .font(.caption)
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
                Button {
                    store.startTriggerRecordingForAdditionalTrigger(trigger.id, in: manipulator.id)
                } label: {
                    Text("Record")
                }
                .buttonStyle(.borderless)

            case .consumer:
                Picker("Consumer key", selection: consumerKeyBinding) {
                    Text("Select...").tag("")
                    ForEach(ConsumerKeyCode.allCases) { key in
                        Text(key.label).tag(key.rawValue)
                    }
                }
                .labelsHidden()

            case .pointing:
                Picker("Mouse button", selection: pointingButtonBinding) {
                    Text("Select...").tag("")
                    ForEach(PointingButton.allCases) { btn in
                        Text(btn.label).tag(btn.rawValue)
                    }
                }
                .labelsHidden()

            case .typedString:
                TextField("Match string", text: stringTriggerBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

            case .any:
                Text("Matches any key press")
                    .font(.caption)
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
        .pickerStyle(.menu)
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
        VStack(alignment: .leading, spacing: 4) {
            Picker("Transform", selection: kindBinding) {
                ForEach(TextTransformKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)
            Text("Transforms the current clipboard text in place.")
                .font(.caption)
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
        HStack {
            Slider(value: volumeBinding, in: 0...100, step: 5)
            Text("\(action.numberValue ?? 50)%")
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Variable name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("=")
                    .foregroundStyle(.secondary)
                TextField("2 + 3 * 4", text: expressionBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            Text("Evaluates the expression (NSExpression syntax) and stores the result in the variable.")
                .font(.caption)
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
        HStack {
            TextField("Variable name", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text(action.kind == .incrementVariable ? "+" : "−")
                .foregroundStyle(.secondary)
            TextField("1", text: stepBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60)
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
        VStack(alignment: .leading, spacing: 4) {
            TextField("https://api.example.com/data", text: urlBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Text("Store response in:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("httpResponse", text: variableBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
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
            TextField(action.kind == .openFolder ? "~/Documents" : "~/Documents/notes.txt", text: pathBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = action.kind != .openFolder
                panel.canChooseDirectories = action.kind == .openFolder
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    onChange { $0.appPath = url.path }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Sound name or file path", text: soundBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Menu("System") {
                    ForEach(Self.systemSounds, id: \.self) { name in
                        Button(name) { onChange { $0.text = name } }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text("A system sound name (e.g. Ping) or a path to a sound file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var soundBinding: Binding<String> {
        Binding(get: { action.text }, set: { newValue in onChange { $0.text = newValue } })
    }
}
