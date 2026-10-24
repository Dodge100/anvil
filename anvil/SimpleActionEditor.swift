import SwiftUI

// MARK: - Simple Action Parameters Editor

/// Editor for the parameters of a lightweight action (`MenuBarItemAction`).
/// Shared by menu bar items and command palette items so both stay in sync.
struct SimpleActionParametersEditor: View {
    @Binding var action: MenuBarItemAction
    /// Manipulators offered by the "Run Manipulator" action kind.
    var manipulators: [Manipulator] = []

    @ViewBuilder
    var body: some View {
        switch $action.wrappedValue.kind {
        case .none:
            EmptyView()
        case .runShortcut:
            TextField("Shortcut name", text: $action.shortcutName, prompt: Text("e.g. Open Browser"))
                .textFieldStyle(.roundedBorder)
        case .runShell:
            TextField("Command", text: $action.shellCommand, prompt: Text("e.g. echo hello"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        case .openApp:
            HStack(spacing: 8) {
                TextField("Bundle ID", text: $action.appBundleID, prompt: Text("com.apple.Safari"))
                    .textFieldStyle(.roundedBorder)
                TextField("App Name", text: $action.appName, prompt: Text("Safari"))
                    .textFieldStyle(.roundedBorder)
            }
        case .openURL:
            TextField("URL", text: $action.urlString, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
        case .sendKey:
            HStack(spacing: 8) {
                TextField("Key", text: $action.toKey, prompt: Text("a, space, return"))
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 2) {
                    ForEach(ModifierKey.flagBased, id: \.self) { mod in
                        Toggle(mod.symbol, isOn: Binding(
                            get: { $action.wrappedValue.toModifiers.contains(mod) },
                            set: {
                                if $0 { $action.wrappedValue.toModifiers.insert(mod) }
                                else { $action.wrappedValue.toModifiers.remove(mod) }
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        case .setVariable:
            HStack(spacing: 8) {
                TextField("Variable", text: $action.variableName, prompt: Text("myVar"))
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: $action.variableValue, prompt: Text("some value"))
                    .textFieldStyle(.roundedBorder)
            }
        case .toggleVariable:
            TextField("Variable", text: $action.variableName, prompt: Text("myVar"))
                .textFieldStyle(.roundedBorder)
        case .incrementVariable:
            HStack(spacing: 8) {
                TextField("Variable", text: $action.variableName, prompt: Text("counter"))
                    .textFieldStyle(.roundedBorder)
                TextField("Step", text: $action.variableValue, prompt: Text("1"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }
        case .setNotification:
            TextField("Message", text: $action.notificationMessage, prompt: Text("Hello from Anvil!"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        case .openFile:
            TextField("File path", text: $action.filePath, prompt: Text("~/Documents"))
                .textFieldStyle(.roundedBorder)
        case .runAppleScript:
            TextEditor(text: $action.scriptBody)
                .font(.caption.monospaced())
                .frame(minHeight: 60, maxHeight: 120)
                .border(.quaternary)
        case .runManipulator:
            Picker("Manipulator", selection: $action.manipulatorID) {
                Text("None").tag("")
                ForEach(manipulators) { manipulator in
                    Text(manipulator.name.isEmpty ? "Untitled" : manipulator.name)
                        .tag(manipulator.id.uuidString)
                }
            }
            .labelsHidden()
        }
    }
}
