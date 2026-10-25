import SwiftUI

// MARK: - Keyboard Trigger Editor

struct KeyboardTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        Group {
            // Match mode picker: sequence vs chord
            Picker("Match", selection: chordModeBinding) {
                Text("In sequence").tag(false)
                Text("Pressed together").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Choose whether the keys must be pressed in sequence or simultaneously (as a chord).")

            if chordModeBinding.wrappedValue {
                // Chord mode editor
                ChordTriggerEditor(store: store, manipulator: manipulator)
            } else {
                // Sequence mode editor
                SequenceModeEditor(store: store, manipulator: manipulator)
            }
        }
    }

    private var chordModeBinding: Binding<Bool> {
        Binding(
            get: { manipulator.trigger.simultaneous?.isValid == true },
            set: { newValue in
                store.updateManipulator(manipulator.id) { manipulator in
                    if newValue {
                        // Switching to chord: create a simultaneous trigger with empty keys, and clear steps
                        manipulator.trigger.simultaneous = SimultaneousTrigger(keys: [])
                        manipulator.trigger.steps = []
                    } else {
                        // Switching to sequence: clear simultaneous, keep steps (but note: we might want to keep steps? The spec says: switching to chord clears steps and vice versa)
                        manipulator.trigger.simultaneous = nil
                        // We do not clear steps here; the spec says vice versa via updateManipulator. We'll leave steps as is when leaving chord mode.
                    }
                }
            }
        )
    }
}

// MARK: - Sequence Mode Editor

struct SequenceModeEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Shortcut recorder row
            ShortcutRecorderRow(store: store, manipulatorID: manipulator.id)

            // If we have steps, show modifier toggles for the first step
            if let firstStep = manipulator.trigger.steps.first, !firstStep.key.isEmpty {
                LabeledContent("Required modifiers") {
                    ModifierToggles(selected: firstStep.mandatoryModifiers) { mods in
                        store.updateManipulator(manipulator.id) {
                            guard $0.trigger.steps.indices.contains(0) else { return }
                            $0.trigger.steps[0].mandatoryModifiers = mods
                        }
                    }
                }
                LabeledContent("Optional modifiers") {
                    ModifierToggles(selected: firstStep.optionalModifiers) { mods in
                        store.updateManipulator(manipulator.id) {
                            guard $0.trigger.steps.indices.contains(0) else { return }
                            $0.trigger.steps[0].optionalModifiers = mods
                        }
                    }
                }
            }

            // Multi-Tap & Hold (Hot Key) configuration
            if !manipulator.trigger.steps.isEmpty || manipulator.trigger.anyKey {
                DisclosureGroup("Multi-Tap & Hold") {
                    HotKeyTriggerEditor(store: store, manipulator: manipulator)
                }
            }
        }
    }
}

// MARK: - Shortcut Recorder Row (reusable)

struct ShortcutRecorderRow: View {
    @ObservedObject var store: RemapStore
    let manipulatorID: UUID

