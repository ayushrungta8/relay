import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
public final class AccessibilityGlobalShortcutMonitor:
    RelayGlobalShortcutMonitoring
{
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackBox: AccessibilityShortcutCallbackBox?

    public init() {}

    public func start(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        stop()

        guard AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary) else {
            throw RelayGlobalShortcutMonitorError
                .accessibilityPermissionRequired
        }

        let callbackBox = AccessibilityShortcutCallbackBox(
            shortcut: shortcut,
            handler: handler
        )
        let eventMask = Self.eventMask(
            for: [.keyDown, .keyUp, .flagsChanged]
        )
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: relayAccessibilityShortcutCallback,
            userInfo: Unmanaged.passUnretained(callbackBox).toOpaque()
        ),
        let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            throw RelayGlobalShortcutMonitorError.eventTapCreationFailed
        }

        self.callbackBox = callbackBox
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        callbackBox = nil
    }

    isolated deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private static func eventMask(
        for types: [CGEventType]
    ) -> CGEventMask {
        types.reduce(0) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }
}

private final class AccessibilityShortcutCallbackBox:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let handler:
        @MainActor @Sendable (RelayGlobalShortcutEvent) -> Void
    private var state: RelayShortcutEventState

    init(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) {
        state = RelayShortcutEventState(shortcut: shortcut)
        self.handler = handler
    }

    func handle(
        type: CGEventType,
        event: CGEvent
    ) {
        guard let input = RelayShortcutInputEvent(
            type: type,
            event: event
        ) else {
            return
        }
        let output = lock.withLock {
            state.handle(input)
        }
        guard let output else { return }
        Task { @MainActor [handler] in
            handler(output)
        }
    }
}

private let relayAccessibilityShortcutCallback: CGEventTapCallBack = {
    _,
    type,
    event,
    userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let callbackBox = Unmanaged<AccessibilityShortcutCallbackBox>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    callbackBox.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private extension RelayShortcutInputEvent {
    init?(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            self = .keyDown(
                keyCode: UInt32(
                    event.getIntegerValueField(.keyboardEventKeycode)
                ),
                modifiers: RelayShortcutModifiers(event.flags),
                isRepeat: event.getIntegerValueField(
                    .keyboardEventAutorepeat
                ) != 0
            )
        case .keyUp:
            self = .keyUp(
                keyCode: UInt32(
                    event.getIntegerValueField(.keyboardEventKeycode)
                )
            )
        case .flagsChanged:
            self = .modifiersChanged(
                RelayShortcutModifiers(event.flags)
            )
        default:
            return nil
        }
    }
}

private extension RelayShortcutModifiers {
    init(_ flags: CGEventFlags) {
        var value: RelayShortcutModifiers = []
        if flags.contains(.maskCommand) { value.insert(.command) }
        if flags.contains(.maskAlternate) { value.insert(.option) }
        if flags.contains(.maskControl) { value.insert(.control) }
        if flags.contains(.maskShift) { value.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { value.insert(.function) }
        self = value
    }
}
