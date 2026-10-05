import SwiftUI
import UniformTypeIdentifiers

// MARK: - Visual Workflow Builder

/// A drag-and-drop visual flow builder that renders a manipulator's trigger,
/// conditions, and actions as connected, reorderable nodes on a canvas.
struct WorkflowBuilderView: View {
    @ObservedObject var store: RemapStore
    let manipulator: Manipulator

    @State private var draggedItemID: String?

    private var mid: UUID { manipulator.id }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                // ── Header badge ──
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                    Text("Flow View")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 16)

                // ── Trigger ──
                WorkflowTriggerNode(trigger: manipulator.trigger)
                    .padding(.bottom, 12)

                // ── Conditions ──
                if !manipulator.conditions.isEmpty || manipulator.actions.isEmpty {
                    // Show the section even when empty so user can add
                    HStack(spacing: 8) {
                        WorkflowArrow()
                        sectionLabel("When all conditions match")
                    }
                    .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(zip(manipulator.conditions.indices, manipulator.conditions)), id: \.1.id) { idx, condition in
                            WorkflowConditionNode(
                                condition: condition,
                                manipulatorID: mid,
                                store: store
                            )
                            .onDrag {
                                draggedItemID = "condition:\(condition.id)"
                                return NSItemProvider(object: condition.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: WorkflowDropDelegate(
                                    targetID: condition.id,
                                    targetKind: .condition,
                                    manipulatorID: mid,
                                    store: store,
                                    draggedItemID: $draggedItemID
                                )
                            )
                            .transition(.opacity.combined(with: .slide))

                            if idx < manipulator.conditions.count - 1 {
                                WorkflowArrow()
                            }
                        }
                    }
                }

                // ── Add condition button ──
                WorkflowAddButton(
                    label: "Add Condition",
                    icon: "plus.rhombus",
                    action: { store.addCondition(to: mid) }
                )
                .padding(.vertical, 8)

                // ── Actions ──
                WorkflowArrow()
                    .padding(.bottom, 4)

                HStack(spacing: 8) {
                    WorkflowArrow()
                    sectionLabel("Then execute in order")
                }
                .padding(.bottom, 8)

                if !manipulator.actions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(zip(manipulator.actions.indices, manipulator.actions)), id: \.1.id) { idx, action in
                            WorkflowActionNode(
                                action: action,
                                manipulatorID: mid,
                                store: store
                            )
                            .onDrag {
                                draggedItemID = "action:\(action.id)"
                                return NSItemProvider(object: action.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: WorkflowDropDelegate(
                                    targetID: action.id,
                                    targetKind: .action,
                                    manipulatorID: mid,
                                    store: store,
                                    draggedItemID: $draggedItemID
                                )
                            )
                            .transition(.opacity.combined(with: .slide))

                            if idx < manipulator.actions.count - 1 {
                                WorkflowArrow()
                            }
                        }
                    }
                }

                // ── Add action button ──
                WorkflowAddButton(
                    label: "Add Action",
                    icon: "plus",
                    action: { store.addActionTo(mid) }
                )
                .padding(.vertical, 8)

                Spacer().frame(height: 40)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Drag-and-drop kind

private enum DropKind {
    case condition
    case action
}

// MARK: - Drop Delegate

private struct WorkflowDropDelegate: DropDelegate {
    let targetID: UUID
    let targetKind: DropKind
    let manipulatorID: UUID
    let store: RemapStore
    @Binding var draggedItemID: String?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedItemID = nil }
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, error in
            guard let data = data as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let sourceUUID = UUID(uuidString: uuidString)
            else { return }

            DispatchQueue.main.async {
                let m = store.manipulators.first(where: { $0.id == manipulatorID })
                switch targetKind {
                case .condition:
                    guard let from = m?.conditions.firstIndex(where: { $0.id == sourceUUID }),
                          let to = m?.conditions.firstIndex(where: { $0.id == targetID }),
                          from != to
                    else { return }
                    let adjusted = to > from ? to + 1 : to
                    store.moveCondition(from: IndexSet(integer: from), to: adjusted, in: manipulatorID)
                case .action:
                    guard let from = m?.actions.firstIndex(where: { $0.id == sourceUUID }),
                          let to = m?.actions.firstIndex(where: { $0.id == targetID }),
                          from != to
                    else { return }
                    let adjusted = to > from ? to + 1 : to
                    store.moveAction(from: IndexSet(integer: from), to: adjusted, in: manipulatorID)
                }
            }
        }
        return true
    }
}

