import SwiftUI
import UniformTypeIdentifiers

// MARK: - Visual Workflow Builder

/// A native list rendering of a manipulator's trigger, nested if/else
/// blocks, and actions. Rows reorder via drag and delete via swipe.
struct WorkflowBuilderView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    @State private var draggedItemID: String?

    private var mid: UUID { manipulator.id }

    var body: some View {
        List {
            Section("Trigger") {
                VStack(alignment: .leading) {
                    Text(manipulator.trigger.displayLabel)
                    Text(manipulator.trigger.keyType.rawValue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !manipulator.usesConditionalBranches {
                Section("Actions") {
                    ForEach(manipulator.actions) { action in
                        WorkflowActionRow(
                            action: action,
                            onDelete: { store.removeAction(action.id, from: mid) }
                        )
                        .onDrag {
                            draggedItemID = "step:direct|then:\(action.id)"
                            return NSItemProvider(object: "step:direct|then:\(action.id)" as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: WorkflowDropDelegate(
                                targetID: action.id,
                                listScope: .directThen,
                                manipulatorID: mid,
                                store: store,
                                draggedItemID: $draggedItemID
                            )
                        )
                    }
                    Button("Add Action") { store.addActionTo(mid) }
                    Button("Add If Condition") { store.convertToConditional(mid) }
                }
            } else if let root = manipulator.rootBlock {
                WorkflowBlockRows(
                    manipulator: manipulator,
                    block: root,
                    depth: 0,
                    draggedItemID: $draggedItemID,
                    store: store
                )

                Section {
                    Button("Flatten to Simple Mode") { store.exitConditionalMode(mid) }
                }
            }
        }
    }
}

// MARK: - Nested block rows (recursive)

/// Renders one block as list sections: its conditions, then-steps and
/// (when present) else-steps. Nested blocks recurse with an "inside" label.
private struct WorkflowBlockRows: View {
    let manipulator: Manipulator
    let block: BranchBlock
    let depth: Int
    @Binding var draggedItemID: String?
    @ObservedObject var store: RemapStore

    private var mid: UUID { manipulator.id }

    var body: some View {
        Section(depth == 0 ? "If" : "If (nested ×\(depth))") {
            if block.conditions.isEmpty {
                Text("Always matches — add a condition to gate it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(block.conditions) { condition in
                WorkflowConditionRow(
                    condition: condition,
                    onDelete: {
                        store.removeBlockCondition(mid, conditionID: condition.id, fromBlock: block.id)
                    }
                )
                .onDrag {
                    draggedItemID = "step:\(block.id.uuidString)|condition:\(condition.id)"
                    return NSItemProvider(object: "step:\(block.id.uuidString)|condition:\(condition.id)" as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: WorkflowDropDelegate(
                        targetID: condition.id,
                        listScope: .condition(block: block.id),
                        manipulatorID: mid,
                        store: store,
                        draggedItemID: $draggedItemID
                    )
                )
            }
            Button("Add Condition") { store.addBlockCondition(mid, to: block.id) }

            MaybeDivider()

            ForEach(Array(block.thenSteps.enumerated()), id: \.element.id) { index, step in
                workflowStepRow(step, side: .then, blockID: block.id, depth: depth)
                if index < block.thenSteps.count - 1 {
                    MaybeDivider()
                }
            }
            if block.thenSteps.isEmpty {
                Text("No steps in this branch yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Add Then Action") {
                store.addTreeAction(mid, to: block.id, in: \.thenSteps, kind: .sendKey)
            }

            MaybeDivider()

            if block.elseSteps.isEmpty {
                Button("Add Else Steps") {
                    store.addTreeAction(mid, to: block.id, in: \.elseSteps, kind: .sendKey)
                }
            } else {
                Text("Else")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(block.elseSteps) { step in
                    workflowStepRow(step, side: .otherwise, blockID: block.id, depth: depth)
                }
                Button("Add Else Action") {
                    store.addTreeAction(mid, to: block.id, in: \.elseSteps, kind: .sendKey)
                }
            }
        }
    }

    @ViewBuilder
    private func workflowStepRow(_ step: BranchStep, side: BlockSide, blockID: UUID, depth: Int) -> some View {
        switch step {
        case .action(let action):
            WorkflowActionRow(
                action: action,
                onDelete: { store.removeTreeStep(action.id, from: mid) }
            )
            .onDrag {
                let scope = "block:\(blockID.uuidString)#\(side.rawValue)"
                draggedItemID = "step:\(scope):\(action.id)"
                return NSItemProvider(object: "step:\(scope):\(action.id)" as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: WorkflowDropDelegate(
                    targetID: action.id,
                    listScope: .block(blockID, side),
                    manipulatorID: mid,
                    store: store,
                    draggedItemID: $draggedItemID
                )
            )
        case .block(let nested):
            WorkflowBlockRows(
                manipulator: manipulator,
                block: nested,
                depth: depth + 1,
                draggedItemID: $draggedItemID,
                store: store
            )
        }
    }
}

private struct MaybeDivider: View {
    var body: some View {
        Divider()
    }
}

// MARK: - Drag-and-drop targets

/// Identifies which list a drop will reorder. Cheap value type — the
/// delegate later locates the owning list inside the tree by walking it.
private enum DropList: Equatable {
    /// The manipulator's direct actions.
    case directThen
    /// A block's condition list.
    case condition(block: UUID)
    /// A block's then or else list.
    case block(UUID, BlockSide)
}

// MARK: - Drop Delegate

private struct WorkflowDropDelegate: DropDelegate {
    let targetID: UUID
    let listScope: DropList
    let manipulatorID: UUID
    let store: RemapStore
    @Binding var draggedItemID: String?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Drag payloads look like `step:<scope>:<id>` where scope is
    /// `direct|then`, `block:<uuid>#then|else`, or `block:<uuid>|condition`.
    /// Only same-list drops reorder.
    private func payloadParts(_ payload: String) -> (scope: String, id: UUID)? {
        let parts = payload.split(separator: ":")
        guard parts.count == 3, let id = UUID(uuidString: String(parts[2])) else { return nil }
        return (String(parts[1]), id)
    }

    private var targetScope: String {
        switch listScope {
        case .directThen:
            return "direct|then"
        case .condition(let block):
            return "block:\(block.uuidString)|condition"
        case .block(let block, let side):
            return "block:\(block.uuidString)#\(side.rawValue)"
        }
    }

    /// A "then" side payload from the direct section uses the shared
    /// `block:#then` spelling; accept both spellings for it only.
    private func scopesMatch(_ payloadScope: String) -> Bool {
        payloadScope == targetScope
            || (listScope == .directThen && payloadScope == "block:|then")
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedItemID = nil }
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, error in
            guard let data = data as? Data,
                  let payload = String(data: data, encoding: .utf8),
                  let parts = payloadParts(payload),
                  scopesMatch(parts.scope)
            else { return }
            let sourceID = parts.id

            DispatchQueue.main.async {
                guard let manipulator = store.manipulator(id: manipulatorID) else { return }
                switch listScope {
                case .directThen:
                    guard let from = manipulator.actions.firstIndex(where: { $0.id == sourceID }),
                          let to = manipulator.actions.firstIndex(where: { $0.id == targetID }),
                          from != to
                    else { return }
                    let adjusted = to > from ? to + 1 : to
                    store.moveAction(from: IndexSet(integer: from), to: adjusted, in: manipulatorID)
                case .condition(let blockID):
                    guard let root = manipulator.rootBlock,
                          let (list, from, to) = Self.locateConditions(root, blockID: blockID, source: sourceID, target: targetID),
                          from != to
                    else { return }
                    let adjusted = to > from ? to + 1 : to
                    store.moveBlockCondition(manipulatorID, inBlock: blockID, fromOffsets: IndexSet(integer: from), toOffset: adjusted)
                    _ = list
                case .block(let blockID, let side):
                    guard let root = manipulator.rootBlock,
                          let (_, from, to) = Self.locateSteps(root, blockID: blockID, side: side, source: sourceID, target: targetID),
                          from != to
                    else { return }
                    let adjusted = to > from ? to + 1 : to
                    store.moveTreeStep(manipulatorID, in: blockID, side: side.keyPath, fromOffsets: IndexSet(integer: from), toOffset: adjusted)
                }
            }
        }
        return true
    }

    // MARK: list location helpers

    private static func locateConditions(_ root: BranchBlock, blockID: UUID, source: UUID, target: UUID) -> (list: [Condition], from: Int, to: Int)? {
        func visit(_ block: BranchBlock, _ found: inout (list: [Condition], from: Int, to: Int)?) -> Bool {
            if block.id == blockID {
                guard let f = block.conditions.firstIndex(where: { $0.id == source }),
                      let t = block.conditions.firstIndex(where: { $0.id == target }) else { return false }
                found = (block.conditions, f, t)
                return true
            }
            for step in block.thenSteps {
                if case .block(let nested) = step, visit(nested, &found) { return true }
            }
            for step in block.elseSteps {
                if case .block(let nested) = step, visit(nested, &found) { return true }
            }
            return false
        }
        var result: (list: [Condition], from: Int, to: Int)? = nil
        return visit(root, &result) ? result : nil
    }

    private static func locateSteps(_ root: BranchBlock, blockID: UUID, side: BlockSide, source: UUID, target: UUID) -> (list: [BranchStep], from: Int, to: Int)? {
        func list(_ block: BranchBlock) -> [BranchStep] {
            block[keyPath: side.keyPath]
        }
        func visit(_ block: BranchBlock, _ found: inout (list: [BranchStep], from: Int, to: Int)?) -> Bool {
            if block.id == blockID {
                let steps = list(block)
                guard let f = steps.firstIndex(where: { $0.id == source }),
                      let t = steps.firstIndex(where: { $0.id == target }) else { return false }
                found = (steps, f, t)
                return true
            }
            for step in block.thenSteps {
                if case .block(let nested) = step, visit(nested, &found) { return true }
            }
            for step in block.elseSteps {
                if case .block(let nested) = step, visit(nested, &found) { return true }
            }
            return false
        }
        var result: (list: [BranchStep], from: Int, to: Int)? = nil
        return visit(root, &result) ? result : nil
    }
}

// MARK: - Condition Row

private struct WorkflowConditionRow: View {
    let condition: Condition
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Label(condition.kind.rawValue, systemImage: condition.kind.symbol)
            Text(displayValue)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .swipeActions {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var displayValue: String {
        if condition.kind == .variable || condition.kind == .globalVariable {
            return "\(condition.target) \(condition.op.rawValue) \(condition.value)"
        }
        if condition.kind == .expression {
            return condition.target
        }
        return "\(condition.op.rawValue) \(condition.target)"
    }
}

// MARK: - Action Row

private struct WorkflowActionRow: View {
    let action: Action
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Label(action.kind.rawValue, systemImage: action.kind.symbol)
            Text(action.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .swipeActions {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Preview

#Preview("Workflow Builder") {
    @Previewable @State var store = RemapStore()

    if let m = store.manipulators.first {
        WorkflowBuilderView(store: store, manipulator: m)
            .frame(width: 560, height: 800)
    }
}
