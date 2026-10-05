import SwiftUI

// MARK: - Action Library Category

struct ActionCategory: Identifiable {
    let id = UUID()
    let name: String
    let actions: [ActionKind]

    init(_ name: String, _ actions: [ActionKind]) {
        self.name = name
        self.actions = actions
    }
}

// MARK: - All Categories

// MARK: - Condition Category

struct ConditionCategory: Identifiable {
    let id = UUID()
    let name: String
    let conditions: [ConditionKind]

    init(_ name: String, _ conditions: [ConditionKind]) {
        self.name = name
        self.conditions = conditions
    }
}

let conditionCategories: [ConditionCategory] = [
    ConditionCategory("App & Window", [
        .frontmostApp, .frontmostAppName, .runningCondition, .window
    ]),
    ConditionCategory("Input", [
        .inputSource, .device, .deviceExists, .keyboardType
    ]),
    ConditionCategory("Variables", [
        .variable, .globalVariable, .expression, .token
    ]),
    ConditionCategory("System", [
        .screen, .namedClipboard, .eventChanged, .pixelCondition
    ])
]

// MARK: - Action Library Panel

let actionCategories: [ActionCategory] = [
    ActionCategory("Input", [
        .sendKey, .sendText, .consumerKey, .pointingButton, .mouseKey,
        .stickyModifier, .holdDown, .disable, .fromEvent
    ]),
    ActionCategory("Variables", [
        .setVariable, .unsetVariable, .toggleVariable,
        .incrementVariable, .decrementVariable,
        .setGlobalVariable, .unsetGlobalVariable
    ]),
    ActionCategory("Applications", [
        .openApp, .activateApp, .hideApp, .unhideApp,
        .quitApp, .forceQuitApp, .activateLastApp
    ]),
    ActionCategory("Windows", [
        .windowAction
    ]),
    ActionCategory("System", [
        .lockScreen, .showDesktop, .missionControl, .toggleDarkMode,
        .setVolume, .muteSystem, .emptyTrash, .getBatteryState,
        .getIPAddress, .toggleHiddenFiles, .logOut, .restartSystem,
        .shutdownSystem
    ]),
    ActionCategory("Text", [
        .speakText, .transformText, .calculateExpression
    ]),
    ActionCategory("Clipboard", [
        .setClipboard, .getClipboard, .clearClipboard,
        .appendClipboard, .pasteClipboard, .getSelectedText
    ]),
    ActionCategory("Automation", [
        .runShell, .runShortcut, .runAppleScript, .executeNamedTrigger,
        .sendUserCommand, .selectInputSource
    ]),
    ActionCategory("Files & Web", [
        .openFile, .openFolder, .openURL, .httpRequest
    ]),
    ActionCategory("Feedback", [
        .setNotification, .playSound, .flashScreen
    ]),
    ActionCategory("Control", [
        .delay, .halt, .showPalette, .hidePalette
    ])
]

// MARK: - Action Library Panel

// MARK: - Action Category (for NavigationSplitView sidebar)

private enum ActionCategoryID: Hashable, CaseIterable {
    case mostUsed
    case input
    case variables
    case applications
    case windows
    case system
    case text
    case clipboard
    case automation
    case filesAndWeb
    case feedback
    case control

    var title: String {
        switch self {
        case .mostUsed: return "Most Used"
        case .input: return "Input"
        case .variables: return "Variables"
        case .applications: return "Applications"
        case .windows: return "Windows"
        case .system: return "System"
        case .text: return "Text"
        case .clipboard: return "Clipboard"
        case .automation: return "Automation"
        case .filesAndWeb: return "Files & Web"
        case .feedback: return "Feedback"
        case .control: return "Control"
        }
    }

    var icon: String {
        switch self {
        case .mostUsed: return "star.fill"
        case .input: return "keyboard"
        case .variables: return "number"
        case .applications: return "app"
        case .windows: return "macwindow"
        case .system: return "gearshape"
        case .text: return "textformat"
        case .clipboard: return "doc.on.clipboard"
        case .automation: return "gearshape.2"
        case .filesAndWeb: return "folder"
        case .feedback: return "bell"
        case .control: return "switch.2"
        }
    }

    var items: [ActionKind] {
        switch self {
        case .mostUsed: return Self._mostUsed
        case .input: return actionCategories[0].actions
        case .variables: return actionCategories[1].actions
        case .applications: return actionCategories[2].actions
        case .windows: return actionCategories[3].actions
        case .system: return actionCategories[4].actions
        case .text: return actionCategories[5].actions
        case .clipboard: return actionCategories[6].actions
        case .automation: return actionCategories[7].actions
        case .filesAndWeb: return actionCategories[8].actions
        case .feedback: return actionCategories[9].actions
        case .control: return actionCategories[10].actions
        }
    }

    private static let _mostUsed: [ActionKind] = [
        .sendKey, .sendText, .setVariable, .openApp, .activateApp,
        .runShell, .setNotification, .delay, .activateLastApp, .getClipboard
    ]
}

// MARK: - Action Library Browser (NavigationSplitView)