    var body: some View {
        LabeledContent("Keys") {
            HStack {
                // Show the current steps (or recorded steps if recording)
                if store.isRecordingTrigger && store.editingManipulatorID == manipulatorID {
                    ShortcutDisplayText(shortcuts: store.recordedTriggerSteps)
                } else {
                    // Find the manipulator to get its steps
                    if let manipulator = store.manipulator(id: manipulatorID) {
                        ShortcutDisplayText(shortcuts: manipulator.trigger.steps)
                    } else {
                        ShortcutDisplayText(shortcuts: [])
                    }
                }

                Spacer()

                Button {
                    if store.isRecordingTrigger && store.editingManipulatorID == manipulatorID {
                        store.stopTriggerRecording(save: true)
                    } else if store.isRecordingTrigger {
                        // Recording another manipulator, ignore
                    } else {
                        store.startTriggerRecording(for: manipulatorID)
                    }
                } label: {
                    Text(store.isRecordingTrigger && store.editingManipulatorID == manipulatorID ? "Done" : (store.editingManipulatorID == manipulatorID ? "Re-record…" : "Record…"))
                }
                .disabled(store.isRecordingTrigger && store.editingManipulatorID != manipulatorID)
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Hot Key Trigger Editor (extracted from existing)

struct HotKeyTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        Group {
            Toggle("Hot key behavior", isOn: hotKeyEnabledBinding)

            if manipulator.trigger.hotKey != nil {
                Stepper(
                    "Tap count: \(manipulator.trigger.hotKey?.tapCount ?? 2)",
                    value: hotKeyTapCountBinding,
                    in: 1...5
                )
                TextField("Timeout between taps (ms)", value: hotKeyTimeoutBinding, formatter: NumberFormatter.sharedInteger)

                Toggle("Require final tap to be held", isOn: hotKeyHoldRequiredBinding)

                if manipulator.trigger.hotKey?.holdRequired == true {
                    TextField("Hold duration (ms)", value: hotKeyHoldThresholdBinding, formatter: NumberFormatter.sharedInteger)
                }
            }
        }
    }

    // MARK: - Hot Key Bindings (same as in ManipulatorEditorView)

    private var hotKeyEnabledBinding: Binding<Bool> {
        Binding(
            get: { manipulator.trigger.hotKey != nil },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if newValue {
                        $0.trigger.hotKey = HotKeyTriggerConfig(
                            tapCount: 2,
                            tapTimeoutMilliseconds: 400,
                            holdRequired: false,
                            holdThresholdMilliseconds: 500
                        )
                    } else {
                        $0.trigger.hotKey = nil
                    }
                }
            }
        )
    }

    private var hotKeyTapCountBinding: Binding<Int> {
        Binding(
            get: { manipulator.trigger.hotKey?.tapCount ?? 2 },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.hotKey != nil {
                        $0.trigger.hotKey?.tapCount = max(1, min(newValue, 5))
                    }
                }
            }
        )
    }

    private var hotKeyTimeoutBinding: Binding<Int> {
        Binding(
            get: { manipulator.trigger.hotKey?.tapTimeoutMilliseconds ?? 400 },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    $0.trigger.hotKey?.tapTimeoutMilliseconds = max(50, newValue)
                }
            }
        )
    }

    private var hotKeyHoldRequiredBinding: Binding<Bool> {
        Binding(
            get: { manipulator.trigger.hotKey?.holdRequired ?? false },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    $0.trigger.hotKey?.holdRequired = newValue
                }
            }
        )
    }

    private var hotKeyHoldThresholdBinding: Binding<Int> {
        Binding(
            get: { manipulator.trigger.hotKey?.holdThresholdMilliseconds ?? 500 },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    $0.trigger.hotKey?.holdThresholdMilliseconds = max(100, newValue)
                }
            }
        )
    }
}

// MARK: - Chord Trigger Editor

