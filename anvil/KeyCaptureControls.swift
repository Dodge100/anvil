import SwiftUI

struct KeyComboCaptureField: View {
    let modifiers: Set<ModifierKey>
    let key: String
    let isCapturing: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button(action: { isCapturing ? onCancel() : onStart() }) {
            Text(displayLabel)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .tint(isCapturing ? .red : .accentColor)
    }

    private var displayLabel: String {
        if isCapturing { return "Press a combo…" }
        if key.isEmpty { return "Capture a combo" }
        return KeyShortcut(mandatoryModifiers: modifiers, key: key).displayLabel
    }
}

