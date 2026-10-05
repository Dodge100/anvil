import Foundation

struct DaemonManager {
    static let label = "com.anvil.daemon"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    static func install() -> Bool {
        guard let executableURL = Bundle.main.executableURL else { return false }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path, "--daemon"],
            "KeepAlive": true,
            "RunAtLoad": true,
            "ThrottleInterval": 5
        ]

        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return false }
        try? data.write(to: plistURL)

        // First unload any existing daemon to prevent stale instances from
        // accumulating when the binary path changes (e.g. across dev builds).
        let unloadTask = Process()
        unloadTask.launchPath = "/bin/launchctl"
        unloadTask.arguments = ["unload", plistURL.path]
        try? unloadTask.run()
        unloadTask.waitUntilExit()

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistURL.path]
        try? task.run()
        task.waitUntilExit()

        return task.terminationStatus == 0
    }

    @discardableResult
    static func uninstall() -> Bool {
        guard isInstalled else { return true }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistURL.path]
        try? task.run()
        task.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)

        return task.terminationStatus == 0
    }

    static var isRunning: Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains(label)
    }

    static func installIfNeeded() {
        // Never auto-install the daemon when running from Xcode's build directory.
        // During development the binary path changes every build, which would cause
        // the daemon to be reinstalled on every launch — spawning stale instances.
        guard let currentPath = Bundle.main.executableURL?.path else { return }
        if currentPath.contains("/DerivedData/") || currentPath.contains("/XCBuildData/") || currentPath.contains("/tmp/") {
            return
        }

        let defaults = UserDefaults.standard
        let lastPath = defaults.string(forKey: "daemonExecutablePath")
        guard lastPath != currentPath || !isInstalled else { return }
        if install() {
            defaults.set(currentPath, forKey: "daemonExecutablePath")
        }
    }
}
