import AppKit
import Carbon.HIToolbox
import IOKit.hid
import ScreenCaptureKit

enum KeyboardRemapEngineState: Equatable {
    case inactive
    case active(count: Int)
    case needsAccessibilityPermission
    case failed(String)
}

final class KeyboardRemapEngine {
    var onStateChange: ((KeyboardRemapEngineState) -> Void)?
    var onExecuteAction: ((Manipulator, Action, CGEventTapProxy?) -> Void)?

    private(set) var state: KeyboardRemapEngineState = .inactive {
        didSet { onStateChange?(state) }
    }

    private(set) var variables: [String: String] = [:]
    private(set) var globalVariables: [String: String] = [:]
    var onGlobalVariablesChange: (([String: String]) -> Void)?
    private(set) var namedClipboards: [String: String] = [:]
    private var stickyModifiers: [ModifierKey: Bool] = [:]
    private var lazyModifiers: Set<ModifierKey> = []

    private var manipulators: [Manipulator] = []
    private var routing = RoutingCache()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?


    private var sequenceProgress: [String: SequenceProgress] = [:]

    /// A trigger group bundles one trigger with its own conditions.
    struct TriggerGroup {
        let trigger: ManipulatorTrigger
        let conditions: [Condition]
        let groupIndex: Int
    }

    /// Unique key for per-trigger-group state tracking.
    private func triggerGroupKey(manipulatorID: UUID, groupIndex: Int) -> String {
        "\(manipulatorID.uuidString):\(groupIndex)"
    }

    /// Lightweight route entry: stores only the manipulator ID instead of the full
    /// ~1KB Manipulator struct. The actual Manipulator is looked up from a dictionary
    /// (`manipulatorCache`) that lives alongside the routing arrays.
    struct ManipulatorRoute {
        let manipulatorID: UUID
        let triggerGroups: [TriggerGroup]
    }

    struct RoutingCache {
        /// Route arrays store lightweight entries (UUID + trigger groups).
        var all: [ManipulatorRoute] = []
        var keyboard: [ManipulatorRoute] = []
        var pointing: [ManipulatorRoute] = []
        var mouseMotionToScroll: [ManipulatorRoute] = []
        var stringTriggers: [ManipulatorRoute] = []
        var hotKeys: [ManipulatorRoute] = []
        var simultaneous: [ManipulatorRoute] = []
        var consumer: [ManipulatorRoute] = []

        /// Full manipulator data keyed by ID for O(1) lookup from routes.
        /// This avoids storing the ~1KB Manipulator struct in every route entry.
        var manipulatorCache: [UUID: Manipulator] = [:]

        var needsMouseMoved: Bool { !mouseMotionToScroll.isEmpty }

        /// Look up a manipulator from the cache by its UUID.
        func manipulator(for id: UUID) -> Manipulator? {
            manipulatorCache[id]
        }

        /// Convenient subscript access for routes — safe because every route
        /// in the cache is guaranteed to have a cache entry.
        subscript(route: ManipulatorRoute) -> Manipulator {
            manipulatorCache[route.manipulatorID]!
        }

        /// Build the routing cache from scratch for the full manipulator list.
        static func build(from manipulators: [Manipulator]) -> RoutingCache {
            var cache = RoutingCache()
            cache.manipulatorCache.reserveCapacity(manipulators.count)
            for manipulator in manipulators where manipulator.isEnabled {
                cache.manipulatorCache[manipulator.id] = manipulator
                cache.insert(manipulator: manipulator)
            }
            return cache
        }

        /// Incremental update: compares old and new manipulator lists and only rebuilds
        /// routes for manipulators whose routing-relevant properties changed.
        /// Non-routing properties (name, notes, folder, tags) do NOT trigger a rebuild.
        static func diffUpdate(
            from newManipulators: [Manipulator],
            oldCache: RoutingCache,
            oldManipulators: [Manipulator]
        ) -> RoutingCache {
            // Build lookup by ID for old manipulators
            let oldByID = Dictionary(uniqueKeysWithValues: oldManipulators.map { ($0.id, $0) })
            let newByID = Dictionary(uniqueKeysWithValues: newManipulators.map { ($0.id, $0) })

            var cache = oldCache

            // ── Removed manipulators ──
            let removedIDs = Set(oldByID.keys).subtracting(newByID.keys)
            for id in removedIDs {
                cache.remove(manipulatorID: id)
                cache.manipulatorCache.removeValue(forKey: id)
            }

            // ── Added or changed manipulators ──
            for (id, newManip) in newByID {
                if let oldManip = oldByID[id] {
                    // Exists in both — only rebuild if routing-relevant properties changed
                    guard hasRoutingRelevantChange(oldManip, newManip) else {
                        // Still update the cache entry in case non-routing props changed
                        cache.manipulatorCache[id] = newManip
                        continue
                    }
                    // Remove old route, insert updated one
                    cache.remove(manipulatorID: id)
                }
                cache.manipulatorCache[id] = newManip
                if newManip.isEnabled {
                    cache.insert(manipulator: newManip)
                }
            }

            return cache
        }

        /// Check if two manipulators differ in routing-relevant properties.
        /// (name, notes, folder, and tags are NOT routing-relevant.)
        static func hasRoutingRelevantChange(_ old: Manipulator, _ new: Manipulator) -> Bool {
            return old.isEnabled != new.isEnabled
                || old.manipulatorType != new.manipulatorType
                || old.trigger != new.trigger
                || old.conditions != new.conditions
                || old.actions != new.actions
                || old.parameters != new.parameters
                || old.additionalTriggers != new.additionalTriggers
        }

        /// Insert a single manipulator into the cache (builds its route).
        mutating func insert(manipulator: Manipulator) {
            guard manipulator.isEnabled else { return }
            let groups = Self.triggerGroups(for: manipulator)
            let eventGroups = groups.filter { $0.trigger.triggerName.isEmpty && $0.trigger.stringTrigger == nil }
            let stringGroups = groups.filter { $0.trigger.stringTrigger?.isValid == true }
            let hotKeyGroups = eventGroups.filter { group in
                guard let hotKey = group.trigger.hotKey, hotKey.isValid else { return false }
                return hotKey.tapCount > 1 || hotKey.holdRequired
            }
            let simultaneousGroups = eventGroups.filter { $0.trigger.simultaneous?.isValid == true }
            let consumerGroups = eventGroups.filter { $0.trigger.keyType == .consumer }

            let routeID = manipulator.id

            if !eventGroups.isEmpty {
                let route = ManipulatorRoute(manipulatorID: routeID, triggerGroups: eventGroups)
                all.append(route)

                if manipulator.manipulatorType == .basic,
                   eventGroups.contains(where: { $0.trigger.keyType != .pointing }) {
                    keyboard.append(route)
                }
                if manipulator.manipulatorType == .mouseBasic
                    || eventGroups.contains(where: { $0.trigger.keyType == .pointing }) {
                    pointing.append(route)
                }
                if manipulator.manipulatorType == .mouseMotionToScroll {
                    mouseMotionToScroll.append(route)
                }
            }

            if !stringGroups.isEmpty {
                stringTriggers.append(ManipulatorRoute(manipulatorID: routeID, triggerGroups: stringGroups))
            }
            if !hotKeyGroups.isEmpty {
                hotKeys.append(ManipulatorRoute(manipulatorID: routeID, triggerGroups: hotKeyGroups))
            }
            if !simultaneousGroups.isEmpty {
                simultaneous.append(ManipulatorRoute(manipulatorID: routeID, triggerGroups: simultaneousGroups))
            }
            if !consumerGroups.isEmpty {
                consumer.append(ManipulatorRoute(manipulatorID: routeID, triggerGroups: consumerGroups))
            }
        }

        /// Remove all route entries for a given manipulator ID from every routing array.
        mutating func remove(manipulatorID id: UUID) {
            let removeFrom: [WritableKeyPath<RoutingCache, [ManipulatorRoute]>] = [
                \.all, \.keyboard, \.pointing, \.mouseMotionToScroll,
                \.stringTriggers, \.hotKeys, \.simultaneous, \.consumer
            ]
            for keyPath in removeFrom {
                self[keyPath: keyPath].removeAll { $0.manipulatorID == id }
            }
        }

        static func triggerGroups(for manipulator: Manipulator) -> [TriggerGroup] {
            var groups: [TriggerGroup] = []
            groups.reserveCapacity(1 + manipulator.additionalTriggers.count)
            groups.append(TriggerGroup(trigger: manipulator.trigger, conditions: manipulator.conditions, groupIndex: 0))
            for (idx, additional) in manipulator.additionalTriggers.enumerated() {
                groups.append(TriggerGroup(trigger: additional.trigger, conditions: additional.conditions, groupIndex: idx + 1))
            }
            return groups
        }
    }

    /// Bitmask-based modifier key tracking for fast set operations.
    /// Using an OptionSet instead of Set<String> eliminates string hashing
    /// overhead on every flagsChanged/key event.
    struct HeldModifierMask: OptionSet, Sendable {
        let rawValue: UInt16

        static let leftControl  = HeldModifierMask(rawValue: 1 << 0)
        static let leftShift    = HeldModifierMask(rawValue: 1 << 1)
        static let rightShift   = HeldModifierMask(rawValue: 1 << 2)
        static let leftCommand  = HeldModifierMask(rawValue: 1 << 3)
        static let rightCommand = HeldModifierMask(rawValue: 1 << 4)
        static let leftOption   = HeldModifierMask(rawValue: 1 << 5)
        static let rightOption  = HeldModifierMask(rawValue: 1 << 6)
        static let rightControl = HeldModifierMask(rawValue: 1 << 7)
        static let fn           = HeldModifierMask(rawValue: 1 << 8)
        static let capsLock     = HeldModifierMask(rawValue: 1 << 9)

