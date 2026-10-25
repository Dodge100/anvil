import SwiftUI
import AppKit

struct TagTokenField: NSViewRepresentable {
    @Binding var tags: [String] // ordered unique
    var completions: [String]
    var placeholder: String = ""

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.tokenStyle = .rounded
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        // Important for Form LabeledContent layout
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTokenField, context: Context) {
        // Only update if the token strings differ from the current binding
        // to avoid clobbering in-progress typing.
        let current = nsView.objectValue as? [String] ?? []
        if current.elementsEqual(tags) { return }
        // Never overwrite the field while the user is editing it — that would
        // wipe the text they are typing.
        guard nsView.window?.firstResponder !== nsView else { return }
        nsView.objectValue = tags
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTokenFieldDelegate, NSTextFieldDelegate {
        var parent: TagTokenField

        init(_ parent: TagTokenField) {
            self.parent = parent
        }

        // MARK: - NSTextFieldDelegate
        func controlTextDidChange(_ obj: Notification) {
            guard let tokenField = obj.object as? NSTokenField else { return }
            // Read the current tokens from the field
            let tokens = tokenField.objectValue as? [String] ?? []
            // Process: trim, drop empty, deduplicate while preserving order
            var seen = Set<String>()
            var processed: [String] = []
            for token in tokens {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if !seen.contains(trimmed) {
                    seen.insert(trimmed)
                    processed.append(trimmed)
                }
            }
            // Update the binding
            parent.tags = processed
        }

        // MARK: - NSTokenFieldDelegate
        func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: Int) -> [String] {
            let lowerSubstring = substring.lowercased()
            // Filter completions case-insensitively by substring, excluding already-present tags
            let present = Set(parent.tags)
            return parent.completions.filter { completion in
                !present.contains(completion) && completion.lowercased().hasPrefix(lowerSubstring)
            }
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String {
            representedObject as? String ?? ""
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String {
            representedObject as? String ?? ""
        }
    }
}