import SwiftUI

struct ManipulatorEditorView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    @State private var activeLibrary: ActiveLibrary? = nil
    @State private var replacingActionID: UUID? = nil
    @State private var replacingConditionID: UUID? = nil
    @State private var triggerExpanded = true
    @State private var conditionsExpanded = true
    @State private var actionsExpanded = true
    @State private var parametersExpanded = false
    @State private var notesExpanded = true

    private enum ActiveLibrary: String, Identifiable {
        case action
        case condition

        var id: String { rawValue }
    }

    var body: some View {
        editorContent
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
            .sheet(item: $activeLibrary) { library in
                switch library {
                case .action:
                    ActionLibraryBrowser(isPresented: sheetBinding) { kind in
                        if let replaceID = replacingActionID {
                            store.updateAction(replaceID, in: manipulator.id) { $0.kind = kind }
                            replacingActionID = nil
                        } else {
                            store.updateManipulator(manipulator.id) { $0.actions.append(Action(kind: kind)) }
                        }
                    }
                case .condition:
                    ConditionLibraryBrowser(isPresented: sheetBinding) { kind in
                        if let replaceID = replacingConditionID {
                            store.updateCondition(replaceID, in: manipulator.id) { $0.kind = kind }
                            replacingConditionID = nil
                        } else {
                            store.updateManipulator(manipulator.id) {
                                var condition = Condition()
                                condition.kind = kind
                                $0.conditions.append(condition)
                            }
                        }
                    }
                }
            }
    }

    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { activeLibrary != nil },
            set: { if !$0 { activeLibrary = nil } }
        )
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                
                // Trigger card
                EditorCard {
                    triggerSection
                }
                
                // Conditions card
                EditorCard {
                    conditionsSection
                }
                
                // Actions card
                EditorCard {
                    actionsSection
                }
                
                // Parameters card
                EditorCard {
                    parametersSection
                }
                
                // Notes card
                EditorCard {
                    notesSection
                }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }



    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Name", text: nameBinding)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            TextField("Folder", text: folderBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            TagEditorField(store: store, manipulator: manipulator)
        }
    }

    private var triggerSection: some View {
        CollapsibleStepCard(title: "Trigger", accentColor: .blue, isExpanded: $triggerExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                // Single unified trigger type selector
                Picker("Type", selection: unifiedTriggerTypeBinding) {
                    ForEach(UnifiedTriggerType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                // Description for special types
                if unifiedTriggerType == .mouseMotionToScroll {
                    Text("Converts mouse movement into scroll events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Trigger configuration based on type
                if unifiedTriggerType != .mouseMotionToScroll {
                    triggerConfiguration
                }
                
                // Additional triggers
                additionalTriggersContent
            }
        }
    }

    // MARK: - Additional Triggers (Merged into Trigger Section)

    private var additionalTriggersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(manipulator.additionalTriggers) { trigger in
                AdditionalTriggerCard(
                    store: store,
                    manipulator: manipulator,
                    trigger: trigger
                )
            }
            Button {
                store.addAdditionalTrigger(to: manipulator.id)
            } label: {
                Label("Add Another Trigger", systemImage: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var triggerConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Named trigger (optional, for all types)
            TextField("Named trigger (optional)", text: triggerNameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .help("If set, this manipulator can be triggered by name from another manipulator's 'Execute Named Trigger' action.")

            // Type-specific trigger editor
            switch unifiedTriggerType {
            case .keyboard:
                keyboardTriggerEditor
            case .consumer:
                consumerTriggerEditor
            case .mouseButton:
                pointingTriggerEditor
            case .typedString:
                typedStringTriggerEditor
            case .anyKey:
                Text("Matches any key press.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .mouseMotionToScroll:
                EmptyView()
            }
        }
    }

    // MARK: - Unified Trigger Type

    private enum UnifiedTriggerType: String, CaseIterable, Identifiable {
        case keyboard = "Keyboard Key"
        case consumer = "Consumer Key"
        case mouseButton = "Mouse Button"
        case typedString = "Typed String"
        case anyKey = "Any Key"
        case mouseMotionToScroll = "Mouse Motion to Scroll"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .keyboard: return "keyboard"
            case .consumer: return "play.square"
            case .mouseButton: return "cursorarrow"
            case .typedString: return "textformat.abc"
            case .anyKey: return "asterisk"
            case .mouseMotionToScroll: return "scroll"
            }
        }

        var manipulatorType: ManipulatorType {
            switch self {
            case .mouseMotionToScroll: return .mouseMotionToScroll
            case .mouseButton: return .mouseBasic
            case .keyboard, .consumer, .typedString, .anyKey: return .basic
            }
        }

        var keyType: TriggerKeyType {
            switch self {
            case .keyboard: return .keyboard
            case .consumer: return .consumer
            case .mouseButton: return .pointing
            case .typedString: return .typedString
            case .anyKey: return .any
            case .mouseMotionToScroll: return .keyboard // not used
            }
        }
    }

    private var unifiedTriggerType: UnifiedTriggerType {
        if manipulator.manipulatorType == .mouseMotionToScroll {
            return .mouseMotionToScroll
        }
        // Map from existing manipulatorType + trigger.keyType
        switch manipulator.trigger.keyType {
        case .keyboard: return .keyboard
        case .consumer: return .consumer
        case .pointing: return .mouseButton
        case .typedString: return .typedString
        case .any: return .anyKey
        }
    }

    private var unifiedTriggerTypeBinding: Binding<UnifiedTriggerType> {
        Binding(
            get: { unifiedTriggerType },
            set: { newValue in
                store.updateManipulator(manipulator.id) { manipulator in
                    manipulator.manipulatorType = newValue.manipulatorType
                    if newValue != .mouseMotionToScroll {
                        manipulator.trigger.keyType = newValue.keyType
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var keyboardTriggerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.isRecordingTrigger
                 ? "Press the keys in order, then click Done."
                 : "Record any key combination or sequence you want to trigger this manipulator.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let simultaneous = manipulator.trigger.simultaneous, simultaneous.isValid {
                Text("Chord: \(simultaneous.keys.map(\.displayLabel).joined(separator: " + "))")
                    .font(.system(.body, design: .monospaced))
                Button("Clear chord") {
                    store.updateManipulator(manipulator.id) { $0.trigger.simultaneous = nil }
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                if store.isRecordingTrigger {
                    ForEach(Array(store.recordedTriggerSteps.enumerated()), id: \.offset) { index, step in
                        TriggerStepBadge(step: step) {
                            store.removeRecordedTriggerStep(at: index)
                        }
                    }
                } else {
                    if manipulator.trigger.steps.isEmpty {
                        Text("Not recorded")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        ForEach(Array(manipulator.trigger.steps.enumerated()), id: \.offset) { index, step in
                            TriggerStepBadge(step: step) {
                                store.removeTriggerStep(at: index, from: manipulator.id)
                            }
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                if store.isRecordingTrigger {
                    Button(role: .destructive) {
                        store.stopTriggerRecording(save: false)
                    } label: {
                        Text("Cancel")
                    }
                    Spacer()
                    Button {
                        store.stopTriggerRecording(save: true)
                    } label: {
                        Text("Done")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.startTriggerRecording(for: manipulator.id)
                    } label: {
                        Text(manipulator.trigger.steps.isEmpty ? "Record Trigger" : "Re-record")
                    }
                    if !manipulator.trigger.steps.isEmpty {
                        Button(role: .destructive) {
                            store.updateManipulator(manipulator.id) { $0.trigger.steps.removeAll() }
                        } label: {
                            Text("Clear")
                        }
                    }
                }
            }

            // Modifier info for selected step
            if let firstStep = manipulator.trigger.steps.first, !firstStep.key.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modifier matching")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("Mandatory:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        modifierChips(for: firstStep.mandatoryModifiers) { mods in
                            store.updateManipulator(manipulator.id) {
                                guard $0.trigger.steps.indices.contains(0) else { return }
                                $0.trigger.steps[0].mandatoryModifiers = mods
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Optional:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        modifierChips(for: firstStep.optionalModifiers) { mods in
                            store.updateManipulator(manipulator.id) {
                                guard $0.trigger.steps.indices.contains(0) else { return }
                                $0.trigger.steps[0].optionalModifiers = mods
                            }
                        }
                    }
                }
            }

            // Simultaneous chord trigger
            if manipulator.trigger.steps.isEmpty {
                Button("Add simultaneous (chord) trigger") {
                    store.updateManipulator(manipulator.id) {
                        $0.trigger.simultaneous = SimultaneousTrigger(keys: [])
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            // Hot Key multi-tap / hold configuration
            if !manipulator.trigger.steps.isEmpty || manipulator.trigger.anyKey {
                hotKeyTriggerEditor
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
                        .background(selected.contains(mod) ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hot Key trigger configuration

    @ViewBuilder
    private var hotKeyTriggerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Hot Key Behavior")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Enabled", isOn: hotKeyEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            if manipulator.trigger.hotKey != nil {
                VStack(alignment: .leading, spacing: 10) {
                    // Tap count
                    HStack(spacing: 8) {
                        Text("Tap count:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Stepper(value: hotKeyTapCountBinding, in: 1...5) {
                            Text("\(manipulator.trigger.hotKey?.tapCount ?? 2)")
                                .font(.system(.body, design: .monospaced))
                                .frame(minWidth: 24)
                        }
                        .controlSize(.small)
                        Text("taps\(manipulator.trigger.hotKey?.tapCount ?? 2 > 1 ? " (multi-tap)" : " (single)")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Tap timeout
                    HStack(spacing: 8) {
                        Text("Timeout:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        TextField("ms", value: hotKeyTimeoutBinding, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .font(.system(.body, design: .monospaced))
                        Text("ms between taps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Hold required toggle
                    Toggle(isOn: hotKeyHoldRequiredBinding) {
                        Text("Require final tap to be held")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if manipulator.trigger.hotKey?.holdRequired == true {
                        HStack(spacing: 8) {
                            Text("Hold duration:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            TextField("ms", value: hotKeyHoldThresholdBinding, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.system(.body, design: .monospaced))
                            Text("ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Hot Key Bindings

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

    @ViewBuilder
    private var consumerTriggerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a media/consumer key to trigger this manipulator.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Consumer key", selection: consumerKeyBinding) {
                Text("Select...").tag("")
                ForEach(ConsumerKeyCode.allCases) { key in
                    Text(key.label).tag(key.rawValue)
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var pointingTriggerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a mouse button to trigger this manipulator.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Mouse button", selection: pointingButtonBinding) {
                Text("Select...").tag("")
                ForEach(PointingButton.allCases) { btn in
                    Text(btn.label).tag(btn.rawValue)
                }
            }
            .labelsHidden()
        }
    }

    private var typedStringTriggerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type a string to match.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Target string
            HStack {
                Text("Match string:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("e.g. teh", text: typedStringBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            // Match mode picker
            HStack {
                Text("Match mode:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Picker("Match mode", selection: typedStringMatchModeBinding) {
                    ForEach(StringTriggerMatchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Clear on match toggle
            Toggle(isOn: typedStringClearOnMatchBinding) {
                Text("Clear buffer after match")
                    .font(.caption)
            }

            // App-specific scope
            HStack {
                Text("App scope:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                TextField("com.apple.Safari (leave empty for all apps)", text: typedStringAppBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Timeout slider
            HStack {
                Text("Timeout:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Slider(value: typedStringTimeoutBinding, in: 0.5...10, step: 0.5)
                    .frame(maxWidth: 200)
                Text(String(format: "%.1fs", manipulator.trigger.stringTrigger?.timeoutSeconds ?? 2.0))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Text("inactivity clears the buffer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Help text for selected match mode
            Text(stringTriggerHelpText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    /// Returns the help text for the currently selected string trigger match mode.
    private var stringTriggerHelpText: String {
        manipulator.trigger.stringTrigger?.matchMode.helpText
            ?? StringTriggerMatchMode.fullMatch.helpText
    }

    @ViewBuilder
    private var conditionsSection: some View {
        CollapsibleStepCard(title: "Only if", accentColor: .orange, isExpanded: $conditionsExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if manipulator.conditions.isEmpty {
                    Text("No conditions. This manipulator will fire in any context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(manipulator.conditions) { condition in
                        ConditionStepRow(
                            condition: condition,
                            onChange: { transform in
                                store.updateCondition(condition.id, in: manipulator.id, transform)
                            },
                            onDelete: {
                                store.removeCondition(condition.id, from: manipulator.id)
                            },
                            onChangeKind: {
                                replacingConditionID = condition.id
                                withAnimation { activeLibrary = .condition }
                            }
                        )
                        .cardStyle()
                        if condition.id != manipulator.conditions.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                Button {
                    withAnimation { activeLibrary = .condition }
                } label: {
                    Label("Add condition", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        CollapsibleStepCard(title: "Do", accentColor: .green, isExpanded: $actionsExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if manipulator.actions.isEmpty {
                    Text("No actions. Add one to make this manipulator do something.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(manipulator.actions) { action in
                        ActionStepRow(
                            store: store,
                            action: action,
                            onChange: { transform in
                                store.updateAction(action.id, in: manipulator.id, transform)
                            },
                            onDelete: {
                                store.removeAction(action.id, from: manipulator.id)
                            },
                            onChangeKind: {
                                replacingActionID = action.id
                                withAnimation { activeLibrary = .action }
                            }
                        )
                        .cardStyle()
                        if action.id != manipulator.actions.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                Button {
                    withAnimation { activeLibrary = .action }
                } label: {
                    Label("Add action", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private var parametersSection: some View {
        CollapsibleStepCard(title: "Parameters", accentColor: .purple, isExpanded: $parametersExpanded) {
            ManipulatorParametersEditor(
                parameters: manipulator.parameters,
                onChange: { newParams in
                    store.updateManipulator(manipulator.id) { $0.parameters = newParams }
                }
            )
        }
    }

    private var notesSection: some View {
        CollapsibleStepCard(title: "Description", accentColor: .gray, isExpanded: $notesExpanded) {
            TextField("Optional notes for this manipulator", text: notesBinding, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .font(.body)
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { manipulator.name },
            set: { newValue in store.updateManipulatorCosmetic(manipulator.id) { $0.name = newValue } }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { manipulator.isEnabled },
            set: { newValue in store.updateManipulator(manipulator.id) { $0.isEnabled = newValue } }
        )
    }

    private var folderBinding: Binding<String> {
        Binding(
            get: { manipulator.folder },
            set: { newValue in store.updateManipulatorCosmetic(manipulator.id) { $0.folder = newValue } }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { manipulator.notes },
            set: { newValue in store.updateManipulatorCosmetic(manipulator.id) { $0.notes = newValue } }
        )
    }

    private var triggerNameBinding: Binding<String> {
        Binding(
            get: { manipulator.trigger.triggerName },
            set: { newValue in
                store.updateManipulatorCosmetic(manipulator.id) { $0.trigger.triggerName = newValue }
            }
        )
    }

    private var consumerKeyBinding: Binding<String> {
        Binding(
            get: { manipulator.trigger.steps.first?.key ?? "" },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    $0.trigger.steps = newValue.isEmpty ? [] : [KeyShortcut(key: newValue)]
                }
            }
        )
    }

    private var pointingButtonBinding: Binding<String> {
        Binding(
            get: { manipulator.trigger.steps.first?.key ?? "" },
            set: { newValue in
                store.updateManipulator(manipulator.id) {
                    $0.trigger.steps = newValue.isEmpty ? [] : [KeyShortcut(key: newValue)]
                }
            }
        )
    }

    /// Binding to the typed-string trigger string value.
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

    /// Binding to the typed-string match mode.
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

    /// Binding to the typed-string timeout (seconds).
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

    /// Binding to the typed-string clearOnMatch toggle.
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

    /// Binding to the typed-string app bundle ID.
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
}

// MARK: - Step card shell

// MARK: - Editor Card (used to wrap each section)

struct EditorCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Card style modifier (for individual rows)

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}

// MARK: - Step card shell

struct StepCard<Content: View>: View {
    let title: String
    var accentColor: Color = .secondary
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Collapsible Step Card

struct CollapsibleStepCard<Content: View>: View {
    let title: String
    var accentColor: Color = .secondary
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Add step menu

struct AddStepMenu: View {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let label: String
    let items: [Item]
    let action: (Item) -> Void

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    action(item)
                } label: {
                    Text(item.title)
                }
            }
        } label: {
            Text(label).font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Trigger step badge

struct TriggerStepBadge: View {
    let step: KeyShortcut
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(step.displayLabel)
                .font(.body.monospaced())
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Tag editor field

struct TagEditorField: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    @State private var newTag: String = ""

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(manipulator.tags.sorted(), id: \.self) { tag in
                Button {
                    store.toggleTag(tag, on: manipulator.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag).font(.caption)
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            TextField("Add tag", text: $newTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(minWidth: 60)
                .onSubmit { addCurrentTag() }
        }
    }

    private func addCurrentTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.updateManipulatorCosmetic(manipulator.id) { $0.tags.insert(trimmed) }
        newTag = ""
    }
}




