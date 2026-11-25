import Carbon.HIToolbox

/// System-wide hotkey via Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKey {
	private var ref: EventHotKeyRef?
	private let keyCode: Int
	private let modifiers: Int
	private static var handlers: [UInt32: () -> Void] = [:]
	/// Every live hotkey, so they can all be suspended together.
	private static var registered: [UInt32: () -> HotKey?] = [:]
	private static var isHandlerInstalled = false
	private static var nextID: UInt32 = 1
	private let id: UInt32

	/// keyCode: e.g. kVK_ANSI_J; modifiers: e.g. cmdKey | optionKey
	init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
		HotKey.installHandlerIfNeeded()
		id = HotKey.nextID
		HotKey.nextID += 1
		self.keyCode = keyCode
		self.modifiers = modifiers
		guard register() else { return nil }
		HotKey.handlers[id] = handler
		HotKey.registered[id] = { [weak self] in self }
	}

	deinit {
		if let ref { UnregisterEventHotKey(ref) }
		HotKey.handlers[id] = nil
		HotKey.registered[id] = nil
	}

	private func register() -> Bool {
		let hkID = EventHotKeyID(signature: OSType(0x4A52_5653), id: id)  // 'JRVS'
		let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
		if status != noErr { Log.info(message: "hotkey: register failed \(status)") }
		return status == noErr
	}

	/// A registered hotkey takes its key away from every app. While Bol itself is pressing keys
	/// (computer control), its hotkeys step aside, so an Escape it sends reaches the app in front
	/// instead of stopping Bol. Main thread only.
	static func setAllSuspended(isSuspended: Bool) {
		for hotKey in registered.values.compactMap({ $0() }) {
			if isSuspended, let ref = hotKey.ref {
				UnregisterEventHotKey(ref)
				hotKey.ref = nil
			} else if !isSuspended, hotKey.ref == nil {
				_ = hotKey.register()
			}
		}
	}

	private static func installHandlerIfNeeded() {
		guard !isHandlerInstalled else { return }
		isHandlerInstalled = true
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(
			GetApplicationEventTarget(),
			{ _, event, _ in
				var hkID = EventHotKeyID()
				GetEventParameter(
					event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
					nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
				if let h = HotKey.handlers[hkID.id] { DispatchQueue.main.async { h() } }
				return noErr
			}, 1, &spec, nil, nil)
	}
}
