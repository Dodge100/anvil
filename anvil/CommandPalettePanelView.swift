import SwiftUI
import UniformTypeIdentifiers

// MARK: - Command Palette Panel

/// Hosts the presentation for the active command palette, switching on its style.
struct CommandPalettePanelView: View {
    @ObservedObject var controller: CommandPaletteController

    var body: some View {
        if let style = controller.activePalette?.style {
            switch style {
            case .spotlight:
                SpotlightPaletteView(controller: controller)
            case .shelf:
                ShelfPaletteView(controller: controller)
            case .circular:
                CircularPaletteView(controller: controller)
            case .grid:
                GridPaletteView(controller: controller)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Shared pieces

/// Plain Spotlight-like search input backed by AppKit. SwiftUI's FocusState
/// failed to install a field editor inside the borderless palette panel, so the
/// controller pushes focus to this real NSTextField after the panel becomes key.
struct PaletteSearchField: NSViewRepresentable {
    @ObservedObject var controller: CommandPaletteController
    var fontSize: CGFloat

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let controller: CommandPaletteController
        /// The searchFocusTick the field last honored (re-focus on change).
        var honoredTick: Int = -1

        init(controller: CommandPaletteController) {
            self.controller = controller
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            controller.query = field.stringValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .labelColor
        field.placeholderString = "Spotlight Search"
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Mirror the controller's query without fighting the user's typing.
        if field.stringValue != controller.query {
            field.stringValue = controller.query
        }
        // A new searchFocusTick means the palette window just became key: make
        // the field its window's first responder so typing lands immediately.
        let tick = controller.searchFocusTick
        if context.coordinator.honoredTick != tick {
            context.coordinator.honoredTick = tick
            if let window = field.window {
                DispatchQueue.main.async {
                    window.makeFirstResponder(field)
                }
            }
        }
    }
}

/// Short verb describing an action, shown as the "run" hint like Spotlight does.
private func actionVerb(for kind: MenuBarActionKind) -> String? {
    switch kind {
    case .none, .showMenu: return nil
    case .runShortcut, .runShell, .runAppleScript, .runManipulator: return "Run"
    case .openApp, .openURL, .openFile: return "Open"
    case .sendKey: return "Press"
    case .setVariable, .toggleVariable, .incrementVariable: return "Set"
    case .setNotification: return "Notify"
    }
}

/// The rounded app-style badge used by list rows.
private struct CommandPaletteItemIcon: View {
    let item: CommandPaletteItem
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: item.icon)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(item.tintColor, in: RoundedRectangle(cornerRadius: size * 0.3))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

/// Placeholder shown when a palette has no matching commands.
private struct CommandPaletteEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

// MARK: - Spotlight Style

/// Spotlight-style overlay: a compact search pill that expands into a result list.
struct SpotlightPaletteView: View {
    @ObservedObject var controller: CommandPaletteController
    @State private var hoveredID: UUID?

    private var items: [CommandPaletteItem] { controller.filteredItems }
    private var stripItems: [CommandPaletteItem] { controller.stripItems }
    private var rowItems: [CommandPaletteItem] { controller.rowItems }
    private var visibleItems: [CommandPaletteItem] { controller.visibleItems }
    private var categories: [String] { controller.categories(for: items) }
    private var isCollapsed: Bool { controller.query.isEmpty && items.isEmpty }

    /// Verb for the highlighted command, shown inline after the query.
    private var selectedActionHint: String? {
        guard visibleItems.indices.contains(controller.selectedIndex) else { return nil }
        let item = visibleItems[controller.selectedIndex]
        return actionVerb(for: item.action.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .frame(height: isCollapsed ? 64 : 48)

            if !isCollapsed {
                if !stripItems.isEmpty {
                    stripRow
                }

                if !categories.isEmpty {
                    Divider().opacity(0.5)
                    categoryBar
                }

                Divider().opacity(0.5)

                if visibleItems.isEmpty {
                    CommandPaletteEmptyState(
                        title: controller.query.isEmpty ? "No Commands" : "No Matches",
                        message: controller.query.isEmpty
                            ? "Add commands to this palette to use it."
                            : "No commands match “\(controller.query)”."
                    )
                    .frame(height: 110)
                } else if !rowItems.isEmpty {
                    resultsList
                        .padding(.top, 5)
                        .padding(.bottom, 9)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isCollapsed ? 21 : 16))
        .overlay(
            RoundedRectangle(cornerRadius: isCollapsed ? 21 : 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            PaletteSearchField(controller: controller, fontSize: 16)

            if !controller.query.isEmpty, let verb = selectedActionHint {
                Text("— \(verb)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Category bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(categories, id: \.self) { category in
                    let isOn = controller.selectedCategory == category
                    Button {
                        controller.selectedCategory = isOn ? nil : category
                        controller.resetSelection()
                    } label: {
                        Text(category)
                            .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Color.primary : Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                isOn ? Color.primary.opacity(0.07) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 27)
    }

    // MARK: Strip

    /// Horizontal strip of compact command boxes, the way Spotlight presents
    /// apps. Shows the commands whose look is "Strip Box".
    private var stripRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stripItems) { item in
                        stripTile(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .frame(height: 84)
            .onChange(of: controller.selectedIndex) { _, index in
                guard stripItems.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(stripItems[index].id, anchor: .center)
                }
            }
        }
    }

    private func stripTile(_ item: CommandPaletteItem) -> some View {
        let isSelected = controller.isSelected(item)
        let isHovered = hoveredID == item.id
        return VStack(spacing: 5) {
            CommandPaletteItemIcon(item: item, size: 34)

            Text(item.name.isEmpty ? "Untitled" : item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(width: 64)
        }
        .padding(.vertical, 6)
        .frame(width: 76, height: 74)
        .background(
            isSelected ? Color.primary.opacity(0.10) : (isHovered ? Color.primary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.trigger(item) }
        .onHover { hoveredID = $0 ? item.id : nil }
        .help(item.subtitle.isEmpty ? item.name : "\(item.name) — \(item.subtitle)")
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rowItems) { item in
                        spotlightRow(item)
                            .id(item.id)
                            .onTapGesture { controller.trigger(item) }
                    }
                }
                .padding(.horizontal, 5)
            }
            .onChange(of: controller.selectedIndex) { _, index in
                guard rowItems.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(rowItems[index].id, anchor: .center)
                }
            }
        }
    }

    private func spotlightRow(_ item: CommandPaletteItem) -> some View {
        let isSelected = controller.isSelected(item)
        let isHovered = hoveredID == item.id
        return HStack(spacing: 11) {
            CommandPaletteItemIcon(item: item)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            if isSelected, let verb = actionVerb(for: item.action.kind) {
                HStack(spacing: 6) {
                    Text(verb)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            isSelected ? Color.primary.opacity(0.10) : (isHovered ? Color.primary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? item.id : nil }
    }
}

// MARK: - Shelf Style

/// Square drop shelf (Dropover-style): revealed beside the cursor by hotkey or by
/// wiggling the cursor while dragging files. Either/or — with no commands it is a
/// plain file shelf for gathering items; the commands the user adds (up to four)
/// become its 2×2 action grid, and dropped files are passed to those commands.
struct ShelfPaletteView: View {
    @ObservedObject var controller: CommandPaletteController
    @State private var isTargeted = false

    /// The shelf shows at most four commands in a 2×2 grid.
    private var items: [CommandPaletteItem] {
        Array(controller.visibleItems.prefix(4))
    }
    private var hasCommands: Bool { !items.isEmpty }
    private var hiddenCount: Int {
        max(controller.visibleItems.count - 4, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .frame(height: 32)

            if hasCommands {
                dropZone
                    .padding(.horizontal, 10)
                actionGrid
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            } else {
                // Pure file shelf: the whole square is the drop zone.
                dropZone
                    .padding(10)
            }
        }
        .frame(width: 260, height: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(isTargeted ? Color.blue.opacity(0.6) : Color.secondary.opacity(0.25), lineWidth: isTargeted ? 1.5 : 0.5)
        )
        .animation(.spring(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: controller.activePalette?.icon ?? "tray.full")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(controller.activePalette?.name ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()

            if !controller.droppedFiles.isEmpty {
                Button {
                    controller.clearDroppedFiles()
                } label: {
                    Text("\(controller.droppedFiles.count) ✕")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Clear gathered files")
            }

            Button {
                controller.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close shelf")
        }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                isTargeted ? Color.blue : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.2, dash: isTargeted ? [] : [5, 3])
            )
            .background(
                isTargeted ? Color.blue.opacity(0.10) : Color.primary.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                if controller.droppedFiles.isEmpty {
                    emptyDropHint
                } else {
                    fileChips
                }
            }
            .frame(maxHeight: .infinity)
    }

    private var emptyDropHint: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isTargeted ? Color.blue : Color.secondary)
            Text("Drop files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var fileChips: some View {
        let files = controller.droppedFiles
        let shown = Array(files.prefix(4))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(shown, id: \.self) { url in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 15, height: 15)
                    Text(url.lastPathComponent)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
                .onTapGesture { controller.removeDroppedFile(url) }
            }
            if files.count > shown.count {
                Text("+ \(files.count - shown.count) more")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
        }
        .padding(6)
    }

    // MARK: Action grid (2×2)

    private var actionGrid: some View {
        VStack(spacing: 2) {
            // Fixed columns (the panel is a fixed 260pt square).
            LazyVGrid(columns: [GridItem(.fixed(117), spacing: 6), GridItem(.fixed(117), spacing: 6)], spacing: 6) {
                ForEach(items) { item in
                    let isSelected = controller.isSelected(item)
                    Button {
                        controller.trigger(item)
                    } label: {
                        HStack(spacing: 6) {
                            CommandPaletteItemIcon(item: item, size: 20)
                            Text(item.name.isEmpty ? "Untitled" : item.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 38)
                        .background(
                            isSelected ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if hiddenCount > 0 {
                Text("…+\(hiddenCount) more commands")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                DispatchQueue.main.async {
                    if let url = Self.url(from: item) {
                        controller.addDroppedFile(url)
                    }
                }
            }
            accepted = true
        }
        return accepted
    }

    /// Drag pasteboards deliver the fileURL payload as URL data, a URL object,
    /// or a plain POSIX path depending on the source.
    private static func url(from item: (any NSSecureCoding)?) -> URL? {
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url
        }
        if let url = item as? URL, url.isFileURL {
            return url
        }
        if let path = item as? String, !path.isEmpty {
            var isDir: ObjCBool = false
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Grid Style

/// Grid of large tiles, like a launcher.
struct GridPaletteView: View {
    @ObservedObject var controller: CommandPaletteController
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                PaletteSearchField(controller: controller, fontSize: 15)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)

            Divider().opacity(0.5)

            if controller.filteredItems.isEmpty {
                CommandPaletteEmptyState(
                    title: controller.query.isEmpty ? "No Commands" : "No Matches",
                    message: controller.query.isEmpty
                        ? "Add commands to this palette to use it."
                        : "No commands match “\(controller.query)”."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(controller.filteredItems) { item in
                            let isSelected = controller.isSelected(item)
                            Button {
                                controller.trigger(item)
                            } label: {
                                VStack(spacing: 8) {
                                    CommandPaletteItemIcon(item: item, size: 44)
                                    Text(item.name.isEmpty ? "Untitled" : item.name)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isSelected ? Color.primary.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Circular Style

/// Radial palette with the commands arranged around a circle.
struct CircularPaletteView: View {
    @ObservedObject var controller: CommandPaletteController

    var body: some View {
        GeometryReader { geo in
            let items = controller.filteredItems
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2 - 52

            ZStack {
                // Centre badge
                VStack(spacing: 5) {
                    Image(systemName: controller.activePalette?.icon ?? "command.square")
                        .font(.system(size: 20))
                    Text(controller.activePalette?.name ?? "Palette")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                .position(center)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let angle = (Double(index) / Double(max(items.count, 1))) * 2 * .pi - .pi / 2
                    let position = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    let isSelected = controller.isSelected(item)

                    Button {
                        controller.trigger(item)
                    } label: {
                        VStack(spacing: 4) {
                            CommandPaletteItemIcon(item: item, size: isSelected ? 46 : 40)
                            Text(item.name.isEmpty ? "Untitled" : item.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .frame(width: 68)
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(position)
                }
            }
        }
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }
}
