import Carbon
import Foundation
import YouTubeMacCore

/// Opt-in system-wide Carbon global hotkey manager (`RegisterEventHotKey`).
/// Requires zero Accessibility permissions and unregisters all hotkeys/handlers cleanly on disable or `deinit`.
@MainActor
public final class GlobalHotKeyManager {
    private static let hotKeySignature: OSType = 0x4747594B // 'GGYK'
    nonisolated(unsafe) private static weak var activeManager: GlobalHotKeyManager?

    private static let carbonEventHandler: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
        guard let eventRef else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == GlobalHotKeyManager.hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }
        let rawID = hotKeyID.id
        Task { @MainActor in
            GlobalHotKeyManager.activeManager?.handleHotKeyID(rawID)
        }
        return noErr
    }

    nonisolated(unsafe) private var hotKeyRefs: [EventHotKeyRef] = []
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor (GlobalHotKeyAction) -> Void)?
    private var actionsByHotKeyID: [UInt32: GlobalHotKeyAction] = [:]

    public init() {}

    deinit {
        unregisterAllNonisolated()
    }

    public var isRegistered: Bool {
        !hotKeyRefs.isEmpty && eventHandlerRef != nil
    }

    public func configure(
        enabled: Bool,
        handler: @escaping @MainActor (GlobalHotKeyAction) -> Void
    ) {
        unregisterAll()
        guard enabled else {
            self.handler = nil
            if Self.activeManager === self {
                Self.activeManager = nil
            }
            return
        }

        self.handler = handler
        Self.activeManager = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonEventHandler,
            1,
            &eventType,
            nil,
            &installedHandler
        )
        guard installStatus == noErr, let installedHandler else {
            return
        }
        eventHandlerRef = installedHandler

        for action in GlobalHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.hotKeySignature,
                id: action.carbonHotKeyID
            )
            let registerStatus = RegisterEventHotKey(
                action.defaultKeyCode,
                action.defaultCarbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if registerStatus == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
                actionsByHotKeyID[action.carbonHotKeyID] = action
            }
        }
    }

    public func unregisterAll() {
        actionsByHotKeyID.removeAll()
        unregisterAllNonisolated()
    }

    private func handleHotKeyID(_ rawID: UInt32) {
        guard let action = actionsByHotKeyID[rawID] else { return }
        handler?(action)
    }

    nonisolated private func unregisterAllNonisolated() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
