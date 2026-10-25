import SwiftUI

struct ManipulatorEditorView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    @State private var activeLibrary: ActiveLibrary? = nil
    /// Where a newly picked action should be appended.
    @State private var pendingActionTarget: ActionTarget = .direct
    /// When set, the picked action replaces this existing action.
    @State private var replacingAction: (target: ActionTarget, id: UUID)? = nil
    /// Which block a newly picked condition belongs to.
    @State private var pendingConditionBlock: UUID? = nil
    /// When set, the picked condition kind replaces this existing condition.
    @State private var replacingCondition: (blockID: UUID, id: UUID)? = nil
    @FocusState private var nameFieldFocused: Bool

    private enum ActiveLibrary: String, Identifiable {
        case action
        case condition

        var id: String { rawValue }
    }

    var body: some View {
        editorContent
            .sheet(item: $activeLibrary) { library in
                switch library {
                case .action:
                    ActionLibraryBrowser(isPresented: sheetBinding) { kind in
                        if let replacing = replacingAction {
                            switch replacing.target {
                            case .direct:
                                store.updateAction(replacing.id, in: manipulator.id) { $0.kind = kind }
                            case .block(let blockID, let side):
                                store.updateTreeAction(replacing.id, in: manipulator.id) { $0.kind = kind }
                            }
                            replacingAction = nil
                        } else {
                            switch pendingActionTarget {
                            case .direct:
                                store.addAction(kind, to: manipulator.id)
                            case .block(let blockID, let side):
                                store.addTreeAction(manipulator.id, to: blockID, in: side.keyPath, kind: kind)
                            }
                        }
                    }
                case .condition:
                    ConditionLibraryBrowser(isPresented: sheetBinding) { kind in
                        if let replacing = replacingCondition {
                            store.updateBlockCondition(manipulator.id, conditionID: replacing.id, inBlock: replacing.blockID) { $0.kind = kind }
                            replacingCondition = nil
                        } else if let blockID = pendingConditionBlock {
                            store.addBlockCondition(manipulator.id, to: blockID, kind: kind)
                            pendingConditionBlock = nil
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
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                triggerSection
                conditionsSection
                actionsSection
                organizationSection
                advancedSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Trigger

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Trigger type", selection: unifiedTriggerTypeBinding) {
                ForEach(UnifiedTriggerType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .labelsHidden()

            switch unifiedTriggerType {
            case .keyboard:
                KeyboardTriggerEditor(store: store, manipulator: manipulator)
            case .consumer:
                ConsumerTriggerEditor(store: store, manipulator: manipulator)
            case .mouseButton:
                PointingTriggerEditor(store: store, manipulator: manipulator)
            case .typedString:
                TypedStringTriggerEditor(store: store, manipulator: manipulator)
            case .anyKey, .mouseMotionToScroll:
                EmptyView()
            }

            Text(triggerSectionFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        if !manipulator.usesConditionalBranches {
            VStack(alignment: .leading, spacing: 8) {
                Text("No conditions. This manipulator fires in any context.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Add if condition") {
                    store.convertToConditional(manipulator.id)
                }
            }
        } else if let root = manipulator.rootBlock {
            NestedBranchSection(
                store: store,
                manipulator: manipulator,
                root: root,
                onAddCondition: { blockID in
                    pendingConditionBlock = blockID
                    withAnimation { activeLibrary = .condition }
                },
                onReplaceCondition: { blockID, conditionID in
                    replacingCondition = (blockID: blockID, id: conditionID)
                    withAnimation { activeLibrary = .condition }
                },
                onAddAction: { blockID, side in
                    pendingActionTarget = .block(blockID: blockID, side: side)
                    withAnimation { activeLibrary = .action }
                },
                onReplaceAction: { blockID, side, actionID in
                    replacingAction = (target: .block(blockID: blockID, side: side), id: actionID)
                    withAnimation { activeLibrary = .action }
                },
                onExitBranchMode: {
                    store.exitConditionalMode(manipulator.id)
                }
            )
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        // In conditional mode the actions live inside the if/elif/else branches.
        if !manipulator.usesConditionalBranches {
            VStack(alignment: .leading, spacing: 8) {
                if manipulator.actions.isEmpty {
                    Text("No actions. Add one to make this manipulator do something.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                                replacingAction = (target: .direct, id: action.id)
                                withAnimation { activeLibrary = .action }
                            },
                            onMoveUp: {
                                moveAction(action: action, up: true)
                            },
                            onMoveDown: {
                                moveAction(action: action, up: false)
                            },
                            onDuplicate: {
                                store.duplicateAction(action.id, in: manipulator.id)
                            }
                        )
                    }
                }
                Button("Add action") {
                    pendingActionTarget = .direct
                    withAnimation { activeLibrary = .action }
                }
            }
        }
    }

    // MARK: - Organization

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    Button("None") {
                        store.updateManipulatorCosmetic(manipulator.id) { $0.folder = "" }
                    }
                    Divider()
                    ForEach(store.allFolders, id: \.self) { folderName in
                        Button(folderName) {
                            store.updateManipulatorCosmetic(manipulator.id) { $0.folder = folderName }
                        }
                    }
                    Divider()
                    Button("New Folder…") {
                        let alert = NSAlert()
                        alert.messageText = "New Folder"
                        alert.informativeText = "Enter a name for the new folder"
                        alert.addButton(withTitle: "OK")
                        alert.addButton(withTitle: "Cancel")
                        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                        alert.accessoryView = textField
                        textField.becomeFirstResponder()
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !folderName.isEmpty {
                                store.updateManipulatorCosmetic(manipulator.id) { $0.folder = folderName }
                            }
                        }
                    }
                } label: {
                    Label(manipulator.folder.isEmpty ? "No folder" : manipulator.folder, systemImage: "folder")
                }

                TagTokenField(
                    tags: Binding(
                        get: { Array(manipulator.tags).sorted() },
                        set: { newTags in
                            store.updateManipulatorCosmetic(manipulator.id) { $0.tags = Set(newTags) }
                        }
                    ),
                    completions: store.allTags,
                    placeholder: "Add tags…"
                )
                .frame(height: 22)
            }

            Toggle("Starred", isOn: Binding(
                get: { manipulator.isStarred },
                set: { _ in store.toggleStarred(manipulator.id) }
            ))
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !manipulator.trigger.triggerName.isEmpty {
                let triggerName = manipulator.trigger.triggerName
                LabeledContent("Named trigger", value: triggerName)
            } else {
                TextField("Named trigger", text: triggerNameBinding)
                    .placeholder(when: triggerNameBinding.wrappedValue.isEmpty) {
                        Text("Named trigger (optional)").foregroundColor(.secondary)
                    }
            }
            Text("Lets the Execute Named Trigger action fire this manipulator directly.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ContextualParametersEditor(manipulator: manipulator, parameters: parametersBinding)
        }
    }

    // MARK: - Header Section (unchanged)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: nameBinding)
                    .font(.title)
                    .labelsHidden()
                    .focused($nameFieldFocused)
                Toggle("Enabled", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            TextField("Description", text: notesBinding, axis: .vertical)
                .lineLimit(2...6)
        }
        .onAppear { focusNameIfNew() }
        .onChange(of: manipulator.id) { _, _ in focusNameIfNew() }
    }

    private func focusNameIfNew() {
        guard store.focusNameForManipulatorID == manipulator.id else { return }
        // Defer both the store mutation and the focus change: this runs
        // during a view update, and publishing then is undefined behaviour
        // (it can wedge the whole editor).
        DispatchQueue.main.async {
            store.focusNameForManipulatorID = nil
            nameFieldFocused = true
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

    private var triggerSectionFooter: String {
        switch unifiedTriggerType {
        case .keyboard:
            return "Press keys in sequence, or press a chord together."
        case .consumer:
            return "Media/consumer keys like brightness and volume."
        case .mouseButton:
            return "Mouse buttons like back, forward, or middle click."
        case .typedString:
            return "Fire when an exact string of characters is typed."
        case .anyKey:
            return "Fire on any key press."
        case .mouseMotionToScroll:
            return "Turn mouse movement into scrolling while active."
        }
    }

    // MARK: - Actions Section Helpers

    private func moveAction(action: Action, up: Bool) {
        guard let index = manipulator.actions.firstIndex(where: { $0.id == action.id }) else { return }
        let newIndex = up ? index - 1 : index + 1
        guard newIndex >= 0 && newIndex < manipulator.actions.count else { return }
        let fromIndex = IndexSet(integer: index)
        let toIndex = newIndex > index ? newIndex + 1 : newIndex // because move(from:to:) adjusts for removal
        store.moveAction(from: fromIndex, to: toIndex, in: manipulator.id)
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

    private var parametersBinding: Binding<ManipulatorParameters> {
        Binding(
            get: { manipulator.parameters },
            set: { newParams in
                store.updateManipulator(manipulator.id) { $0.parameters = newParams }
            }
        )
    }
}

// MARK: - Shared section containers
// EditorCard and CollapsibleStepCard remain for Menu Bar editor use.

// MARK: - Collapsible Step Card (native DisclosureGroup)

struct CollapsibleStepCard<Content: View>: View {
    let title: String
    var accentColor: Color = .secondary
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(title: String, accentColor: Color = .secondary, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 8)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Editor Card (Apple Settings-style section)

struct EditorCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Conditional branch target

/// Where a newly picked action from the library should be appended.
enum ActionTarget: Hashable {
    case direct
    case block(blockID: UUID, side: BlockSide)
}

/// Which half of a block's body a step belongs to: the `then` list or the
/// `else` list. `otherwise` avoids reserving the `else` keyword as an ID.
enum BlockSide: String, Hashable {
    case then
    case otherwise

    var keyPath: WritableKeyPath<BranchBlock, [BranchStep]> {
        switch self {
        case .then: return \.thenSteps
        case .otherwise: return \.elseSteps
        }
    }

    var label: String {
        switch self {
        case .then: return "Then"
        case .otherwise: return "Else"
        }
    }
}

/// Scope options shared by the root block header (same list the branch cards used).
func blockScopeOptions(for manipulator: Manipulator, current: BranchTriggerScope) -> [(title: String, scope: BranchTriggerScope)] {
    var options: [(String, BranchTriggerScope)] = [
        ("Any trigger", .any),
        ("Main trigger", .main)
    ]
    for (idx, additional) in manipulator.additionalTriggers.enumerated() {
        let label = additional.trigger.displayLabel
        let title = label.isEmpty || label == "Not recorded"
            ? "Extra trigger \(idx + 1)"
            : "Extra \(idx + 1): \(label)"
        options.append((String(title.prefix(28)), .additional(id: additional.id)))
    }
    // Keep the current selection visible if its trigger was deleted.
    if case .additional(let id) = current,
       !manipulator.additionalTriggers.contains(where: { $0.id == id }) {
        options.append(("Removed trigger", current))
    }
    return options
}

// MARK: - Hierarchical if / else (code-editor style)

/// The condition section active state: renders the root `if` block and all
/// nested blocks recursively, with indentation, a connecting gutter, and
/// monospaced if/else keywords — like a code editor.
struct NestedBranchSection: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let root: BranchBlock
    var onAddCondition: (UUID) -> Void
    var onReplaceCondition: (_ blockID: UUID, _ conditionID: UUID) -> Void
    var onAddAction: (_ blockID: UUID, _ side: BlockSide) -> Void
    var onReplaceAction: (_ blockID: UUID, _ side: BlockSide, _ actionID: UUID) -> Void
    var onExitBranchMode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BranchBlockView(
                store: store,
                manipulator: manipulator,
                block: root,
                isRoot: true,
                depth: 0,
                onAddCondition: onAddCondition,
                onReplaceCondition: onReplaceCondition,
                onAddAction: onAddAction,
                onReplaceAction: onReplaceAction
            )

            HStack(spacing: 12) {
                Button {
                    store.addNestedBlock(manipulator.id, to: root.id, in: \.thenSteps)
                } label: {
                    Label("Add if inside", systemImage: "plus.square.on.square")
                }
                .help("Nest an if block inside the root.")

                Spacer()

                Button(role: .destructive) {
                    onExitBranchMode()
                } label: {
                    Text("Back to simple mode")
                }
                .help("Flatten all branching back into a plain action list.")
            }
        }
    }
}