struct ActionLibraryBrowser: View {
    @Binding var isPresented: Bool
    let onSelect: (ActionKind) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: ActionCategoryID? = .mostUsed
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [(ActionCategoryID, [ActionKind])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return ActionCategoryID.allCases.filter { $0 != .mostUsed }.map { ($0, $0.items) }
        }
        return ActionCategoryID.allCases.filter { $0 != .mostUsed }.compactMap { cat in
            let matching = cat.items.filter { $0.rawValue.lowercased().contains(query) }
            guard !matching.isEmpty else { return nil }
            return (cat, matching)
        }
    }

    private var mostUsedFiltered: [ActionKind] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ActionCategoryID.mostUsed.items }
        return ActionCategoryID.mostUsed.items.filter { $0.rawValue.lowercased().contains(query) }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                // Category list
                List(selection: $selectedCategory) {
                    if searchText.isEmpty {
                        Section {
                            ForEach([ActionCategoryID.mostUsed], id: \.self) { category in
                                categoryRow(category)
                            }
                        }
                    }

                    Section("Categories") {
                        ForEach(ActionCategoryID.allCases.filter { $0 != .mostUsed }, id: \.self) { category in
                            categoryRow(category)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Actions")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 480)
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ category: ActionCategoryID) -> some View {
        Label {
            Text(category.title)
        } icon: {
            Image(systemName: category.icon)
                .foregroundStyle(category == .mostUsed ? .yellow : .secondary)
        }
        .tag(category)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if !searchText.isEmpty {
            itemList(items: mostUsedFiltered, title: nil)
        } else if let category = selectedCategory {
            itemList(items: category.items, title: category.title)
        } else {
            ContentUnavailableView(
                "Select a Category",
                systemImage: "sidebar.left",
                description: Text("Choose a category from the sidebar.")
            )
        }
    }

    // MARK: - Item List

    private func itemList(items: [ActionKind], title: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, searchText.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            List {
                ForEach(items, id: \.self) { kind in
                    Button {
                        onSelect(kind)
                        withAnimation { isPresented = false }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(kind.rawValue)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(kind)
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Condition Category (for NavigationSplitView sidebar)

private enum ConditionCategoryID: Hashable, CaseIterable {
    case mostUsed
    case appAndWindow
    case input
    case variables
    case system

    var title: String {
        switch self {
        case .mostUsed: return "Most Used"
        case .appAndWindow: return "App & Window"
        case .input: return "Input"
        case .variables: return "Variables"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .mostUsed: return "star.fill"
        case .appAndWindow: return "app"
        case .input: return "keyboard"
        case .variables: return "number"
        case .system: return "gearshape"
        }
    }

    var items: [ConditionKind] {
        switch self {
        case .mostUsed: return Self._mostUsed
        case .appAndWindow: return conditionCategories[0].conditions
        case .input: return conditionCategories[1].conditions
        case .variables: return conditionCategories[2].conditions
        case .system: return conditionCategories[3].conditions
        }
    }

    private static let _mostUsed: [ConditionKind] = [
        .frontmostApp, .inputSource, .variable, .deviceExists,
        .runningCondition, .window, .globalVariable
    ]
}

// MARK: - Condition Library Browser (NavigationSplitView)

struct ConditionLibraryBrowser: View {
    @Binding var isPresented: Bool
    let onSelect: (ConditionKind) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: ConditionCategoryID? = .mostUsed
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [(ConditionCategoryID, [ConditionKind])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return ConditionCategoryID.allCases.filter { $0 != .mostUsed }.map { ($0, $0.items) }
        }
        return ConditionCategoryID.allCases.filter { $0 != .mostUsed }.compactMap { cat in
            let matching = cat.items.filter { $0.rawValue.lowercased().contains(query) }
            guard !matching.isEmpty else { return nil }
            return (cat, matching)
        }
    }

    private var mostUsedFiltered: [ConditionKind] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ConditionCategoryID.mostUsed.items }
        return ConditionCategoryID.mostUsed.items.filter { $0.rawValue.lowercased().contains(query) }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                // Category list
                List(selection: $selectedCategory) {
                    if searchText.isEmpty {
                        Section {
                            ForEach([ConditionCategoryID.mostUsed], id: \.self) { category in
                                categoryRow(category)
                            }
                        }
                    }

                    Section("Categories") {
                        ForEach(ConditionCategoryID.allCases.filter { $0 != .mostUsed }, id: \.self) { category in
                            categoryRow(category)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Conditions")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 480)
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ category: ConditionCategoryID) -> some View {
        Label {
            Text(category.title)
        } icon: {
            Image(systemName: category.icon)
                .foregroundStyle(category == .mostUsed ? .yellow : .secondary)
        }
        .tag(category)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if !searchText.isEmpty {
            itemList(items: mostUsedFiltered, title: nil)
        } else if let category = selectedCategory {
            itemList(items: category.items, title: category.title)
        } else {
            ContentUnavailableView(
                "Select a Category",
                systemImage: "sidebar.left",
                description: Text("Choose a category from the sidebar.")
            )
        }
    }

    // MARK: - Item List

    private func itemList(items: [ConditionKind], title: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, searchText.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            List {
                ForEach(items, id: \.self) { kind in
                    Button {
                        onSelect(kind)
                        withAnimation { isPresented = false }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(kind.rawValue)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(kind)
                }
            }
            .listStyle(.inset)
        }
    }
}
