import SwiftUI

struct KeyComboCaptureField: View {
    let isRecording: Bool
    let displayLabel: String
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if displayLabel.isEmpty {
                    Text("Not recorded")
                        .foregroundStyle(.secondary)
                } else {
                    Text(displayLabel)
                        .monospaced()
                }
                Spacer()
                Button(isRecording ? "Done" : "Record") {
                    if isRecording {
                        onStop()
                    } else {
                        onStart()
                    }
                }
            }
            if isRecording {
                Text("Press keys…  (Esc to cancel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct KeyPickerMenu: View {
    let label: String
    let onPick: (String) -> Void

    init(label: String = "Choose…", onPick: @escaping (String) -> Void) {
        self.label = label
        self.onPick = onPick
    }

    var body: some View {
        Menu(label) {
            let categories = Set(KeyLibrary.all.map { $0.category })
            let sortedCategories = categories.sorted { $0.displayOrder < $1.displayOrder }
            
            ForEach(sortedCategories, id: \.self) { category in
                Section(category.rawValue) {
                    let descriptors = KeyLibrary.all.filter { $0.category == category }
                    ForEach(descriptors) { descriptor in
                        Button(descriptor.label) {
                            onPick(descriptor.id)
                        }
                    }
                }
            }
        }
    }
}

struct ShortcutDisplayText: View {
    let shortcuts: [KeyShortcut]
    let emptyPlaceholder: String

    init(shortcuts: [KeyShortcut], emptyPlaceholder: String = "None recorded") {
        self.shortcuts = shortcuts
        self.emptyPlaceholder = emptyPlaceholder
    }

    var body: some View {
        if shortcuts.isEmpty {
            Text(emptyPlaceholder)
                .foregroundStyle(.secondary)
        } else {
            Text(shortcuts.map { $0.displayLabel }.joined(separator: " → "))
                .monospaced()
        }
    }
}