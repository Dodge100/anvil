import SwiftUI
import UniformTypeIdentifiers

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

enum AppMode: String, CaseIterable, Identifiable {
    case remaps = "Remaps"
    case menuBar = "Menu Bar"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .remaps: return "keyboard"
        case .menuBar: return "menubar.rectangle"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var store: RemapStore
    @State private var selectedMode: AppMode = .remaps

    var body: some View {
        VStack(spacing: 0) {
            switch selectedMode {
            case .remaps:
                RemapView(store: store)
            case .menuBar:
                MenuBarItemsView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let toast = store.toastMessage {
                ToastView(message: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.toastMessage)
        .onDrop(of: [.fileURL], delegate: ManipulatorDropDelegate(store: store))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(AppMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between remap editor and menu bar items")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView(store: RemapStore())
}
