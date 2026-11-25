import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts dictated text where you're typing: through the clipboard and ⌘V, then puts
/// back what the clipboard held. Main thread only.
enum Paster {
	/// Long enough for the app in front to read the clipboard before it's restored.
	private static let restoreSeconds = 0.6
	/// Tells clipboard managers to skip the dictation (nspasteboard.org convention).
	private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

	/// Pastes `text` into the app in front. Without Accessibility Bol can't press ⌘V, so the text is
	/// left on the clipboard and this returns false.
	static func paste(text: String) -> Bool {
		let pasteboard = NSPasteboard.general
		let saved = snapshot(pasteboard: pasteboard)
		pasteboard.clearContents()
		let item = NSPasteboardItem()
		item.setString(text, forType: .string)
		item.setData(Data(), forType: transientType)
		pasteboard.writeObjects([item])
		guard AXIsProcessTrusted() else { return false }
		let changeCount = pasteboard.changeCount
		pressCommandV()
		DispatchQueue.main.asyncAfter(deadline: .now() + restoreSeconds) {
			// Something newer was copied meanwhile: leave it.
			guard pasteboard.changeCount == changeCount else { return }
			restore(items: saved, pasteboard: pasteboard)
		}
		return true
	}

	/// Puts text on the clipboard, for when it couldn't be pasted.
	static func copy(text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	private static func snapshot(pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
		(pasteboard.pasteboardItems ?? []).map { item in
			var types: [NSPasteboard.PasteboardType: Data] = [:]
			for type in item.types { if let data = item.data(forType: type) { types[type] = data } }
			return types
		}
	}

	private static func restore(items: [[NSPasteboard.PasteboardType: Data]], pasteboard: NSPasteboard) {
		pasteboard.clearContents()
		guard !items.isEmpty else { return }
		pasteboard.writeObjects(
			items.map { types in
				let item = NSPasteboardItem()
				for (type, data) in types { item.setData(data, forType: type) }
				return item
			})
	}

	/// ⌘V with only Command set, so a dictation key still held doesn't turn it into another shortcut.
	private static func pressCommandV() {
		let source = CGEventSource(stateID: .combinedSessionState)
		let key = keyCode(character: "v") ?? CGKeyCode(kVK_ANSI_V)
		for isDown in [true, false] {
			let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
			event?.flags = .maskCommand
			event?.post(tap: .cghidEventTap)
		}
	}

	/// The key that types `character` on the current keyboard layout (Dvorak's V isn't QWERTY's).
	private static func keyCode(character: String) -> CGKeyCode? {
		guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
			let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
		else { return nil }
		let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
		return layoutData.withUnsafeBytes { raw -> CGKeyCode? in
			guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
			for code in 0..<128 {
				var deadKeys: UInt32 = 0
				var length = 0
				var chars = [UniChar](repeating: 0, count: 4)
				let status = UCKeyTranslate(
					layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
					OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
				if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == character {
					return CGKeyCode(code)
				}
			}
			return nil
		}
	}
}
