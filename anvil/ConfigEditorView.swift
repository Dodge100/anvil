import SwiftUI

// MARK: - JSON Code Editor

/// A direct config.json editor within the app.
/// Provides raw JSON editing, syntax validation, formatting, and save.
struct ConfigEditorView: View {
    @ObservedObject var store: RemapStore
    @Environment(\.dismiss) private var dismiss

    @State private var editorText: String = ""
    @State private var originalText: String = ""
    @State private var validationError: String?
    @State private var lastSaved: Date?
    @State private var showReplaceConfirmation = false
    @State private var pendingExternalReload = false
    @State private var externalPollTimer: Timer?

    var isDirty: Bool { editorText != originalText }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Text("config.json")
                    .font(.headline)
                Spacer()

                // Reload from disk
                Button {
                    loadConfig()
                } label: {
                    Text("Reload")
                }
                .help("Reload config.json from disk (discards unsaved changes)")

                // Format JSON
                Button {
                    formatJSON()
                } label: {
                    Text("Format")
                }
                .help("Pretty-print JSON")

                Divider()
                    .frame(height: 20)

                // Save
                Button {
                    saveConfig()
                } label: {
                    Text("Save")
                }
                .disabled(!isDirty && validationError == nil)

                // Close
                Button {
                    if isDirty {
                        showReplaceConfirmation = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("Done")
                }
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // ── Editor ───────────────────────────────────────────────
            JSONEditorTextView(text: $editorText, validationError: $validationError)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Status Bar ───────────────────────────────────────────
            HStack(spacing: 8) {
                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if isDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let saved = lastSaved {
                    Text("Saved \(saved.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loaded from disk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(editorText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))
        }
        .frame(minWidth: 640, minHeight: 400)
        .onAppear {
            loadConfig()
            startPolling()
        }
        .onDisappear {
            externalPollTimer?.invalidate()
            externalPollTimer = nil
        }
        .alert("Discard changes?", isPresented: $showReplaceConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes to config.json.")
        }
        .alert("External Changes Detected", isPresented: $pendingExternalReload) {
            Button("Reload") {
                loadConfig()
            }
            Button("Keep My Changes", role: .cancel) {
                pendingExternalReload = false
            }
        } message: {
            Text("config.json was modified outside the editor. Reload to see the latest content?")
        }
    }

    // MARK: - Load

    private func loadConfig() {
        do {
            let data = try Data(contentsOf: RemapStore.configURL)
            // Pretty-print on load so the user sees a clean starting point
            if let object = try JSONSerialization.jsonObject(with: data) as? NSObject {
                let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                editorText = String(decoding: pretty, as: UTF8.self)
            } else {
                editorText = String(decoding: data, as: UTF8.self)
            }
            originalText = editorText
            validationError = nil
        } catch {
            // If the file doesn't exist yet, seed with an empty array
            if (error as? CocoaError)?.code == .fileReadNoSuchFile {
                editorText = "[]"
                originalText = editorText
                validationError = nil
            } else {
                validationError = "Failed to load: \(error.localizedDescription)"
                editorText = ""
                originalText = ""
            }
        }
    }

    // MARK: - Format

    private func formatJSON() {
        guard let data = editorText.data(using: .utf8) else {
            validationError = "Cannot encode text as UTF-8"
            return
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            editorText = String(decoding: pretty, as: UTF8.self)
            validationError = nil
        } catch {
            validationError = "Format failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Save

    private func saveConfig() {
        // Validate first
        guard let data = editorText.data(using: .utf8) else {
            validationError = "Cannot encode text as UTF-8"
            return
        }
        if let error = Self.validate(editorText) {
            validationError = error
            return
        }

        // Write to a temp file first, then atomically replace
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("config_\(UUID().uuidString).json")
        do {
            try data.write(to: tmpURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(RemapStore.configURL, withItemAt: tmpURL)
            originalText = editorText
            lastSaved = Date()
            validationError = nil

            // The config polling timer in RemapStore will detect the change
            // and reload manipulators automatically.
        } catch {
            validationError = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Polling

    fileprivate static func validate(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else {
            return "Cannot encode text as UTF-8"
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return nil
        } catch {
            return "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        // Check every 2 seconds if the file was modified externally (by daemon, another app, etc.)
        var lastMod: Date?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: RemapStore.configURL.path),
           let mod = attrs[.modificationDate] as? Date {
            lastMod = mod
        }

        externalPollTimer?.invalidate()
        let configPath = RemapStore.configURL.path
        externalPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: configPath),
                  let mod = attrs[.modificationDate] as? Date,
                  mod != lastMod else { return }
            lastMod = mod

            DispatchQueue.main.async {
                // Only notify if the user hasn't made local changes
                if !self.isDirty {
                    self.loadConfig()
                } else {
                    // Flag that external changes exist; user can choose to reload
                    self.pendingExternalReload = true
                }
            }
        }
    }
}

// MARK: - NSTextView Bridge (Code Editor)

/// A minimal SwiftUI wrapper around NSTextView for monospaced code editing
/// with JSON-aware features.
struct JSONEditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var validationError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.usesFontPanel = false
        textView.usesRuler = false

        // Word wrap: off by default for code; toggle with Cmd+Shift+W
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.enabledTextCheckingTypes = 0

        scrollView.documentView = textView

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text, !context.coordinator.isEditing {
            textView.string = text
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONEditorTextView
        weak var textView: NSTextView?
        var isEditing = false
        private var changeTimer: Timer?

        init(_ parent: JSONEditorTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isEditing = true
            parent.text = textView.string

            // Debounce validation (validate 300ms after last keystroke)
            changeTimer?.invalidate()
            changeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.parent.validationError = ConfigEditorView.validate(textView.string)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            changeTimer?.invalidate()
            changeTimer = nil
        }
    }
}

// MARK: - Toolbar Integration

/// Button that can be placed in a toolbar to open the JSON code editor.
struct ConfigEditorButton: View {
    @ObservedObject var store: RemapStore
    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor = true
        } label: {
            Text("Edit config.json")
        }
        .sheet(isPresented: $showEditor) {
            ConfigEditorView(store: store)
        }
    }
}
