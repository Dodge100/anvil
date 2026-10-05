import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType

extension UTType {
    /// The anvil manipulator file format: a single `Manipulator` encoded as JSON.
    static var anvilManipulator: UTType {
        UTType(exportedAs: "com.anvil.manipulator", conformingTo: .json)
    }

    /// The anvil menu bar item file format: a single `MenuBarItem` encoded as JSON.
    static var anvilMenuBarItem: UTType {
        UTType(exportedAs: "com.anvil.menubaritem", conformingTo: .json)
    }
}

// MARK: - File I/O

enum ManipulatorFile {
    /// The file extension for exported manipulator files (no leading dot).
    static let fileExtension = "anvilmanipulator"

    // MARK: Export

    /// Encode a manipulator as JSON data.
    static func encode(_ manipulator: Manipulator) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manipulator)
    }

    /// Write a single manipulator to a file URL.
    static func write(_ manipulator: Manipulator, to url: URL) throws {
        try encode(manipulator).write(to: url)
    }

    /// Show a save panel and export the given manipulator.
    /// - Returns: `true` if the file was written successfully.
    @MainActor
    @discardableResult
    static func export(_ manipulator: Manipulator) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Manipulator"
        panel.nameFieldStringValue = sanitizedFilename(for: manipulator.name)
        panel.allowedContentTypes = [.anvilManipulator]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try write(manipulator, to: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    // MARK: Import

    /// Decode a manipulator from JSON data.
    static func decode(_ data: Data) throws -> Manipulator {
        try JSONDecoder().decode(Manipulator.self, from: data)
    }

    /// Read and decode a manipulator from a file URL.
    static func read(from url: URL) throws -> Manipulator {
        try decode(Data(contentsOf: url))
    }

    /// Show an open panel and return the selected manipulator.
    @MainActor
    static func importSingle() -> Manipulator? {
        let panel = NSOpenPanel()
        panel.title = "Import Manipulator"
        panel.allowedContentTypes = [.anvilManipulator]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            return try read(from: url)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    // MARK: Helpers

    /// Derive a safe file name from the manipulator name.
    private static func sanitizedFilename(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(.punctuationCharacters)
        let safe = name.unicodeScalars.filter { allowed.contains($0) }.map(Character.init)
        let trimmed = String(safe).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        return "\(base).\(fileExtension)"
    }
}

// MARK: - Menu Bar Item File I/O

enum MenuBarItemFile {
    /// The file extension for exported menu bar item files (no leading dot).
    static let fileExtension = "anvilmenubaritem"

    // MARK: Export

    /// Encode a menu bar item as JSON data.
    static func encode(_ item: MenuBarItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(item)
    }

    /// Write a single menu bar item to a file URL.
    static func write(_ item: MenuBarItem, to url: URL) throws {
        try encode(item).write(to: url)
    }

    /// Show a save panel and export the given menu bar item.
    /// - Returns: `true` if the file was written successfully.
    @MainActor
    @discardableResult
    static func export(_ item: MenuBarItem) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Menu Bar Item"
        panel.nameFieldStringValue = sanitizedFilename(for: item.name)
        panel.allowedContentTypes = [.anvilMenuBarItem]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try write(item, to: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    // MARK: Import

    /// Decode a menu bar item from JSON data.
    static func decode(_ data: Data) throws -> MenuBarItem {
        try JSONDecoder().decode(MenuBarItem.self, from: data)
    }

    /// Read and decode a menu bar item from a file URL.
    static func read(from url: URL) throws -> MenuBarItem {
        try decode(Data(contentsOf: url))
    }

    /// Show an open panel and return the selected menu bar item.
    @MainActor
    static func importSingle() -> MenuBarItem? {
        let panel = NSOpenPanel()
        panel.title = "Import Menu Bar Item"
        panel.allowedContentTypes = [.anvilMenuBarItem]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            return try read(from: url)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    // MARK: Helpers

    /// Derive a safe file name from the menu bar item name.
    private static func sanitizedFilename(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(.punctuationCharacters)
        let safe = name.unicodeScalars.filter { allowed.contains($0) }.map(Character.init)
        let trimmed = String(safe).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        return "\(base).\(fileExtension)"
    }
}

// MARK: - Drag-and-Drop support

/// A drop delegate that imports `.anvilmanipulator` files into the store.
struct ManipulatorDropDelegate: DropDelegate {
    let store: RemapStore

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.fileURL]).first else { return false }

        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data,
                  let urlData = data as? Data,
                  let urlString = String(data: urlData, encoding: .utf8),
                  let url = URL(string: urlString)
            else { return }

            let ext = url.pathExtension.lowercased()
            guard ext == ManipulatorFile.fileExtension || ext == "json" else { return }

            Task { @MainActor in
                store.importManipulator(from: url)
            }
        }
        return true
    }
}
