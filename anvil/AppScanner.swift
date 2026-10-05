import Foundation

struct InstalledApp: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let bundleID: String
    let url: URL

    /// Cached installed apps to avoid repeated filesystem enumeration.
    private static var cachedApps: [InstalledApp]?
    private static var cacheTime: Date = .distantPast
    private static let cacheTTL: TimeInterval = 60.0

    static func allInstalledApps() -> [InstalledApp] {
        let now = Date()
        if let cached = cachedApps, now.timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }

        let directories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Developer/Applications"),
        ]

        var apps: [InstalledApp] = []
        var seenBundleIDs = Set<String>()

        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                guard let bundle = Bundle(url: url) else { continue }
                guard let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { continue }
                guard seenBundleIDs.insert(bundleID).inserted else { continue }

                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                apps.append(InstalledApp(name: name, bundleID: bundleID, url: url))
            }
        }

        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedApps = sorted
        cacheTime = now
        return sorted
    }
}
