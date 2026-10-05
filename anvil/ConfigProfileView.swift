import SwiftUI

// MARK: - Profile Manager View

/// Profile management view usable in Settings or as a sheet.
struct ConfigProfileManagerView: View {
    @ObservedObject var store: RemapStore
    @Environment(\.dismiss) private var dismiss

    @State private var showRenameAlert = false
    @State private var renameTarget: ConfigProfile?
    @State private var renameText = ""
    @State private var showDeleteAlert = false
    @State private var deleteTarget: ConfigProfile?
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack {
                Text("Profiles")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if store.profiles.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Profiles", systemImage: "square.on.square")
                } description: {
                    Text("Create a profile to get started.")
                } actions: {
                    Button("Create Default Profile") {
                        let profile = ConfigProfile.default()
                        store.profiles.append(profile)
                        store.activeProfileID = profile.id
                        store.manipulators = []
                        store.menuBarItems = MenuBarItem.defaults()
                        store.saveProfilesManifest()
                        store.saveConfig()
                        store.applyRemaps()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                profileList
            }

            // ── Footer ──
            HStack(spacing: 8) {
                Button {
                    createProfile()
                } label: {
                    Text("New Profile")
                }
                .controlSize(.small)

                Button {
                    guard let active = store.activeProfile else { return }
                    store.duplicateProfile(active.id)
                } label: {
                    Text("Duplicate Active")
                }
                .controlSize(.small)
                .disabled(store.activeProfile == nil)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.3))
        }
        .frame(minWidth: 400, minHeight: 320)
        .alert("Rename Profile", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameProfile(target.id, name: renameText.trimmingCharacters(in: .whitespaces))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this profile.")
        }
        .alert("Delete Profile?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    do {
                        try store.deleteProfile(target.id)
                    } catch let error as ProfileError {
                        deleteError = error.localizedDescription
                    } catch {}
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let target = deleteTarget {
                Text("Delete \"\(target.name)\"? This cannot be undone.")
            }
        }
        .alert("Cannot Delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Profile List

    private var profileList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        isActive: profile.id == store.activeProfileID,
                        onSwitch: { store.switchProfile(to: profile.id) },
                        onRename: {
                            renameTarget = profile
                            renameText = profile.name
                            showRenameAlert = true
                        },
                        onDuplicate: { store.duplicateProfile(profile.id) },
                        onDelete: {
                            deleteTarget = profile
                            showDeleteAlert = true
                        },
                        onChangeIcon: { icon in
                            store.updateProfileIcon(profile.id, icon: icon)
                        },
                        onChangeColor: { colorName in
                            store.updateProfileColor(profile.id, colorName: colorName)
                        }
                    )
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
    }

    // MARK: - Create Profile

    private func createProfile() {
        let baseName = "Profile \(store.profiles.count + 1)"
        store.createProfile(name: baseName, icon: "person")
    }
}

// MARK: - Profile Card

private struct ProfileCard: View {
    let profile: ConfigProfile
    let isActive: Bool
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onChangeIcon: (String) -> Void
    let onChangeColor: (String) -> Void

    @State private var showIconPicker = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon with popover picker
            Button {
                showIconPicker.toggle()
            } label: {
                Image(systemName: profile.icon)
                    .font(.body)
                    .foregroundStyle(isActive ? .white : profile.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        isActive ? profile.accentColor : profile.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showIconPicker, arrowEdge: .trailing) {
                iconAndColorPickerPopover
            }

            // Name
            Text(profile.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            // Active badge or switch button
            if isActive {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("Active")
                        .font(.caption)
                }
                .foregroundStyle(profile.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(profile.accentColor.opacity(0.1), in: Capsule())
            } else {
                Button("Switch") {
                    onSwitch()
                }
                .controlSize(.small)
            }

            // Context menu
            Menu {
                Button("Rename") { onRename() }
                Button("Duplicate") { onDuplicate() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
                    .disabled(profile.name == "Default")
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? profile.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isActive ? 1.5 : 1)
        )
    }

    // MARK: - Icon Picker Popover

    private var iconAndColorPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(ConfigProfile.availableIcons, id: \.self) { icon in
                    Button {
                        onChangeIcon(icon)
                        showIconPicker = false
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(profile.icon == icon ? profile.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(icon)
                }
            }

            Divider()

            Text("Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(ConfigProfile.availableColors, id: \.name) { item in
                    Button {
                        onChangeColor(item.name)
                        showIconPicker = false
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().strokeBorder(
                                    profile.colorName == item.name ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
    }
}

// MARK: - Toolbar Profile Switcher

/// Compact profile switcher for the toolbar. Shows the active profile's icon and name,
/// with a native dropdown menu to switch or manage profiles.
struct ProfileSwitcherButton: View {
    @ObservedObject var store: RemapStore
    @State private var showManager = false

    var body: some View {
        Menu {
            if store.profiles.isEmpty {
                Button("No Profiles") { }
                    .disabled(true)
            } else {
                ForEach(store.profiles) { profile in
                    let isActive = profile.id == store.activeProfileID
                    Button {
                        store.switchProfile(to: profile.id)
                    } label: {
                        HStack {
                            Image(systemName: profile.icon)
                                .foregroundStyle(isActive ? .white : profile.accentColor)
                                .frame(width: 22, height: 22)
                                .background(
                                    isActive ? profile.accentColor : profile.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                            Text(profile.name)
                            if isActive {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Manage Profiles\u{2026}") {
                showManager = true
            }
        } label: {
            if let active = store.activeProfile {
                HStack(spacing: 4) {
                    Image(systemName: active.icon)
                        .foregroundStyle(active.accentColor)
                    Text(active.name)
                }
            } else {
                Image(systemName: "person.circle")
            }
        }
        .help("Switch or manage config profiles")
        .sheet(isPresented: $showManager) {
            ConfigProfileManagerView(store: store)
        }
    }
}
