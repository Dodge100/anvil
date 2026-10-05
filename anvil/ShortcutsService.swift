import AppKit

struct ShortcutInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

enum ShortcutsService {
    private static let bundleIDs = ["com.apple.shortcuts", "is.workflow.my.shortcuts"]

    static func runShortcut(named name: String) -> Bool {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        guard let bundleID = resolveBundleID() else { return false }
        let source = """
        tell application id "\(bundleID)"
            try
                run shortcut "\(escaped)"
            on error errMsg number errNum
                return "Error " & errNum & ": " & errMsg
            end try
        end tell
        """
        let result = runAppleScript(source)
        return !result.lowercased().contains("error")
    }

    static func availableShortcuts() -> [ShortcutInfo] {
        guard let bundleID = resolveBundleID() else { return [] }
        let source = """
        tell application id "\(bundleID)"
            try
                set shortcutList to name of every shortcut
                return shortcutList
            on error errMsg number errNum
                return errMsg
            end try
        end tell
        """
        let output = runAppleScript(source)
        guard !output.lowercased().contains("error") else { return [] }
        return parseShortcutNames(output)
    }

    private static func resolveBundleID() -> String? {
        for id in bundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
                return id
            }
        }
        return nil
    }

    private static func runAppleScript(_ source: String) -> String {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", source]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return "Error: \(error.localizedDescription)" }
        task.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        if !data.isEmpty {
            return String(data: data, encoding: .utf8) ?? ""
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: errData, encoding: .utf8) ?? ""
    }

    private static func parseShortcutNames(_ output: String) -> [ShortcutInfo] {
        let lines = output
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.map { ShortcutInfo(id: $0, name: $0) }
    }
}
