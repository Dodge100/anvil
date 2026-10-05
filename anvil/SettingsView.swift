import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: RemapStore

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ConfigProfileManagerView(store: store)
                .tabItem {
                    Label("Profiles", systemImage: "square.on.square")
                }
        }
                .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @ObservedObject var store: RemapStore
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { DaemonManager.isInstalled },
                    set: { newValue in
                        if newValue {
                            DaemonManager.install()
                        } else {
                            DaemonManager.uninstall()
                        }
                    }
                ))
                Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { newValue in
                        if newValue {
                            StatusBarController.shared.rebuildAll()
                        } else {
                            StatusBarController.shared.removeAll()
                        }
                    }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