struct ChordTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Chord keys") {
                HStack {
                    // Show the current simultaneous keys (or recorded steps if chord-recording)
                    if store.isRecordingTrigger && store.editingManipulatorID == manipulator.id {
                        ShortcutDisplayText(shortcuts: store.recordedTriggerSteps)
                    } else {
                        if let simultaneous = manipulator.trigger.simultaneous {
                            ShortcutDisplayText(shortcuts: simultaneous.keys)
                        } else {
                            ShortcutDisplayText(shortcuts: [])
                        }
                    }

                    Spacer()

                    Button {
                        if store.isRecordingTrigger && store.editingManipulatorID == manipulator.id {
                            store.stopTriggerRecording(save: true)
                        } else if store.isRecordingTrigger {
                            // Recording another manipulator, ignore
                        } else {
                            store.startChordRecording(for: manipulator.id)
                        }
                    } label: {
                        Text(store.isRecordingTrigger && store.editingManipulatorID == manipulator.id ? "Done" : (store.editingManipulatorID == manipulator.id ? "Record chord…" : "Record chord…"))
                    }
                    .disabled(store.isRecordingTrigger && store.editingManipulatorID != manipulator.id)
                    .buttonStyle(.bordered)
                }
            }

            if store.isRecordingTrigger && store.editingManipulatorID == manipulator.id {
                Text("Press the keys together — bare Esc cancels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                KeyPickerMenu(label: "Add key") { keyID in
                    let keyShortcut = KeyShortcut(key: keyID)
                    store.updateManipulator(manipulator.id) { manipulator in
                        if var simultaneous = manipulator.trigger.simultaneous {
                            simultaneous.keys.append(keyShortcut)
                            manipulator.trigger.simultaneous = simultaneous
                        } else {
                            manipulator.trigger.simultaneous = SimultaneousTrigger(keys: [keyShortcut])
                        }
                    }
                }
                Button("Clear", role: .destructive) {
                    store.updateManipulator(manipulator.id) { $0.trigger.simultaneous = nil }
                }
                .disabled(!(manipulator.trigger.simultaneous?.isValid ?? false))
            }

            // Order pickers
            Picker("Key down order", selection: simultaneousKeyDownOrderBinding) {
                Text("Insensitive").tag(SimultaneousOrder.insensitive)
                Text("Strict").tag(SimultaneousOrder.strict)
                Text("Strict inverse").tag(SimultaneousOrder.strictInverse)
            }
            .pickerStyle(.menu)

            Picker("Key up order", selection: simultaneousKeyUpOrderBinding) {
                Text("Insensitive").tag(SimultaneousOrder.insensitive)
                Text("Strict").tag(SimultaneousOrder.strict)
                Text("Strict inverse").tag(SimultaneousOrder.strictInverse)
            }
            .pickerStyle(.menu)

            Picker("Key up when", selection: simultaneousKeyUpWhenBinding) {
                Text("Any key up").tag(SimultaneousUpWhen.any)
                Text("All keys up").tag(SimultaneousUpWhen.all)
            }
            .pickerStyle(.menu)

            Toggle("Detect key down uninterruptedly", isOn: simultaneousUninterruptedBinding)
        }
    }

    // MARK: - Simultaneous Trigger Bindings

    private var simultaneousKeyDownOrderBinding: Binding<SimultaneousOrder> {
        Binding(
            get: { manipulator.trigger.simultaneous?.options.keyDownOrder ?? .insensitive },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.simultaneous == nil {
                        $0.trigger.simultaneous = SimultaneousTrigger(keys: [])
                    }
                    $0.trigger.simultaneous?.options.keyDownOrder = newValue
                }
            }
        )
    }

    private var simultaneousKeyUpOrderBinding: Binding<SimultaneousOrder> {
        Binding(
            get: { manipulator.trigger.simultaneous?.options.keyUpOrder ?? .insensitive },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.simultaneous == nil {
                        $0.trigger.simultaneous = SimultaneousTrigger(keys: [])
                    }
                    $0.trigger.simultaneous?.options.keyUpOrder = newValue
                }
            }
        )
    }

    private var simultaneousKeyUpWhenBinding: Binding<SimultaneousUpWhen> {
        Binding(
            get: { manipulator.trigger.simultaneous?.options.keyUpWhen ?? .any },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.simultaneous == nil {
                        $0.trigger.simultaneous = SimultaneousTrigger(keys: [])
                    }
                    $0.trigger.simultaneous?.options.keyUpWhen = newValue
                }
            }
        )
    }

    private var simultaneousUninterruptedBinding: Binding<Bool> {
        Binding(
            get: { manipulator.trigger.simultaneous?.options.detectKeyDownUninterruptedly ?? false },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.simultaneous == nil {
                        $0.trigger.simultaneous = SimultaneousTrigger(keys: [])
                    }
                    $0.trigger.simultaneous?.options.detectKeyDownUninterruptedly = newValue
                }
            }
        )
    }
}

// MARK: - Consumer Trigger Editor

