import AppKit

struct AnvilDaemon {
    static func run() {
        // NSApp is nil until the shared NSApplication is explicitly initialized.
        // The daemon bypasses SwiftUI's app lifecycle (no AnvilApp.main()), so
        // we must create it here before touching NSApp / NSApplication.shared.
        NSApplication.shared.setActivationPolicy(.prohibited)

        let store = RemapStore(daemonMode: true)
        store.startConfigPolling()
        store.writeDaemonStatus()

        // Keep the process alive indefinitely.
        // The kqueue config-polling source (startConfigPolling) needs the current
        // RunLoop to be running — RunLoop.current.run() achieves that without
        // pulling in the full NSApplication event loop.
        RunLoop.current.run()
    }
}