            /// All modifier key masks.
        static let all: HeldModifierMask = [.leftControl, .leftShift, .rightShift, .leftCommand, .rightCommand, .leftOption, .rightOption, .rightControl, .fn, .capsLock]

        /// Clear all bits.
        mutating func removeAll() {
            self = []
        }

        /// Map a keyID string to its mask bit.
        static func bit(for keyID: String) -> HeldModifierMask? {
            switch keyID {
            case "left_control":  return .leftControl
            case "left_shift":    return .leftShift
            case "right_shift":   return .rightShift
            case "left_command":  return .leftCommand
            case "right_command": return .rightCommand
            case "left_option":   return .leftOption
            case "right_option":  return .rightOption
            case "right_control": return .rightControl
            case "fn":            return .fn
            case "caps_lock":     return .capsLock
            default:              return nil
            }
        }

        /// All mask bits for a logical ModifierKey (may have left+right variants).
        static func bits(for modifier: ModifierKey) -> HeldModifierMask {
            switch modifier {
            case .control: return [.leftControl, .rightControl]
            case .shift:   return [.leftShift, .rightShift]
            case .command: return [.leftCommand, .rightCommand]
            case .option:  return [.leftOption, .rightOption]
            case .fn:      return .fn
            case .capsLock: return .capsLock
            }
        }
    }

    // Track physical key-down state for modifier keys (left/right discrimination)
    private var heldModifierKeys: HeldModifierMask = []
    private var modifierKeyStates: [CGKeyCode: Bool] = [:]
    /// Modifier keys whose key-down was swallowed by a manipulator; their
    /// key-up (flagsChanged) must be swallowed too.
    private var swallowedModifierKeys: HeldModifierMask = []


    // Active press tracking for held-down / to-if-alone / delayed-action semantics.
    private struct ActivePress {
        let manipulator: Manipulator
        let keyID: String
        let keyType: TriggerKeyType
        let downTime: Date
        let proxy: CGEventTapProxy?
    }
    private var activePresses: [UUID: ActivePress] = [:]
    private var pressTimers: [UUID: [ActionFireMode: Task<Void, Never>]] = [:]

    // Simultaneous chord tracking
    private struct SimultaneousState {
        let manipulatorID: UUID
        var heldKeys: Set<String>
        var downTimes: [String: Date]
    }
    private var simultaneousStates: [String: SimultaneousState] = [:]

    // String trigger tracking: per-manipulator buffer of typed characters
    // and a timer that resets the buffer after a period of inactivity.
    private var stringInputBuffer: [UUID: String] = [:]
    private var stringInputTimers: [UUID: Task<Void, Never>] = [:]

    // MARK: - Hot‑key multi‑tap tracking

    /// Tracks the current tap‑counting progress for manipulators with a `HotKeyTriggerConfig`.
    private struct MultiTapProgress {
        let manipulatorID: UUID
        let keyID: String
        var count: Int
        var lastTapTime: Date
        var timerTask: Task<Void, Never>?
    }

    private var multiTapProgress: [String: MultiTapProgress] = [:]

    /// Track pending hold tasks for manipulators where `holdRequired` is true.
    /// The hold task fires after `holdThresholdMilliseconds` from the final tap.
    private var multiTapPendingHolds: [String: Task<Void, Never>] = [:]

    deinit {
        cancelAllStringTimers()
        cancelAllMultiTapTimers()
        cancelAllPendingHolds()
        removeObservers()
        stop()
    }

    // MARK: - Caches for expensive conditions

    private var cachedInputSourceID: String?
    private var cachedFrontmostApp: NSRunningApplication?
    private var inputSourceObserver: NSObjectProtocol?
    private var frontmostAppObserver: NSObjectProtocol?

    /// Cache for running app lookups: lowered bundle ID/name → true
    private var cachedRunningApps: Set<String> = []
    private var runningAppsCacheTime: Date = .distantPast
    private let runningAppsCacheTTL: TimeInterval = 2.0

    /// Cache for pixel color conditions: key="x,y" → (colorHex, timestamp)
    private var pixelColorCache: [String: (String, Date)] = [:]
    /// Pixel color cache TTL in seconds (0.5 = updated twice per second)
    private let pixelColorCacheTTL: TimeInterval = 0.5

    /// Cache for frontmost window properties: key=property → value
    private var windowPropertyCache: [String: String] = [:]
    private var windowPropertyCacheTime: Date = .distantPast
    private let windowPropertyCacheTTL: TimeInterval = 1.0

    /// Per-event condition result cache to avoid redundant evaluation across routing passes.
    /// Reset at the start of each handle() call.
    private var eventConditionCache: [UUID: Bool] = [:]

    /// Ordered condition evaluation: cheap conditions are checked before expensive ones.
    /// This allows early-exit without hitting AX/ScreenCapture APIs when a cheap condition fails.
    private static let cheapConditionKinds: Set<ConditionKind> = [
        .variable, .globalVariable, .expression, .eventChanged,
        .namedClipboard, .device, .deviceExists
    ]
    private static let mediumConditionKinds: Set<ConditionKind> = [
        .frontmostApp, .frontmostAppName, .inputSource, .keyboardType,
        .runningCondition, .screen
    ]
    // .window, .token, .pixelCondition are expensive (AXUI / ScreenCaptureKit)

