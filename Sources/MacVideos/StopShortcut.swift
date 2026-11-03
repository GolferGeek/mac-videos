import Carbon

/// RegisterEventHotKey works across apps without Accessibility or Input Monitoring permission.
@MainActor final class StopShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static let signature: OSType = 0x4D565354 // MVST

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4D565354, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<StopShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), identifier,
                                  GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
