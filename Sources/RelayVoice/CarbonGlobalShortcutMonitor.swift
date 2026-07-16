import Carbon.HIToolbox
import Foundation

public enum RelayGlobalShortcutEvent: Equatable, Sendable {
    case pressed
    case released
}

@MainActor
public protocol RelayGlobalShortcutMonitoring: AnyObject {
    func start(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws

    func stop()
}

public enum RelayGlobalShortcutMonitorError:
    Error,
    Equatable,
    Sendable
{
    case eventHandlerInstallationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)
}

extension RelayGlobalShortcutMonitorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallationFailed(status):
            "Relay could not install its shortcut handler (OSStatus \(status))."
        case let .hotKeyRegistrationFailed(status):
            "Relay could not register its global shortcut (OSStatus \(status))."
        }
    }
}

@MainActor
public final class CarbonGlobalShortcutMonitor:
    RelayGlobalShortcutMonitoring
{
    private static let signature: OSType = 0x524C5956 // RLYV
    private static let identifier: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callbackBox: CarbonHotKeyCallbackBox?

    public init() {}

    public func start(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        stop()

        let callbackBox = CarbonHotKeyCallbackBox(
            signature: Self.signature,
            identifier: Self.identifier,
            handler: handler
        )
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            relayCarbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(callbackBox).toOpaque(),
            &installedHandler
        )

        guard handlerStatus == noErr, let installedHandler else {
            throw RelayGlobalShortcutMonitorError
                .eventHandlerInstallationFailed(handlerStatus)
        }

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonMask,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &registeredHotKey
        )

        guard registrationStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            throw RelayGlobalShortcutMonitorError
                .hotKeyRegistrationFailed(registrationStatus)
        }

        self.callbackBox = callbackBox
        eventHandlerRef = installedHandler
        hotKeyRef = registeredHotKey
    }

    public func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        callbackBox = nil
    }

    isolated deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

private final class CarbonHotKeyCallbackBox: @unchecked Sendable {
    private let signature: OSType
    private let identifier: UInt32
    private let handler:
        @MainActor @Sendable (RelayGlobalShortcutEvent) -> Void

    init(
        signature: OSType,
        identifier: UInt32,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) {
        self.signature = signature
        self.identifier = identifier
        self.handler = handler
    }

    func handle(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard parameterStatus == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == identifier else {
            return OSStatus(eventNotHandledErr)
        }

        let event: RelayGlobalShortcutEvent
        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            event = .pressed
        case UInt32(kEventHotKeyReleased):
            event = .released
        default:
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [handler] in
            handler(event)
        }
        return noErr
    }
}

private let relayCarbonHotKeyHandler: EventHandlerUPP = {
    _,
    eventRef,
    userData in
    guard let eventRef, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let callbackBox = Unmanaged<CarbonHotKeyCallbackBox>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return callbackBox.handle(eventRef)
}

private extension RelayShortcutModifiers {
    var carbonMask: UInt32 {
        var result: UInt32 = 0
        if contains(.command) {
            result |= UInt32(cmdKey)
        }
        if contains(.option) {
            result |= UInt32(optionKey)
        }
        if contains(.control) {
            result |= UInt32(controlKey)
        }
        if contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }
}
