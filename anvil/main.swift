import SwiftUI
import Foundation

// MARK: - Single-instance guard
// Two copies of the app both watching/writing the same profile file clobber
// each other's edits (typing reverts, toggles snap back), so a GUI instance
// refuses to start while another GUI instance is running.

/// Handle to the lock file. Kept open for the lifetime of the process —
/// the lock is released automatically if the process crashes.
private var singleInstanceLockFD: Int32 = -1

@discardableResult
private func acquireSingleInstanceLock() -> Bool {
    let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0]
    let dirURL = URL(fileURLWithPath: appSupport).appendingPathComponent("Anvil", isDirectory: true)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let fd = open(dirURL.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return true } // fail open rather than refuse to start
    var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
    if fcntl(fd, F_SETLK, &lock) != 0 {
        close(fd)
        // Another GUI instance holds the lock — surface it instead of silently
        // starting a second copy that would fight over the profile file.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            others.first?.activate()
        }
        return false
    }
    singleInstanceLockFD = fd
    return true
}

if CommandLine.arguments.contains("--daemon") {
    AnvilDaemon.run()
} else if acquireSingleInstanceLock() {
    AnvilApp.main()
} else {
    exit(0)
}
