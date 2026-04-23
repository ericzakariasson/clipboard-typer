import Carbon
import Foundation

enum HotKeyAction: UInt32 {
    case enqueueClipboard = 1
    case typeNext = 2
    case showControls = 3
}

enum HotKeyRegistrationError: LocalizedError {
    case installHandler(OSStatus)
    case register(HotKeyAction, OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "Could not install hotkey handler. OSStatus: \(status)"
        case .register(let action, let status):
            return "Could not register \(action.displayName) hotkey. OSStatus: \(status)"
        }
    }
}

extension HotKeyAction {
    var displayName: String {
        switch self {
        case .enqueueClipboard:
            return "enqueue clipboard"
        case .typeNext:
            return "type next"
        case .showControls:
            return "show controls"
        }
    }
}

final class HotKeyController {
    private static let signature: OSType = 0x43515459 // "CQTY"

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private let onAction: (HotKeyAction) -> Void

    init(onAction: @escaping (HotKeyAction) -> Void) {
        self.onAction = onAction
    }

    deinit {
        unregisterAll()
    }

    func registerDefaultHotKeys() throws {
        try installHandlerIfNeeded()

        try register(
            action: .enqueueClipboard,
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        )

        try register(
            action: .typeNext,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        )

        try register(
            action: .showControls,
            keyCode: UInt32(kVK_ANSI_O),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        )
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr else {
            throw HotKeyRegistrationError.installHandler(status)
        }
    }

    private func register(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) throws {
        if let existingRef = hotKeyRefs[action] {
            UnregisterEventHotKey(existingRef)
            hotKeyRefs[action] = nil
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: action.rawValue
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyRegistrationError.register(action, status)
        }

        hotKeyRefs[action] = hotKeyRef
    }

    private func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == signature,
              let action = HotKeyAction(rawValue: hotKeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }

        let controller = Unmanaged<HotKeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()

        DispatchQueue.main.async {
            controller.onAction(action)
        }

        return noErr
    }
}