/// One `if` block, rendered like a code block: a keyword row, an indented
/// body with a gutter, and an `else` half. Nested blocks recurse.
struct BranchBlockView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let block: BranchBlock
    let isRoot: Bool
    let depth: Int
    var onAddCondition: (UUID) -> Void
    var onReplaceCondition: (_ blockID: UUID, _ conditionID: UUID) -> Void
    var onAddAction: (_ blockID: UUID, _ side: BlockSide) -> Void
    var onReplaceAction: (_ blockID: UUID, _ side: BlockSide, _ actionID: UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider().opacity(isRoot ? 0 : 0.25)
            codeBody
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(blockBackground)
        .overlay(blockOutline)
    }

    // MARK: pieces

    private var headerRow: some View {
        HStack(spacing: 8) {
            KeywordChip("if", tone: isRoot ? .title : .comment)

            if block.conditions.isEmpty {
                Text("always")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach(blockScopeOptions(for: manipulator, current: block.triggerScope), id: \.scope) { option in
                    Button(option.title) { store.setBlockTriggerScope(manipulator.id, blockID: block.id, scope: option.scope) }
                }
            } label: {
                Label(scopeLabel(block.triggerScope), systemImage: "scope")
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Only run this block for a specific trigger, or for any trigger.")
            .accessibilityLabel("Trigger scope for this block")

            if block.conditions.count > 1 {
                Picker("Match", selection: matchAllBinding) {
                    Text("All").tag(true)
                    Text("Any").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Require all conditions, or any of them.")
            }

            Spacer(minLength: 8)

            if isRoot {
                Button {
                    onAddCondition(block.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Add condition to this block")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35))
        .contextMenu {
            if !isRoot {
                Button("Add condition…") { onAddCondition(block.id) }
                Divider()
                Button("Unwrap (keep then steps)") {
                    store.unwrapTreeBlock(block.id, in: manipulator.id)
                }
                Button("Delete block and contents", role: .destructive) {
                    store.deleteTreeBlock(block.id, in: manipulator.id)
                }
            }
        }
    }

    /// Indented body with a connecting gutter line, split into then/else.
    private var codeBody: some View {
        HStack(alignment: .top, spacing: 0) {
            // Gutter: connects the block header (Xcode-style code line) down the body.
            Rectangle()
                .fill(.quaternary)
                .frame(width: 2)
                .padding(.leading, 18)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 10) {
                conditionRows

                StepList(
                    store: store,
                    manipulator: manipulator,
                    blockID: block.id,
                    side: .then,
                    steps: block.thenSteps,
                    indent: depth + 1,
                    onAddCondition: onAddCondition,
                    onReplaceCondition: onReplaceCondition,
                    onAddAction: onAddAction,
                    onReplaceAction: onReplaceAction
                )

                if !block.elseSteps.isEmpty {
                    HStack(spacing: 6) {
                        KeywordChip("else", tone: .comment)
                        Rectangle().fill(.quaternary).frame(height: 1)
                    }
                    .padding(.trailing, 6)

                    StepList(
                        store: store,
                        manipulator: manipulator,
                        blockID: block.id,
                        side: .otherwise,
                        steps: block.elseSteps,
                        indent: depth + 1,
                        onAddCondition: onAddCondition,
                        onReplaceCondition: onReplaceCondition,
                        onAddAction: onAddAction,
                        onReplaceAction: onReplaceAction
                    )
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var conditionRows: some View {
        if !block.conditions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(block.conditions) { condition in
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle()
                            .fill(.quaternary.opacity(0.6))
                            .frame(width: 2, height: 18)
                        ConditionStepRow(
                            condition: condition,
                            onChange: { transform in
                                store.updateBlockCondition(manipulator.id, conditionID: condition.id, inBlock: block.id, transform)
                            },
                            onDelete: {
                                store.removeBlockCondition(manipulator.id, conditionID: condition.id, fromBlock: block.id)
                            },
                            onChangeKind: {
                                onReplaceCondition(block.id, condition.id)
                            }
                        )
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var blockBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background.secondary)
    }

    private var blockOutline: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.quinary, lineWidth: 1)
    }

    private var matchAllBinding: Binding<Bool> {
        Binding(
            get: { block.matchAll },
            set: { newValue in
                store.setBlockMatchAll(manipulator.id, blockID: block.id, matchAll: newValue)
            }
        )
    }
}

/// A monospaced `if` / `else` keyword, styled like a code token.
struct KeywordChip: View {
    let keyword: String
    let tone: Tone

    enum Tone {
        case title
        case comment
    }

    init(_ keyword: String, tone: Tone = .title) {
        self.keyword = keyword
        self.tone = tone
    }

    var body: some View {
        Text(keyword)
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(tone == .title ? Color.pink : Color.gray)
    }
}

private func scopeLabel(_ scope: BranchTriggerScope) -> String {
    switch scope {
    case .any: return "Any trigger"
    case .main: return "Main trigger"
    case .additional: return "Extra trigger"
    }
}

/// A mixed list of steps (actions and nested blocks) inside a block,
/// plus the row of add-buttons that operates on that list.
struct StepList: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let blockID: UUID
    let side: BlockSide
    let steps: [BranchStep]
    let indent: Int
    var onAddCondition: (UUID) -> Void
    var onReplaceCondition: (_ blockID: UUID, _ conditionID: UUID) -> Void
    var onAddAction: (_ blockID: UUID, _ side: BlockSide) -> Void
    var onReplaceAction: (_ blockID: UUID, _ side: BlockSide, _ actionID: UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if steps.isEmpty {
                Text(side == .then ? "No steps in this branch yet." : "Nothing runs on else.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    BranchStepRowView(
                        store: store,
                        manipulator: manipulator,
                        step: step,
                        blockID: blockID,
                        side: side,
                        index: index,
                        depth: indent,
                        onAddCondition: onAddCondition,
                        onReplaceCondition: onReplaceCondition,
                        onAddAction: onAddAction,
                        onReplaceAction: onReplaceAction
                    )
                    if index < steps.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAddAction(blockID, side)
                } label: {
                    Label(side.label + " action", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .font(.footnote)

                Menu {
                    Button("Add condition to this block…") { onAddCondition(blockID) }
                    Button("Nest an if block here") {
                        store.addNestedBlock(manipulator.id, to: blockID, in: side.keyPath)
                    }
                } label: {
                    Label("More…", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .font(.footnote)
                .fixedSize()
            }
        }
    }
}

/// Renders one step: an action row, or a nested block (recursion).
struct BranchStepRowView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator
    let step: BranchStep
    let blockID: UUID
    let side: BlockSide
    let index: Int
    let depth: Int
    var onAddCondition: (UUID) -> Void
    var onReplaceCondition: (_ blockID: UUID, _ conditionID: UUID) -> Void
    var onAddAction: (_ blockID: UUID, _ side: BlockSide) -> Void
    var onReplaceAction: (_ blockID: UUID, _ side: BlockSide, _ actionID: UUID) -> Void

    var body: some View {
        switch step {
        case .action(let action):
            ActionStepRow(
                store: store,
                action: action,
                onChange: { transform in
                    store.updateTreeAction(action.id, in: manipulator.id, transform)
                },
                onDelete: {
                    store.removeTreeStep(action.id, from: manipulator.id)
                },
                onChangeKind: {
                    onReplaceAction(blockID, side, action.id)
                },
                onMoveUp: index > 0 ? { move(offset: -1) } : nil,
                onMoveDown: { move(offset: 1) },
                onDuplicate: {
                    store.duplicateTreeAction(action.id, in: manipulator.id)
                }
            )
            .contextMenu {
                Button("Wrap in if…") {
                    store.wrapTreeStepInBlock(action.id, in: manipulator.id)
                }
                Divider()
                Button("Move Up", action: { move(offset: -1) })
                Button("Move Down", action: { move(offset: 1) })
                Divider()
                Button("Delete", role: .destructive) {
                    store.removeTreeStep(action.id, from: manipulator.id)
                }
            }
        case .block(let nested):
            BranchBlockView(
                store: store,
                manipulator: manipulator,
                block: nested,
                isRoot: false,
                depth: depth + 1,
                onAddCondition: onAddCondition,
                onReplaceCondition: onReplaceCondition,
                onAddAction: onAddAction,
                onReplaceAction: onReplaceAction
            )
            .padding(.top, 2)
        }
    }

    private func move(offset: Int) {
        let adjusted = index + offset
        guard (0...Int.max).contains(adjusted) else { return }
        store.moveTreeStep(manipulator.id, in: blockID, side: side.keyPath, fromOffsets: IndexSet(integer: index), toOffset: adjusted)
    }
}

// MARK: - Trigger step badge

struct TriggerStepBadge: View {
    let step: KeyShortcut
    let onDelete: () -> Void

    var body: some View {
        LabeledContent(step.displayLabel) {
            Button("Remove", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Placeholder ViewModifier (for textfield placeholder)

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}