struct ConsumerTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a media/consumer key to trigger this manipulator.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Consumer key", selection: consumerKeyBinding) {
                Text("Select...").tag(String?.none)
                ForEach(ConsumerKeyCode.allCases) { key in
                    Label(key.label, systemImage: key.symbol)
                        .tag(key.keyID as String?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Stores the canonical consumer key ID (`vk_consumer_*`) so the engine
    /// can match incoming media-key events. Legacy short-form IDs are
    /// upgraded to the canonical form on load.
    private var consumerKeyBinding: Binding<String?> {
        Binding(
            get: {
                guard let key = manipulator.trigger.steps.first?.key else { return nil }
                // Normalize legacy/short-form IDs to the canonical form so the
                // picker shows the right selection.
                if let code = ConsumerKeyCode.allCases.first(where: { $0.keyID == key }) {
                    return code.keyID
                }
                if let code = ConsumerKeyCode.allCases.first(where: { $0.rawValue == key }) {
                    return code.keyID
                }
                if key == "vk_consumer_prev" { return ConsumerKeyCode.previous.keyID }
                return key
            },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    let value = newValue ?? ""
                    $0.trigger.steps = value.isEmpty ? [] : [KeyShortcut(key: value)]
                }
            }
        )
    }
}

// MARK: - Pointing Trigger Editor

struct PointingTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a mouse button to trigger this manipulator.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Mouse button", selection: pointingButtonBinding) {
                Text("Select...").tag("")
                ForEach(PointingButton.allCases) { btn in
                    Label(btn.label, systemImage: btn.symbol)
                        .tag(btn.rawValue as String?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var pointingButtonBinding: Binding<String?> {
        Binding(
            get: { manipulator.trigger.steps.first?.key },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    let value = newValue ?? ""
                    $0.trigger.steps = value.isEmpty ? [] : [KeyShortcut(key: value)]
                }
            }
        )
    }
}

// MARK: - Typed String Trigger Editor

struct TypedStringTriggerEditor: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Match string", text: typedStringBinding)

            Picker("Match mode", selection: typedStringMatchModeBinding) {
                ForEach(StringTriggerMatchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Clear buffer after match", isOn: typedStringClearOnMatchBinding)

            TextField("App scope (bundle ID, empty for all apps)", text: typedStringAppBinding)

            LabeledContent("Timeout") {
                HStack {
                    Slider(value: typedStringTimeoutBinding, in: 0.5...10, step: 0.5)
                    Text(String(format: "%.1fs", manipulator.trigger.stringTrigger?.timeoutSeconds ?? 2.0))
                }
            }
        }
    }

    private var typedStringBinding: Binding<String> {
        Binding(
            get: { manipulator.trigger.stringTrigger?.string ?? "" },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.string = newValue
                }
            }
        )
    }

    private var typedStringMatchModeBinding: Binding<StringTriggerMatchMode> {
        Binding(
            get: { manipulator.trigger.stringTrigger?.matchMode ?? .fullMatch },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.matchMode = newValue
                }
            }
        )
    }

    private var typedStringClearOnMatchBinding: Binding<Bool> {
        Binding(
            get: { manipulator.trigger.stringTrigger?.clearOnMatch ?? true },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.clearOnMatch = newValue
                }
            }
        )
    }

    private var typedStringAppBinding: Binding<String> {
        Binding(
            get: { manipulator.trigger.stringTrigger?.appBundleID ?? "" },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.appBundleID = newValue
                }
            }
        )
    }

    private var typedStringTimeoutBinding: Binding<Double> {
        Binding(
            get: { manipulator.trigger.stringTrigger?.timeoutSeconds ?? 2.0 },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    if $0.trigger.stringTrigger == nil {
                        $0.trigger.stringTrigger = StringTriggerOptions()
                    }
                    $0.trigger.stringTrigger?.timeoutSeconds = max(0.1, newValue)
                }
            }
        )
    }
}