// MARK: - Trigger Node

private struct WorkflowTriggerNode: View {
    let trigger: ManipulatorTrigger

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: trigger.keyType.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.displayLabel)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                Text(trigger.keyType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !trigger.triggerName.isEmpty {
                Text(trigger.triggerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(10)
    }
}

// MARK: - Condition Node

private struct WorkflowConditionNode: View {
    let condition: Condition
    let manipulatorID: UUID
    let store: RemapStore

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: condition.kind.symbol)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(condition.kind.rawValue)
                    .font(.subheadline.weight(.medium))
                Text(displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Quick-op actions: delete
            HStack(spacing: 4) {
                if isHovered {
                    Button {
                        store.removeCondition(condition.id, from: manipulatorID)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Image(systemName: "line.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .onHover { isHovered = $0 }
        .cursor(.openHand)
        .padding(.horizontal, 4)
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8))
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

// MARK: - Action Node

private struct WorkflowActionNode: View {
    let action: Action
    let manipulatorID: UUID
    let store: RemapStore

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.kind.symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.kind.rawValue)
                    .font(.subheadline.weight(.medium))
                Text(action.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Fire mode badge
            if action.fireMode != .onKeyDown {
                Text(action.fireMode.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            // Quick-op buttons
            HStack(spacing: 4) {
                if isHovered {
                    Button {
                        store.removeAction(action.id, from: manipulatorID)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Image(systemName: "line.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .onHover { isHovered = $0 }
        .cursor(.openHand)
        .padding(.horizontal, 4)
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch action.kind {
        case .halt, .disable: return .red
        case .delay: return .orange
        case .setVariable, .unsetVariable, .toggleVariable, .setGlobalVariable, .unsetGlobalVariable: return .teal
        case .runShell, .runAppleScript, .sendUserCommand, .runShortcut: return .purple
        case .sendKey, .consumerKey, .pointingButton, .mouseKey, .holdDown, .stickyModifier: return .blue
        case .sendText: return .cyan
        case .openApp, .openURL: return .green
        case .softwareFunction: return .brown
        case .selectInputSource: return .mint
        case .setNotification: return .yellow
        case .fromEvent: return .gray
        case .executeNamedTrigger, .showPalette, .hidePalette: return .pink
        case .getSelectedText: return .cyan
        case .setClipboard, .getClipboard, .clearClipboard: return .orange
        case .activateApp, .hideApp, .unhideApp, .quitApp, .forceQuitApp, .activateLastApp: return .green
        case .windowAction: return .indigo
        case .lockScreen, .showDesktop, .missionControl, .toggleDarkMode, .setVolume,
             .muteSystem, .emptyTrash, .getBatteryState, .getIPAddress, .toggleHiddenFiles,
             .logOut, .restartSystem, .shutdownSystem: return .brown
        case .speakText, .transformText, .calculateExpression: return .cyan
        case .incrementVariable, .decrementVariable: return .teal
        case .appendClipboard, .pasteClipboard: return .orange
        case .httpRequest, .openFile, .openFolder: return .green
        case .playSound, .flashScreen: return .yellow
        }
    }
}

// MARK: - Arrow

private struct WorkflowArrow: View {
    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Add button

private struct WorkflowAddButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Add a new \(label.lowercased())")
    }
}

// MARK: - Cursor modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
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