    // Cached DateFormatters to avoid allocating one per token resolution call.
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    private func setupObservers() {
        // Invalidate input source cache when it changes
        inputSourceObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.cachedInputSourceID = nil
        }
        // Invalidate frontmost app cache when the active app changes
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.cachedFrontmostApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }
        // NOTE: The distributed notification "NSTextInputContextKeyboardSelectionDidChangeNotification"
        // was previously registered here as a duplicate of the system notification above.
        // Removed to avoid redundant cache invalidation.
    }

    private func removeObservers() {
        if let obs = inputSourceObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = frontmostAppObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        inputSourceObserver = nil
        frontmostAppObserver = nil
    }

    // Cache a single Date() at the start of handle() to avoid multiple allocations per event.
    private var eventTimestamp: Date = .distantPast
    /// Cached NSEvent for each handle() call to avoid redundant CGEvent→NSEvent bridging.
    private var cachedNSEvent: NSEvent?

    // Reentrancy guard: prevents the event-tap callback from re-entering
    // itself when our own actions post events back to the session event tap.
    private var eventTapReentrant: Bool = false

    // Exponential backoff for tap-disabled-by-timeout events.
    // Resets on successful event processing, doubles on each timeout.
    private var tapTimeoutCount: Int = 0
    private let maxBackoffDelay: Double = 10.0 // cap at 10 seconds

    // MARK: - Public API

    func apply(_ manipulators: [Manipulator]) {
        let newFiltered = manipulators.filter { m in
            m.isEnabled && (m.trigger.isValid || m.manipulatorType != .basic
                || m.additionalTriggers.contains(where: { $0.trigger.isValid }))
        }

        // Use diff-based routing update: only rebuild routes for manipulators
        // whose routing-relevant properties changed. This is much faster than
        // a full rebuild when only 1-2 manipulators are edited at a time.
        if !self.manipulators.isEmpty && !routing.all.isEmpty {
            routing = RoutingCache.diffUpdate(
                from: newFiltered,
                oldCache: routing,
                oldManipulators: self.manipulators
            )
        } else {
            routing = RoutingCache.build(from: newFiltered)
        }
        self.manipulators = newFiltered

        sequenceProgress.removeAll()
        simultaneousStates.removeAll()
        cancelAllActivePresses()
        cancelAllStringTimers()
        cancelAllMultiTapTimers()
        cancelAllPendingHolds()
        stringInputBuffer.removeAll()

        let count = self.manipulators.count
        guard count > 0 else {
            stop()
            state = .inactive
            return
        }

        guard ensureAccessibilityPermission(prompt: true) else {
            stop()
            state = .needsAccessibilityPermission
            return
        }

        guard startIfNeeded() else { return }
        state = .active(count: count)
    }

    func requestAccessibilityPermission() {
        _ = ensureAccessibilityPermission(prompt: true)
        if ensureAccessibilityPermission(prompt: false) {
            if !manipulators.isEmpty, startIfNeeded() {
                state = .active(count: manipulators.count)
            } else {
                state = .inactive
            }
        } else {
            state = .needsAccessibilityPermission
        }
    }

    func stop() {
        removeObservers()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        cancelAllActivePresses()
        cancelAllStringTimers()
        cancelAllMultiTapTimers()
        cancelAllPendingHolds()
        stringInputBuffer.removeAll()
        simultaneousStates.removeAll()
        heldModifierKeys.removeAll()
        modifierKeyStates.removeAll()
        swallowedModifierKeys.removeAll()
    }

    func setVariable(name: String, value: String) {
        variables[name] = value
    }

    func unsetVariable(name: String) {
        variables.removeValue(forKey: name)
    }

    func resetVariables() {
        variables.removeAll()
    }

    func setGlobalVariable(name: String, value: String) {
        globalVariables[name] = value
        onGlobalVariablesChange?(globalVariables)
    }

    func unsetGlobalVariable(name: String) {
        globalVariables.removeValue(forKey: name)
        onGlobalVariablesChange?(globalVariables)
    }

    func loadGlobalVariables(_ vars: [String: String]) {
        globalVariables = vars
    }

    func resetGlobalVariables() {
        globalVariables.removeAll()
        onGlobalVariablesChange?(globalVariables)
    }

    func setNamedClipboard(name: String, value: String) {
        namedClipboards[name] = value
    }

    func unsetNamedClipboard(name: String) {
        namedClipboards.removeValue(forKey: name)
    }

    func setStickyModifier(_ modifier: ModifierKey, active: Bool) {
        stickyModifiers[modifier] = active
        if active {
            postModifierPress(modifier: modifier, down: true)
        } else {
            postModifierPress(modifier: modifier, down: false)
        }
    }

    func toggleStickyModifier(_ modifier: ModifierKey) {
        let current = stickyModifiers[modifier] ?? false
        setStickyModifier(modifier, active: !current)
    }

    func setLazyModifiers(_ modifiers: Set<ModifierKey>) {
        lazyModifiers.formUnion(modifiers)
    }

    // MARK: - Named trigger

    /// Trigger a manipulator by its trigger name.
    /// - Parameters:
    ///   - name: The triggerName of the manipulator to trigger.
    ///   - proxy: Optional CGEventTapProxy for event posting.
    /// - Returns: `true` if a named manipulator was found and executed.
    @discardableResult
    func triggerNamedTrigger(name: String, proxy: CGEventTapProxy? = nil) -> Bool {
        for manipulator in manipulators where manipulator.isEnabled {
            guard manipulator.trigger.triggerName == name else { continue }
            guard allConditionsMet(manipulator.conditions) else { continue }
            for action in manipulator.actions {
                guard actionConditionsMet(action) else { continue }
                onExecuteAction?(manipulator, action, proxy)
                if action.kind == .halt { break }
            }
            return true
        }
        return false
    }

    // MARK: - Event handling

    private func startIfNeeded() -> Bool {
        if eventTap != nil { return true }
        setupObservers()

        var eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        if routing.needsMouseMoved {
            eventTypes.append(.mouseMoved)
        }
        // Register for system-defined events (consumer/media keys: volume, brightness, etc.)
        // These arrive as CGEventType 14 (NX_SYSDEFINED), not .flagsChanged.
        if let sysDefined = CGEventType(rawValue: 14) {
            eventTypes.append(sysDefined)
        }
        let events = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (1 << type.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            state = .failed("Could not create event tap. Disable App Sandbox and grant Accessibility.")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            state = .failed("Could not create run loop source for event tap.")
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // REENTRANCY GUARD: If we are already processing an event (e.g. our
        // own actions posted a new CGEvent back to the session tap), pass
        // the event through immediately so we cannot stack-overflow or freeze.
        if eventTapReentrant { return Unmanaged.passUnretained(event) }
        eventTapReentrant = true
        defer { eventTapReentrant = false }

        // Reset per-event caches and capture a single timestamp for this event cycle
        eventTimestamp = Date()
        cachedNSEvent = NSEvent(cgEvent: event)
        eventConditionCache.removeAll(keepingCapacity: true)

        // Reset timeout backoff — if we received an event, the tap is working
        tapTimeoutCount = 0

        switch type {
        case .tapDisabledByTimeout:
            // Exponential backoff: 0.1s, 0.2s, 0.4s, 0.8s, 1.6s, 3.2s, 6.4s, 10s (capped)
            tapTimeoutCount += 1
            let delay = min(pow(2.0, Double(tapTimeoutCount - 1)) * 0.1, maxBackoffDelay)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let eventTap = self.eventTap else { return }
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .tapDisabledByUserInput:
            // Don't auto-re-enable on user input disable; user must manually restart.
            tapTimeoutCount = 0
            state = .inactive
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            return dispatchKeyDown(keyCode: keyCode, flags: flags, event: event, proxy: proxy)

        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return handleKeyUp(keyCode: keyCode, event: event)

        case .flagsChanged:
            return handleFlagsChanged(event: event, proxy: proxy)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleMouseDown(type: type, event: event)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return handleMouseUp(type: type, event: event)

        case .mouseMoved:
            return handleMouseMotionToScroll(event: event, proxy: proxy)

        default:
            // System-defined events (consumer/media keys like volume, brightness)
            // arrive as CGEventType(rawValue: 14) with NSEvent subtype 8.
            if let nsEvent = cachedNSEvent,
               nsEvent.type == .systemDefined,
               nsEvent.subtype.rawValue == 8 {
                let nxKeyType = Int32((nsEvent.data1 >> 16) & 0xFFFF)
                if let consumerKeyID = consumerKeyIDForNXKeyType(nxKeyType) {
                    if let result = dispatchConsumerKeyDown(consumerKeyID: consumerKeyID, event: event) {
                        return result
                    }
                    return nil
                }
            }
            // Reset timeout backoff on any successful event processing
            tapTimeoutCount = 0
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Key dispatch

    private func dispatchKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent, proxy: CGEventTapProxy?) -> Unmanaged<CGEvent>? {
        guard let keyID = KeyboardKeyCodeMap.id(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        // Check sticky modifiers
        let augmentedFlags = applyStickyModifiers(to: flags)

        // Interruption check
        for (id, press) in activePresses where press.keyID != keyID {
            resolvePress(manipulatorID: id, with: .interrupted)
        }

        // --- Hot‑key multi‑tap check ---
        // When any trigger group has a `HotKeyTriggerConfig` we intercept the key
        // BEFORE normal sequence/step matching so that taps are counted without
        // reaching the system or conflicting with other trigger logic.
        var hotKeySwallowed = false
        for route in routing.hotKeys where routing[route].manipulatorType == .basic {
            let manipulator = routing[route]
            for group in route.triggerGroups {
                guard let hotKey = group.trigger.hotKey, hotKey.isValid,
                      hotKey.tapCount > 1 || hotKey.holdRequired else { continue }
                guard allConditionsMet(group.conditions) else { continue }

                let keyMatches: Bool
                if group.trigger.anyKey {
                    keyMatches = true
                } else {
                    keyMatches = group.trigger.steps.contains { step in
                        step.key == keyID && modifiersMatch(step, flags: augmentedFlags)
                    }
                }
                guard keyMatches else { continue }

                if handleMultiTap(for: manipulator, keyID: keyID, hotKey: hotKey, flags: augmentedFlags, proxy: proxy, groupIndex: group.groupIndex) {
                    hotKeySwallowed = true
                    break
                }
            }
            if hotKeySwallowed { break }
        }

        if hotKeySwallowed {
            return nil
        }

        var didSwallow = false
        for route in routing.keyboard {
            let manipulator = routing[route]
            for group in route.triggerGroups {
                guard allConditionsMet(group.conditions) else { continue }
                let trigger = group.trigger

                if trigger.anyKey {
                    executeFire(for: manipulator, keyID: keyID, keyType: .keyboard, proxy: proxy)
                    didSwallow = true
                    break
                }

                switch advanceSequenceTrigger(manipulator, trigger: trigger, groupIndex: group.groupIndex, keyID: keyID, flags: augmentedFlags) {
                case .noMatch:
                    if trigger.simultaneous != nil {
                        if advanceSimultaneousTrigger(manipulator, trigger: trigger, groupIndex: group.groupIndex, keyID: keyID, flags: augmentedFlags, proxy: proxy) {
                            didSwallow = true
                            break
                        }
                    }
                    continue
                case .advanced:
                    didSwallow = true
                    break
                case .fired:
                    executeFire(for: manipulator, keyID: keyID, keyType: .keyboard, proxy: proxy)
                    if shouldHalt(for: manipulator) { return nil }
                    didSwallow = true
                    break
                }
            }
        }

        // Check string triggers from all trigger groups
        checkStringTriggers(keyID: keyID, event: event, proxy: proxy)

        if !lazyModifiers.isEmpty, !KeyboardKeyCodeMap.isModifierKeyID(keyID) {
            lazyModifiers.removeAll()
        }

        return didSwallow ? nil : Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(keyCode: CGKeyCode, event: CGEvent) -> Unmanaged<CGEvent> {
        guard let keyID = KeyboardKeyCodeMap.id(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        // Cancel any pending multi‑tap holds that are waiting for this key.
        // If the hold timer hasn't fired yet, the user released before the
        // hold threshold — the multi‑tap sequence is silently discarded.
        for (key, task) in multiTapPendingHolds {
            let parts = key.split(separator: ":")
            guard parts.count >= 2, let manipulatorID = UUID(uuidString: String(parts[0])) else { continue }
            guard let manipulator = manipulators.first(where: { $0.id == manipulatorID }) else { continue }

            // Check if this key matches the manipulator's trigger
            let matchFound = manipulator.trigger.steps.contains { $0.key == keyID }
                || manipulator.trigger.anyKey
                || (manipulator.trigger.keyType == .consumer && manipulator.trigger.steps.first?.key == keyID)
                || (manipulator.trigger.keyType == .pointing && manipulator.trigger.steps.first?.key == keyID)

            if matchFound {
                task.cancel()
                multiTapPendingHolds.removeValue(forKey: key)
            }
        }

        // Check simultaneous triggers for key up across all trigger groups
        for route in routing.simultaneous {
            let manipulator = routing[route]
            for group in route.triggerGroups {
                guard group.trigger.simultaneous?.isValid == true else { continue }
                checkSimultaneousKeyUp(manipulator, keyID: keyID, groupIndex: group.groupIndex)
            }
        }

        for id in activePresses.keys.filter({ activePresses[$0]?.keyID == keyID }) {
            resolvePress(manipulatorID: id, with: .released)
        }
        return Unmanaged.passUnretained(event)
    }

    /// Device-specific CGEventFlags bit for an individual (left/right) modifier key.
    /// These NX_DEVICE* bits let us derive press/release directly from the event
    /// flags instead of toggling stored state (which desyncs if events are missed,
    /// e.g. when the tap starts while a modifier is already held).
    private static func deviceModifierFlagBit(for keyID: String) -> CGEventFlags? {
        switch keyID {
        case "left_control": return CGEventFlags(rawValue: 0x00000001)
        case "left_shift": return CGEventFlags(rawValue: 0x00000002)
        case "right_shift": return CGEventFlags(rawValue: 0x00000004)
        case "left_command": return CGEventFlags(rawValue: 0x00000008)
        case "right_command": return CGEventFlags(rawValue: 0x00000010)
        case "left_option": return CGEventFlags(rawValue: 0x00000020)
        case "right_option": return CGEventFlags(rawValue: 0x00000040)
        case "right_control": return CGEventFlags(rawValue: 0x00002000)
        case "fn": return .maskSecondaryFn
        default: return nil // caps_lock has no reliable device bit; use toggle tracking
        }
    }

    private func handleFlagsChanged(event: CGEvent, proxy: CGEventTapProxy?) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if let keyID = KeyboardKeyCodeMap.id(for: keyCode), KeyboardKeyCodeMap.isModifierKeyID(keyID) {
            // Derive press direction from the device-specific flag bit when
            // available; fall back to toggle tracking (caps lock).
            let isDown: Bool
            if let bit = Self.deviceModifierFlagBit(for: keyID) {
                isDown = flags.contains(bit)
            } else {
                isDown = !(modifierKeyStates[keyCode, default: false])
            }
            modifierKeyStates[keyCode] = isDown



            if isDown {
                if let bit = HeldModifierMask.bit(for: keyID) {
                    heldModifierKeys.insert(bit)
                }
            } else {
                if let bit = HeldModifierMask.bit(for: keyID) {
                    heldModifierKeys.remove(bit)
                }
            }

            // Modifier keys never produce keyDown/keyUp events — they only
            // arrive here as flagsChanged. Route them through the regular
            // dispatch so manipulators triggered BY a modifier key
            // (caps_lock → escape, right_command → …, etc.) actually fire.
            if isDown {
                if dispatchKeyDown(keyCode: keyCode, flags: flags, event: event, proxy: proxy) == nil {
                    if let bit = HeldModifierMask.bit(for: keyID) {
                        swallowedModifierKeys.insert(bit)
                    }
                    return nil
                }
            } else {
                // Resolve presses waiting on this modifier's key-up
                // (if-alone / after-key-up fire modes).
                for id in activePresses.keys.filter({ activePresses[$0]?.keyID == keyID }) {
                    resolvePress(manipulatorID: id, with: .released)
                }
                for route in routing.simultaneous {
                    let manipulator = routing[route]
                    for group in route.triggerGroups {
                        guard group.trigger.simultaneous?.isValid == true else { continue }
                        checkSimultaneousKeyUp(manipulator, keyID: keyID, groupIndex: group.groupIndex)
                    }
                }
                // If we swallowed the corresponding key-down, swallow the
                // key-up too so apps never see a half-pressed modifier.
                if let bit = HeldModifierMask.bit(for: keyID),
                   swallowedModifierKeys.contains(bit) {
                    swallowedModifierKeys.remove(bit)
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if let nsEvent = cachedNSEvent ?? NSEvent(cgEvent: event) {
            if nsEvent.type == .flagsChanged {
                let keyCodeInt = Int(nsEvent.keyCode)
                if let consumerKeyID = consumerKeyID(forNSEventKeyCode: keyCodeInt) {
                    if let result = dispatchConsumerKeyDown(consumerKeyID: consumerKeyID, event: event) {
                        return result
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - String trigger dispatch

    /// Characters that are considered printable and can be accumulated
    /// into a string trigger buffer. Modifier keys and function keys reset the buffer.
    /// Set of key IDs that should NOT be treated as printable text input.
    /// NOTE: backspace (key ID `"delete"`) is intentionally excluded from
    /// this set — it is handled by removing the last character from the buffer.
    private static let stringTriggerNonPrintableKeyIDs: Set<String> = {
        var set = Set<String>()
        // Navigation / cursor keys
        set.insert("left_arrow")
        set.insert("right_arrow")
        set.insert("up_arrow")
        set.insert("down_arrow")
        // Editing / control keys
        set.insert("return")
        set.insert("escape")
        set.insert("forward_delete")
        set.insert("tab")
        set.insert("space")
        // Jump keys
        set.insert("home")
        set.insert("end")
        set.insert("pageup")
        set.insert("pagedown")
        // Function keys
        for i in 1...20 {
            set.insert("f\(i)")
        }
        set.insert("help")
        // Consumer/Media keys are non-printable
        for cc in ConsumerKeyCode.allCases {
            set.insert("vk_consumer_\(cc.rawValue)")
        }
        return set
    }()

    /// Evaluate all manipulators that have a string trigger, accumulating the
    /// typed character into their buffers and firing on match.  This never
    /// swallows the event — the typed character must reach the application so
    /// that autocorrect-style actions (backspace → retype) work correctly.
    ///
    /// Unlike the `keyID`-based triggers (sequence, simultaneous), string triggers
    /// need the *actual* characters a text field would receive.  We obtain these
    /// from `NSEvent.characters`, which respects keyboard layout, modifier state,
    /// dead keys, and IME composition.
    private func checkStringTriggers(keyID: String, event: CGEvent, proxy: CGEventTapProxy?) {
        // Modifier keys neither extend nor reset string buffers (Shift is
        // legitimately pressed mid-word for capitals). They also arrive as
        // flagsChanged events whose NSEvent has no `characters`.
        if KeyboardKeyCodeMap.isModifierKeyID(keyID) { return }

        // Get the printable characters this key event would insert into a text field.
        // NSEvent may be nil for synthetic events; in that case fall back to keyID.
        // NOTE: NSEvent.characters raises for non-key events, so only read it
        // for keyDown/keyUp events.
        // Use cached NSEvent from handle() to avoid redundant CGEvent→NSEvent bridging.
        let nsEvent = cachedNSEvent ?? NSEvent(cgEvent: event)
        let characters: String
        if let nsEvent, nsEvent.type == .keyDown || nsEvent.type == .keyUp {
            characters = nsEvent.characters ?? ""
        } else {
            characters = ""
        }

        let isBackspace = (keyID == "delete")

        // Determine printability. Backspace is handled separately below.
        let isPrintable: Bool
        if isBackspace {
            isPrintable = false
        } else {
            let isModifier = KeyboardKeyCodeMap.isModifierKeyID(keyID)
            let isNavOrFunction = Self.stringTriggerNonPrintableKeyIDs.contains(keyID)
            let hasPrintableText = !characters.isEmpty
            isPrintable = !isModifier && !isNavOrFunction && hasPrintableText
        }
        let resetAll = !isPrintable && !isBackspace

        for route in routing.stringTriggers {
            let manipulator = routing[route]
            for group in route.triggerGroups {
                guard let stringTrigger = group.trigger.stringTrigger, stringTrigger.isValid else { continue }
                guard allConditionsMet(group.conditions) else {
                    resetStringBuffer(for: manipulator.id)
                    continue
                }

                // App-specific string trigger: if an app bundle ID is configured,
                // only accumulate/fire when that application is frontmost.
                if !stringTrigger.appBundleID.isEmpty {
                    let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
                    if cachedFrontmostApp == nil { cachedFrontmostApp = app }
                    guard app?.bundleIdentifier?.lowercased() == stringTrigger.appBundleID.lowercased() else {
                        resetStringBuffer(for: manipulator.id)
                        continue
                    }
                }

                if resetAll {
                    resetStringBuffer(for: manipulator.id)
                    continue
                }

                // Backspace removes the last character from the buffer.
                if isBackspace {
                    if var buffer = stringInputBuffer[manipulator.id], !buffer.isEmpty {
                        buffer.removeLast()
                        if buffer.isEmpty {
                            resetStringBuffer(for: manipulator.id)
                        } else {
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        }
                    }
                    continue
                }

                // Append the actual typed character(s) to the buffer.
                var buffer = stringInputBuffer[manipulator.id] ?? ""
                buffer += characters

                let target = stringTrigger.string
                guard !target.isEmpty else { continue }

                let matched: Bool
                switch stringTrigger.matchMode {
                case .fullMatch:
                    matched = (buffer == target)
                case .prefix:
                    matched = buffer.hasPrefix(target) && buffer.count >= target.count
                case .anyMatch:
                    matched = buffer.contains(target) && buffer.count >= target.count
                }

                if matched {
                    let clearOnMatch = stringTrigger.clearOnMatch
                    switch stringTrigger.matchMode {
                    case .fullMatch:
                        if buffer == target {
                            if clearOnMatch { resetStringBuffer(for: manipulator.id) }
                            executeStringTriggerFire(for: manipulator, target: target)
                        } else {
                            resetStringBuffer(for: manipulator.id)
                        }
                    case .prefix:
                        if buffer.count >= target.count {
                            if clearOnMatch { resetStringBuffer(for: manipulator.id) }
                            executeStringTriggerFire(for: manipulator, target: target)
                        } else {
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        }
                    case .anyMatch:
                        if buffer.count >= target.count {
                            if clearOnMatch { resetStringBuffer(for: manipulator.id) }
                            executeStringTriggerFire(for: manipulator, target: target)
                        } else {
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        }
                    }
                } else {
                    // No match — decide how to handle the stale buffer.
                    switch stringTrigger.matchMode {
                    case .fullMatch:
                        let trimmed = trimmingSuffixToMatch(buffer, target: target)
                        if trimmed != buffer {
                            if trimmed.isEmpty {
                                resetStringBuffer(for: manipulator.id)
                            } else {
                                stringInputBuffer[manipulator.id] = trimmed
                                resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                            }
                        } else if buffer.count < target.count && target.hasPrefix(buffer) {
                            // Buffer is a prefix of the target — keep accumulating
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        } else {
                            resetStringBuffer(for: manipulator.id)
                        }
                    case .prefix:
                        if buffer.count < target.count {
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        } else {
                            resetStringBuffer(for: manipulator.id)
                        }
                    case .anyMatch:
                        if buffer.count < target.count {
                            stringInputBuffer[manipulator.id] = buffer
                            resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                        } else {
                            let trimmed = trimmingSuffixToMatch(buffer, target: target)
                            if trimmed != buffer {
                                if trimmed.isEmpty {
                                    resetStringBuffer(for: manipulator.id)
                                } else {
                                    stringInputBuffer[manipulator.id] = trimmed
                                    resetStringTriggerTimer(for: manipulator.id, timeout: stringTrigger.timeoutSeconds)
                                }
                            } else {
                                resetStringBuffer(for: manipulator.id)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Trim the buffer to the longest suffix that forms a prefix of the target.
    /// E.g. target="the", buffer="breathe" → "the" (suffix "the" is prefix of "the")
    private func trimmingSuffixToMatch(_ buffer: String, target: String) -> String {
        guard !buffer.isEmpty, !target.isEmpty else { return "" }
        let bufChars = Array(buffer)
        let targetChars = Array(target)
        // Try increasingly short suffixes from longest to shortest.
        // Use Character array comparison to avoid O(n) String allocations per iteration.
        for start in bufChars.indices {
            let suffixLen = bufChars.count - start
            if suffixLen > targetChars.count { continue }
            // Check if target starts with this suffix
            let suffix = bufChars[start...]
            var matches = true
            for (i, ch) in suffix.enumerated() {
                if targetChars[i] != ch { matches = false; break }
            }
            if matches {
                return String(suffix)
            }
        }
        return ""
    }

    private func executeStringTriggerFire(for manipulator: Manipulator, target: String) {
        DispatchQueue.main.async { [weak self] in
            self?.executeFire(for: manipulator, keyID: "string:\(target)", keyType: .keyboard, proxy: nil)
        }
    }

    private func resetStringBuffer(for id: UUID) {
        stringInputBuffer.removeValue(forKey: id)
        stringInputTimers[id]?.cancel()
        stringInputTimers.removeValue(forKey: id)
    }

    private func resetStringTriggerTimer(for id: UUID, timeout: Double) {
        stringInputTimers[id]?.cancel()
        let timeoutNs = UInt64(max(timeout, 0.1) * 1_000_000_000)
        stringInputTimers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.resetStringBuffer(for: id)
            }
        }
    }

    private func cancelAllStringTimers() {
        for (_, task) in stringInputTimers {
            task.cancel()
        }
        stringInputTimers.removeAll()
    }

    // MARK: - Consumer key dispatch

    private func dispatchConsumerKeyDown(consumerKeyID: String, event: CGEvent) -> Unmanaged<CGEvent>? {
        for route in routing.consumer {
            let manipulator = routing[route]
            guard let group = route.triggerGroups.first(where: { group in
                group.trigger.keyType == .consumer
                && group.trigger.steps.first?.key == consumerKeyID
                && allConditionsMet(group.conditions)
            }) else { continue }

            executeFire(for: manipulator, keyID: consumerKeyID, keyType: group.trigger.keyType)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Mouse dispatch

    private func handleMouseDown(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = pointingButton(for: type, event: event)
        guard let buttonID = button?.rawValue else { return Unmanaged.passUnretained(event) }

        // Check mouse_basic manipulators
        for route in routing.pointing where routing[route].manipulatorType == .mouseBasic {
            let manipulator = routing[route]
            if route.triggerGroups.contains(where: { group in
                allConditionsMet(group.conditions) && group.trigger.steps.first?.key == buttonID
            }) {
                executeFire(for: manipulator, keyID: buttonID, keyType: .pointing)
                return nil
            }
        }

        // Check regular pointing triggers
        for route in routing.pointing {
            let manipulator = routing[route]
            guard route.triggerGroups.contains(where: { group in
                group.trigger.keyType == .pointing
                && group.trigger.steps.first?.key == buttonID
                && allConditionsMet(group.conditions)
            }) else { continue }
            executeFire(for: manipulator, keyID: buttonID, keyType: .pointing)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleMouseUp(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        let button = pointingButton(for: type, event: event)
        guard let buttonID = button?.rawValue else { return Unmanaged.passUnretained(event) }

        for id in activePresses.keys.filter({ activePresses[$0]?.keyID == buttonID }) {
            resolvePress(manipulatorID: id, with: .released)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseMotionToScroll(event: CGEvent, proxy: CGEventTapProxy?) -> Unmanaged<CGEvent>? {
        // Check mouse_motion_to_scroll manipulators
        for route in routing.mouseMotionToScroll {
            let manipulator = routing[route]
            guard allConditionsMet(manipulator.conditions) else { continue }
            // This manipulator type swaps the event meaning: mouse movement becomes scroll
            let speed = manipulator.parameters.mouseMotionToScrollSpeed
            let dx = event.getIntegerValueField(.mouseEventDeltaX)
            let dy = event.getIntegerValueField(.mouseEventDeltaY)
            guard dx != 0 || dy != 0 else { continue }

            let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
            if let scrollEvent {
                scrollEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy) * speed)
                scrollEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx) * speed)
                scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy) * speed)
                scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx) * speed)
                postEvent(scrollEvent, proxy: proxy)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Simultaneous (chord) triggers

    private func advanceSimultaneousTrigger(_ manipulator: Manipulator, trigger: ManipulatorTrigger, groupIndex: Int, keyID: String, flags: CGEventFlags, proxy: CGEventTapProxy?) -> Bool {
        guard let simultaneous = trigger.simultaneous, simultaneous.isValid else { return false }

        let simKeys = simultaneous.keys
        guard simKeys.contains(where: { $0.key == keyID }) else { return false }
        let stateKey = triggerGroupKey(manipulatorID: manipulator.id, groupIndex: groupIndex)

        var state = simultaneousStates[stateKey] ?? SimultaneousState(
            manipulatorID: manipulator.id,
            heldKeys: Set<String>(),
            downTimes: [:]
        )

        state.heldKeys.insert(keyID)
        state.downTimes[keyID] = eventTimestamp
        simultaneousStates[stateKey] = state

        // Check if all keys are held (with matching modifiers)
        let allHeld = simKeys.allSatisfy { keyStep in
            state.heldKeys.contains(keyStep.key)
        }

        if allHeld {
            // Check key down order if strict
            let options = simultaneous.options
            if options.keyDownOrder != .insensitive {
                let downOrder = state.downTimes.sorted { $0.value < $1.value }.map(\.key)
                let expectedOrder = simKeys.map(\.key)
                let matches: Bool
                switch options.keyDownOrder {
                case .insensitive:
                    matches = true
                case .strict:
                    matches = downOrder == expectedOrder
                case .strictInverse:
                    matches = downOrder == expectedOrder.reversed()
                }
                guard matches else { return false }
            }

            // Fire the manipulator
            simultaneousStates.removeValue(forKey: stateKey)
            executeFire(for: manipulator, keyID: simKeys.map(\.key).joined(separator: "+"), keyType: .keyboard, proxy: proxy)

            // If there are to_after_key_up actions, schedule them
            if !options.toAfterKeyUp.isEmpty {
                // Store the simultaneous state so we can fire after-key-up when keys come up
                // For now, execute the after-key-up actions' fire mode
            }

            return !manipulator.actions.contains(where: { $0.kind == .disable })
        }

        // Check timeout
        let oldest = state.downTimes.values.min() ?? eventTimestamp
        if eventTimestamp.timeIntervalSince(oldest) > manipulator.parameters.sequenceTimeout {
            simultaneousStates.removeValue(forKey: stateKey)
        }

        // Swallow the key while we wait for the remaining chord keys.
        // Without this, the first letter would pass through to the system.
        return true
    }

    private func checkSimultaneousKeyUp(_ manipulator: Manipulator, keyID: String, groupIndex: Int) {
        let stateKey = triggerGroupKey(manipulatorID: manipulator.id, groupIndex: groupIndex)
        guard var state = simultaneousStates[stateKey] else { return }
        state.heldKeys.remove(keyID)
        state.downTimes.removeValue(forKey: keyID)

        if state.heldKeys.isEmpty {
            simultaneousStates.removeValue(forKey: stateKey)
        } else {
            simultaneousStates[stateKey] = state
        }
    }

    // MARK: - String (typed) trigger handling

    /// Processes the current key-down event for typed-string triggers.
    /// Accumulates printable characters into per-manipulator buffers and fires
    /// actions when the buffer matches the configured trigger string.
    ///
    /// Typed-string triggers never swallow the original event — the typed
    /// characters always pass through to the system so that autocorrect-style
    /// actions can undo and retype the corrected text.
    // MARK: - Hot‑key multi‑tap handling

    /// Processes a key‑down event for a manipulator that has a `HotKeyTriggerConfig`.
    /// Returns `true` if the event should be swallowed (either because the multi‑tap
    /// sequence is in‑progress or because it just completed).
    private func handleMultiTap(for manipulator: Manipulator, keyID: String, hotKey: HotKeyTriggerConfig, flags: CGEventFlags, proxy: CGEventTapProxy?, groupIndex: Int) -> Bool {
        let now = eventTimestamp
        let tapKey = triggerGroupKey(manipulatorID: manipulator.id, groupIndex: groupIndex)
        var progress = multiTapProgress[tapKey]

        // Reset if the tapped key changed or the previous tap timed out
        if let p = progress, (p.keyID != keyID || now.timeIntervalSince(p.lastTapTime) > Double(hotKey.tapTimeoutMilliseconds) / 1000.0) {
            p.timerTask?.cancel()
            progress = nil
        }

        if progress == nil {
            progress = MultiTapProgress(manipulatorID: manipulator.id, keyID: keyID, count: 0, lastTapTime: now)
        }

        progress!.count += 1
        progress!.lastTapTime = now

        let currentCount = progress!.count

        if currentCount >= hotKey.tapCount {
            if hotKey.holdRequired {
                // ── Hold‑required path ──────────────────────────────
                multiTapProgress.removeValue(forKey: tapKey)
                progress!.timerTask?.cancel()

                // Cancel any previous pending hold for this trigger group
                multiTapPendingHolds[tapKey]?.cancel()

                let holdNs = UInt64(max(hotKey.holdThresholdMilliseconds, 0)) * 1_000_000
                let holdTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: holdNs)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        guard self.multiTapPendingHolds[tapKey] != nil else { return }
                        self.multiTapPendingHolds.removeValue(forKey: tapKey)
                        // Hold threshold satisfied — fire the manipulator
                        self.executeFire(for: manipulator, keyID: keyID, keyType: manipulator.trigger.keyType, proxy: proxy, tapCount: hotKey.tapCount)
                    }
                }
                multiTapPendingHolds[tapKey] = holdTask
                return true
            } else {
                // ── No hold required — fire immediately ─────────────
                defer {
                    multiTapProgress.removeValue(forKey: tapKey)
                }
                progress!.timerTask?.cancel()
                executeFire(for: manipulator, keyID: keyID, keyType: manipulator.trigger.keyType, proxy: proxy, tapCount: hotKey.tapCount)
                return true
            }
        } else {
            // ── Still counting — wait for more taps ────────────────
            let timeout = Double(hotKey.tapTimeoutMilliseconds) / 1000.0
            let task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                _ = await MainActor.run {
                    self?.multiTapProgress.removeValue(forKey: tapKey)
                }
            }
            progress!.timerTask = task
            multiTapProgress[tapKey] = progress!
            return true
        }
    }

    // MARK: - Press handling

    private enum PressResolution {
        case released
        case interrupted
    }

    private func executeFire(for manipulator: Manipulator, keyID: String, keyType: TriggerKeyType, proxy: CGEventTapProxy? = nil, tapCount: Int? = nil) {
        for action in manipulator.actions where action.fireMode == .onKeyDown {
            guard actionConditionsMet(action) else { continue }
            if let tapCount, action.tapCount != tapCount { continue }
            onExecuteAction?(manipulator, action, proxy)
            if action.kind == .halt { break }
        }

        let hasDeferred = manipulator.actions.contains { $0.fireMode != .onKeyDown }
        guard hasDeferred else { return }

        guard manipulator.trigger.steps.count <= 1 || manipulator.trigger.simultaneous != nil else { return }

        let press = ActivePress(manipulator: manipulator, keyID: keyID, keyType: keyType, downTime: eventTimestamp, proxy: proxy)
        activePresses[manipulator.id] = press
        scheduleTimers(for: manipulator)
    }

    private func scheduleTimers(for manipulator: Manipulator) {
        let id = manipulator.id
        let params = manipulator.parameters
        var timers: [ActionFireMode: Task<Void, Never>] = [:]

        if manipulator.actions.contains(where: { $0.fireMode == .ifAlone })
            || manipulator.actions.contains(where: { $0.fireMode == .ifHeldDown }) {
            let threshold = max(0, params.toIfHeldDownThresholdMilliseconds)
            timers[.ifHeldDown] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(threshold) * 1_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.fireHeldDown(for: id) }
            }
        }

        if manipulator.actions.contains(where: { $0.fireMode == .ifHeldDownInvoked })
            || manipulator.actions.contains(where: { $0.fireMode == .ifHeldDownCanceled }) {
            let delay = max(0, params.toDelayActionDelayMilliseconds)
            if delay > 0 {
                timers[.ifHeldDownInvoked] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.fireDelayedInvoked(for: id) }
                }
            } else {
                Task { await MainActor.run { self.fireDelayedInvoked(for: id) } }
            }
        }

        if !timers.isEmpty {
            pressTimers[id] = timers
        }
    }

    @MainActor private func fireHeldDown(for id: UUID) {
        guard activePresses[id] != nil else { return }
        guard let manipulator = manipulators.first(where: { $0.id == id }) else { return }
        let activeTapCount = manipulator.trigger.hotKey?.tapCount
        for action in manipulator.actions where action.fireMode == .ifHeldDown {
            guard actionConditionsMet(action) else { continue }
            if let activeTapCount, action.tapCount != activeTapCount { continue }
            onExecuteAction?(manipulator, action, nil)
        }
    }

    @MainActor private func fireDelayedInvoked(for id: UUID) {
        guard activePresses[id] != nil else { return }
        guard let manipulator = manipulators.first(where: { $0.id == id }) else { return }
        let activeTapCount = manipulator.trigger.hotKey?.tapCount
        for action in manipulator.actions where action.fireMode == .ifHeldDownInvoked {
            guard actionConditionsMet(action) else { continue }
            if let activeTapCount, action.tapCount != activeTapCount { continue }
            onExecuteAction?(manipulator, action, nil)
        }
        if let timers = pressTimers[id] {
            timers[.ifHeldDownInvoked]?.cancel()
            pressTimers[id]?[.ifHeldDownInvoked] = nil
        }
    }

    private func resolvePress(manipulatorID id: UUID, with resolution: PressResolution) {
        defer {
            cancelPressTimers(for: id)
            activePresses.removeValue(forKey: id)
            pressTimers.removeValue(forKey: id)
        }
        guard let press = activePresses[id] else { return }
        let manipulator = press.manipulator
        let elapsed = eventTimestamp.timeIntervalSince(press.downTime) * 1000.0
        let params = manipulator.parameters

        // When the manipulator uses a hot‑key trigger, only actions whose
        // `tapCount` matches the trigger's configured `tapCount` should fire.
        let activeTapCount = manipulator.trigger.hotKey?.tapCount

        switch resolution {
        case .released:
            for action in manipulator.actions where action.fireMode == .afterKeyUp {
                guard actionConditionsMet(action) else { continue }
                if let activeTapCount, action.tapCount != activeTapCount { continue }
                onExecuteAction?(manipulator, action, press.proxy)
            }
            if elapsed <= Double(params.toIfAloneTimeoutMilliseconds) {
                for action in manipulator.actions where action.fireMode == .ifAlone {
                    guard actionConditionsMet(action) else { continue }
                    if let activeTapCount, action.tapCount != activeTapCount { continue }
                    onExecuteAction?(manipulator, action, press.proxy)
                }
            }
        case .interrupted:
            for action in manipulator.actions where action.fireMode == .ifHeldDownCanceled {
                guard actionConditionsMet(action) else { continue }
                if let activeTapCount, action.tapCount != activeTapCount { continue }
                onExecuteAction?(manipulator, action, nil)
            }
            for action in manipulator.actions where action.fireMode == .ifOtherKeyPressed {
                guard actionConditionsMet(action) else { continue }
                if let activeTapCount, action.tapCount != activeTapCount { continue }
                onExecuteAction?(manipulator, action, nil)
            }
        }
    }

    private func cancelPressTimers(for id: UUID) {
        if let timers = pressTimers[id] {
            for (_, task) in timers { task.cancel() }
        }
    }

    private func cancelAllActivePresses() {
        for id in activePresses.keys {
            cancelPressTimers(for: id)
        }
        activePresses.removeAll()
        pressTimers.removeAll()
    }

    private func cancelAllMultiTapTimers() {
        for (_, progress) in multiTapProgress {
            progress.timerTask?.cancel()
        }
        multiTapProgress.removeAll()
    }

    private func cancelAllPendingHolds() {
        for (_, task) in multiTapPendingHolds {
            task.cancel()
        }
        multiTapPendingHolds.removeAll()
    }

    // MARK: - Action side effects (halt, holdDown, lazy, repeat)

    private func shouldHalt(for manipulator: Manipulator) -> Bool {
        manipulator.actions.contains { $0.kind == .halt && $0.fireMode == .onKeyDown }
    }

    private func actionConditionsMet(_ action: Action) -> Bool {
        action.actionConditions.allSatisfy(conditionMet)
    }

    // MARK: - Sequence triggers

    private struct SequenceProgress {
        var index: Int
        var lastTime: Date
    }

    private enum SequenceAdvanceResult {
        case noMatch
        case advanced
        case fired
    }

    private func advanceSequenceTrigger(_ manipulator: Manipulator, trigger: ManipulatorTrigger, groupIndex: Int, keyID: String, flags: CGEventFlags) -> SequenceAdvanceResult {
        let steps = trigger.steps
        guard !steps.isEmpty else { return .noMatch }
        let seqKey = triggerGroupKey(manipulatorID: manipulator.id, groupIndex: groupIndex)

        let now = eventTimestamp
        var progress = sequenceProgress[seqKey] ?? SequenceProgress(index: 0, lastTime: .distantPast)
        if now.timeIntervalSince(progress.lastTime) > manipulator.parameters.sequenceTimeout {
            progress.index = 0
        }

        let expected = steps[progress.index]
        guard expected.key == keyID, modifiersMatch(expected, flags: flags) else {
            if progress.index > 0,
               steps[0].key == keyID,
               modifiersMatch(steps[0], flags: flags) {
                sequenceProgress[seqKey] = SequenceProgress(index: 1, lastTime: now)
                return .advanced
            }
            sequenceProgress[seqKey] = nil
            return .noMatch
        }

        progress.index += 1
        if progress.index == steps.count {
            sequenceProgress[seqKey] = nil
            return .fired
        } else {
            sequenceProgress[seqKey] = SequenceProgress(index: progress.index, lastTime: now)
            return .advanced
        }
    }

    // MARK: - Conditions

    /// Evaluate all conditions with short-circuit ordering: cheap → medium → expensive.
    /// Single-pass: conditions are bucketed by tier and evaluated in priority order.
    /// Results are cached per event cycle to avoid redundant evaluation across routing passes.
    private func allConditionsMet(_ conditions: [Condition]) -> Bool {
        // Partition into three tiers in a single pass
        var cheap: [Condition] = []
        var medium: [Condition] = []
        var expensive: [Condition] = []
        cheap.reserveCapacity(conditions.count)
        medium.reserveCapacity(conditions.count)
        expensive.reserveCapacity(conditions.count)
        for condition in conditions {
            if Self.cheapConditionKinds.contains(condition.kind) {
                cheap.append(condition)
            } else if Self.mediumConditionKinds.contains(condition.kind) {
                medium.append(condition)
            } else {
                expensive.append(condition)
            }
        }
        // Evaluate tiers in priority order with short-circuit
        for condition in cheap where !evaluateConditionCached(condition) { return false }
        for condition in medium where !evaluateConditionCached(condition) { return false }
        for condition in expensive where !evaluateConditionCached(condition) { return false }
        return true
    }

    /// Evaluate a single condition against current state.
    /// Exposed as internal for palette / external trigger use.
    func evaluateCondition(_ condition: Condition) -> Bool {
        conditionMet(condition)
    }

    /// Evaluates a condition with per-event caching.
    private func evaluateConditionCached(_ condition: Condition) -> Bool {
        if let cached = eventConditionCache[condition.id] {
            return cached
        }
        let result = conditionMet(condition)
        eventConditionCache[condition.id] = result
        return result
    }

    func conditionMet(_ condition: Condition) -> Bool {
        switch condition.kind {
        case .frontmostApp:
            let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
            if cachedFrontmostApp == nil { cachedFrontmostApp = app }
            return compare(app?.bundleIdentifier ?? "", condition.op, condition.target)
        case .frontmostAppName:
            let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
            if cachedFrontmostApp == nil { cachedFrontmostApp = app }
            return compare(app?.localizedName ?? "", condition.op, condition.target)
        case .inputSource:
            return compare(currentInputSourceID(), condition.op, condition.target)
        case .device:
            return false
        case .variable:
            return compare(variables[condition.target] ?? "", condition.op, condition.value)
        case .globalVariable:
            return compare(globalVariables[condition.target] ?? "", condition.op, condition.value)
        case .keyboardType:
            return compare(currentKeyboardLayoutName(), condition.op, condition.target)
        case .deviceExists:
            return false
        case .expression:
            return evaluateExpression(condition.target)
        case .eventChanged:
            return true
        case .window:
            return windowConditionMet(condition)
        case .runningCondition:
            return isAppRunning(target: condition.target)
        case .token:
            let resolved = resolveToken(condition.target)
            return compare(resolved, condition.op, condition.value)
        case .namedClipboard:
            return compare(namedClipboards[condition.target] ?? "", condition.op, condition.value)
        case .screen:
            return screenConditionMet(condition)
        case .pixelCondition:
            return pixelConditionMet(condition)
        }
    }

    func compare(_ actual: String, _ op: ComparisonOp, _ expected: String) -> Bool {
        switch op {
        case .isEqual: return actual.lowercased() == expected.lowercased()
        case .isNotEqual: return actual.lowercased() != expected.lowercased()
        case .contains: return actual.lowercased().contains(expected.lowercased())
        case .matches:
            return (actual.range(of: expected, options: [.regularExpression, .caseInsensitive]) != nil)
        }
    }

    func modifiersMatch(_ shortcut: KeyShortcut, flags: CGEventFlags) -> Bool {
        let mandatoryFlags = shortcut.mandatoryModifiers.compactMap { $0.cgFlag }.reduce(into: CGEventFlags()) { $0.insert($1) }
        let optionalFlags = shortcut.optionalModifiers.compactMap { $0.cgFlag }.reduce(into: CGEventFlags()) { $0.insert($1) }

        // All mandatory modifiers must be present in flags
        let hasAllMandatory = mandatoryFlags.isSubset(of: flags)

        // Extra held modifiers (beyond mandatory + optional) block the match:
        // ⌘⇧A must not fire a plain ⌘A trigger. Only the four primary
        // modifier masks are checked; alpha-shift/fn/numpad bits are ignored.
        let checkedMasks: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        var allowedFlags = mandatoryFlags.union(optionalFlags)
        // If the trigger key itself is a modifier (e.g. remapping left_command),
        // pressing it sets its own mask — exempt it from the extra-flag check.
        if KeyboardKeyCodeMap.isModifierKeyID(shortcut.key) {
            for mod in ModifierKey.allCases where KeyboardKeyCodeMap.modifierKeyIDs(for: mod).contains(shortcut.key) {
                if let flag = mod.cgFlag { allowedFlags.insert(flag) }
            }
        }
        let extraFlags = flags.intersection(checkedMasks).subtracting(allowedFlags)
        let hasNoExtra = extraFlags.isEmpty

        // Check specific modifier key identities (left/right variants) using bitmask
        if !shortcut.mandatoryModifiers.isEmpty {
            let allHeld = shortcut.mandatoryModifiers.allSatisfy { mod in
                let modBits = HeldModifierMask.bits(for: mod)
                return !heldModifierKeys.intersection(modBits).isEmpty
            }
            if !allHeld { return false }
        }

        return hasAllMandatory && hasNoExtra
    }

    private func currentInputSourceID() -> String {
        if let cached = cachedInputSourceID { return cached }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        let result = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        cachedInputSourceID = result
        return result
    }

    private func currentKeyboardLayoutName() -> String {
        let id = currentInputSourceID()
        if id.contains("ANSI") { return "ansi" }
        if id.contains("IS") && !id.contains("ISL") { return "iso" }
        if id.contains("JIS") { return "jis" }
        return id
    }



    private func evaluateExpression(_ expression: String) -> Bool {
        // Try != first (longer operator, must check before ==)
        if let notRange = expression.range(of: "!=") {
            let varName = String(expression[expression.startIndex..<notRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let expected = String(expression[notRange.upperBound..<expression.endIndex]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
            return variables[varName] != expected
        }
        if let eqRange = expression.range(of: "==") {
            let varName = String(expression[expression.startIndex..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let expected = String(expression[eqRange.upperBound..<expression.endIndex]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
            return variables[varName] == expected
        }
        return false
    }

    // MARK: - Token resolution

    /// Resolve a token expression to its current string value.
    /// Supported token families:
    ///   - System:* (CurrentDate, CurrentTime, UserName, FullUserName, HostName, OSVersion)
    ///   - Front:* (Application, BundleID, Name)
    ///   - FrontBrowser:* (URL, Title)
    private func resolveToken(_ token: String) -> String {
        switch token {
        case "System:CurrentDate":
            return Self.isoDateFormatter.string(from: Date())
        case "System:CurrentTime":
            return Self.timeFormatter.string(from: Date())
        case "System:CurrentDateTime":
            return Self.dateTimeFormatter.string(from: Date())
        case "System:UserName":
            return NSUserName()
        case "System:FullUserName":
            return NSFullUserName()
        case "System:HostName":
            return ProcessInfo.processInfo.hostName
        case "System:OSVersion":
            let info = ProcessInfo.processInfo.operatingSystemVersion
            return "\(info.majorVersion).\(info.minorVersion).\(info.patchVersion)"
        case "Front:Application", "Front:Name":
            let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
            if cachedFrontmostApp == nil { cachedFrontmostApp = app }
            return app?.localizedName ?? ""
        case "Front:BundleID":
            let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
            if cachedFrontmostApp == nil { cachedFrontmostApp = app }
            return app?.bundleIdentifier ?? ""
        case "FrontBrowser:URL":
            return getFrontBrowserURL()
        case "FrontBrowser:Title":
            return getFrontBrowserTitle()
        default:
            return token
        }
    }

    /// Get the URL from the frontmost browser via Accessibility API.
    /// Works with Safari, Chrome, Firefox, Brave, Edge, Arc, Orion.
    private func getFrontBrowserURL() -> String {
        guard let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication else { return "" }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try focused element first (Chrome, Firefox, Brave, Edge)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused = focused {
            let focusedElement: AXUIElement = unsafeBitCast(focused, to: AXUIElement.self)
            var url: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedElement, "AXURL" as CFString, &url) == .success,
               let urlString = url as? String, !urlString.isEmpty {
                return urlString
            }
        }

        // Try main window (Safari, Orion)
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &window) == .success,
           let windowVal = window {
            let windowElement: AXUIElement = unsafeBitCast(windowVal, to: AXUIElement.self)
            // Attempt AXURL on the window itself
            var windowURL: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, "AXURL" as CFString, &windowURL) == .success,
               let urlString = windowURL as? String, !urlString.isEmpty {
                return urlString
            }
            // Try the document (Safari)
            var doc: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXDocumentAttribute as CFString, &doc) == .success,
               let docVal = doc {
                let docElement: AXUIElement = unsafeBitCast(docVal, to: AXUIElement.self)
                var docURL: CFTypeRef?
                if AXUIElementCopyAttributeValue(docElement, "AXURL" as CFString, &docURL) == .success,
                   let urlString = docURL as? String, !urlString.isEmpty {
                    return urlString
                }
            }
        }

        return ""
    }

    /// Get the page title from the frontmost browser via Accessibility API.
    private func getFrontBrowserTitle() -> String {
        guard let app = cachedFrontmostApp ?? NSWorkspace.shared.frontmostApplication else { return "" }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try main window title (works for most browsers)
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &window) == .success,
           let windowVal = window {
            let windowElement: AXUIElement = unsafeBitCast(windowVal, to: AXUIElement.self)
            var title: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
               let titleString = title as? String, !titleString.isEmpty {
                return titleString
            }
        }

        return ""
    }

    private func isAppRunning(target: String) -> Bool {
        let lowered = target.lowercased()
        // Refresh cache if stale
        let now = eventTimestamp
        if now.timeIntervalSince(runningAppsCacheTime) >= runningAppsCacheTTL {
            cachedRunningApps = Set(
                NSWorkspace.shared.runningApplications.compactMap { app in
                    if let bid = app.bundleIdentifier?.lowercased() { return bid }
                    if let name = app.localizedName?.lowercased() { return name }
                    return nil
                }
            )
            runningAppsCacheTime = now
        }
        return cachedRunningApps.contains(lowered)
    }

    // MARK: - Pixel color condition

    /// Background task queue for pixel capture so the event tap never blocks.
    private let pixelCaptureQueue = DispatchQueue(label: "com.anvil.pixel-capture", qos: .utility)

    /// Pixel capture is dispatched async and the result is cached. The first evaluation
    /// for a given coordinate may return stale data; the cache is refreshed on a background timer.
    private func pixelConditionMet(_ condition: Condition) -> Bool {
        let parts = condition.target.components(separatedBy: ",")
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return false
        }

        let cacheKey = "\(Int(x)),\(Int(y))"
        let now = eventTimestamp

        // Return cached value if fresh enough
        if let cached = pixelColorCache[cacheKey], now.timeIntervalSince(cached.1) < pixelColorCacheTTL {
            return compare(cached.0, condition.op, condition.value)
        }

        // Cache is stale — trigger an async refresh but return the stale value for now
        // so the event tap never blocks.
        pixelCaptureQueue.async { [weak self] in
            guard let self else { return }
            if let hex = self.capturePixelColor(x: x, y: y) {
                DispatchQueue.main.async {
                    self.pixelColorCache[cacheKey] = (hex, Date())
                }
            }
        }

        // Return the stale cached value if available, otherwise false
        if let cached = pixelColorCache[cacheKey] {
            return compare(cached.0, condition.op, condition.value)
        }

        return false
    }

    /// Capture a single pixel's hex color (runs on background queue).
    private func capturePixelColor(x: Double, y: Double) -> String? {
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let quartzPoint = CGPoint(x: x, y: globalHeight - y)
        let captureRect = CGRect(x: quartzPoint.x, y: quartzPoint.y, width: 1, height: 1)

        var resultImage: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(in: captureRect) { image, _ in
            resultImage = image
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)

        guard let image = resultImage else { return nil }
        guard let dataProvider = image.dataProvider,
              let pixelData = dataProvider.data,
              let data = CFDataGetBytePtr(pixelData) else {
            return nil
        }
        let r = data[0]
        let g = data[1]
        let b = data[2]
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // MARK: - Window condition

    /// Returns cached or freshly-fetched window property, respecting cache TTL.
    /// This avoids calling expensive AXUIElementCopyAttributeValue on every key event.
    private func cachedWindowProperty(_ key: String, fetch: () -> String) -> String {
        let now = eventTimestamp
        if now.timeIntervalSince(windowPropertyCacheTime) < windowPropertyCacheTTL {
            if let cached = windowPropertyCache[key] {
                return cached
            }
        }
        let value = fetch()
        windowPropertyCache[key] = value
        windowPropertyCacheTime = now
        return value
    }

    func windowConditionMet(_ condition: Condition) -> Bool {
        let lowered = condition.target.lowercased()

        // Check window state keywords: minimized, hidden, visible
        if lowered == "minimized" || lowered == "hidden" || lowered == "visible" {
            let isMinimized = isFrontmostWindowMinimized()
            let isHidden = isFrontmostWindowHidden()
            let actualState: String
            if isMinimized {
                actualState = "minimized"
            } else if isHidden {
                actualState = "hidden"
            } else {
                actualState = "visible"
            }
            return compare(actualState, condition.op, condition.target)
        }

        // Otherwise match against the frontmost window's title
        let title = frontmostWindowTitle()
        return compare(title, condition.op, condition.target)
    }

    /// Returns the title of the frontmost window using the Accessibility API.
    /// Results are cached for `windowPropertyCacheTTL` seconds.
    private func frontmostWindowTitle() -> String {
        cachedWindowProperty("title") {
            guard let app = NSWorkspace.shared.frontmostApplication else { return "" }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let focusedResult = AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &value)
            if focusedResult == .success, let focusedWindowVal = value {
                let focusedWindow: AXUIElement = unsafeBitCast(focusedWindowVal, to: AXUIElement.self)
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(focusedWindow, "AXTitle" as CFString, &title)
                if let t = title as? String, !t.isEmpty { return t }
            }
            var windows: CFTypeRef?
            let winResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windows)
            guard winResult == .success, let windowArray = windows as? [AXUIElement], let firstWindow = windowArray.first else { return "" }
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(firstWindow, "AXTitle" as CFString, &title)
            return (title as? String) ?? ""
        }
    }

    /// Returns true if the frontmost window is minimized.
    private func isFrontmostWindowMinimized() -> Bool {
        let result = cachedWindowProperty("minimized") {
            guard let app = NSWorkspace.shared.frontmostApplication else { return "false" }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let focusedResult = AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &value)
            if focusedResult == .success, let focusedWindowVal = value {
                let focusedWindow: AXUIElement = unsafeBitCast(focusedWindowVal, to: AXUIElement.self)
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(focusedWindow, "AXMinimized" as CFString, &minimized)
                return (minimized as? Bool) ?? false ? "true" : "false"
            }
            var windows: CFTypeRef?
            let winResult = AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &windows)
            guard winResult == .success, let windowArray = windows as? [AXUIElement], let firstWindow = windowArray.first else { return "false" }
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(firstWindow, "AXMinimized" as CFString, &minimized)
            return (minimized as? Bool) ?? false ? "true" : "false"
        }
        return result == "true"
    }

    /// Returns true if the frontmost application is hidden.
    private func isFrontmostWindowHidden() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return app.isHidden
    }



    // MARK: - Screen condition

    private func screenConditionMet(_ condition: Condition) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let lowered = condition.target.lowercased()

        // "primary" — matches if the current screen is the primary display
        if lowered == "primary" {
            let isPrimary = screen == NSScreen.screens.first
            return compare("\(isPrimary)", condition.op, "true")
        }

        // "retina" / "2x" — matches if screen has HiDPI backing scale
        if lowered == "retina" || lowered == "2x" {
            let isRetina = screen.backingScaleFactor > 1.0
            return compare("\(isRetina)", condition.op, "true")
        }

        // Resolution: "1920x1080" format — matches frame point dimensions
        if lowered.contains("x") {
            let parts = lowered.components(separatedBy: "x")
            if parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil {
                let frame = screen.frame
                let actual = "\(Int(frame.width))x\(Int(frame.height))"
                return compare(actual, condition.op, condition.target)
            }
        }

        return false
    }

    private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Sticky modifier

    private func applyStickyModifiers(to flags: CGEventFlags) -> CGEventFlags {
        var augmented = flags
        for (modifier, active) in stickyModifiers where active {
            if let flag = modifier.cgFlag {
                augmented.insert(flag)
            }
        }
        for modifier in lazyModifiers {
            if let flag = modifier.cgFlag {
                augmented.insert(flag)
            }
        }
        return augmented
    }

    // MARK: - Post events

    private func postEvent(_ event: CGEvent, proxy: CGEventTapProxy?) {
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Post modifier event

    private func postModifierPress(modifier: ModifierKey, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyID in KeyboardKeyCodeMap.modifierKeyIDs(for: modifier) {
            guard let keyCode = KeyboardKeyCodeMap.code(for: keyID) else { continue }
            if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) {
                event.flags = down ? (modifier.cgFlag ?? CGEventFlags()) : []
                postEvent(event, proxy: nil)
            }
        }
    }

    // MARK: - Helpers

    private func pointingButton(for type: CGEventType, event: CGEvent) -> PointingButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp: return .left
        case .rightMouseDown, .rightMouseUp: return .right
        case .otherMouseDown, .otherMouseUp:
            switch event.getIntegerValueField(.mouseEventButtonNumber) {
            case 2: return .middle
            case 3: return .back
            case 4: return .forward
            default: return .center
            }
        default: return nil
        }
    }

    private func consumerKeyID(forNSEventKeyCode keyCode: Int) -> String? {
        switch keyCode {
        case 0: return "vk_consumer_volume_up"
        case 1: return "vk_consumer_volume_down"
        case 7: return "vk_consumer_mute"
        case 2: return "vk_consumer_brightness_up"
        case 3: return "vk_consumer_brightness_down"
        default: return nil
        }
    }

    /// Map an NX_KEYTYPE value (extracted from a system-defined event's data1) to a consumer key ID.
    private func consumerKeyIDForNXKeyType(_ nxKeyType: Int32) -> String? {
        switch nxKeyType {
        case NX_KEYTYPE_SOUND_UP: return "vk_consumer_volume_up"
        case NX_KEYTYPE_SOUND_DOWN: return "vk_consumer_volume_down"
        case NX_KEYTYPE_MUTE: return "vk_consumer_mute"
        case NX_KEYTYPE_BRIGHTNESS_UP: return "vk_consumer_brightness_up"
        case NX_KEYTYPE_BRIGHTNESS_DOWN: return "vk_consumer_brightness_down"
        case NX_KEYTYPE_PLAY: return "vk_consumer_play"
        case NX_KEYTYPE_NEXT: return "vk_consumer_next"
        case NX_KEYTYPE_PREVIOUS: return "vk_consumer_prev"
        case NX_KEYTYPE_REWIND: return "vk_consumer_rewind"
        case NX_KEYTYPE_FF: return "vk_consumer_fast_forward"
        case NX_KEYTYPE_EJECT: return "vk_consumer_eject"
        case NX_KEYTYPE_POWER: return "vk_consumer_power"
        default: return nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<KeyboardRemapEngine>.fromOpaque(userInfo).takeUnretainedValue()
        return engine.handle(proxy: proxy, type: type, event: event)
    }
}
