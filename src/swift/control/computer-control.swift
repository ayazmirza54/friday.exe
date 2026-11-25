import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers

/// Sees and operates the Mac for the brain: screenshots, pointer, keyboard, clipboard, apps.
///
/// Runs in the app because the app holds the Accessibility and Screen Recording grants. Actions
/// run one at a time on their own queue (they sleep between events); results come back on main.
final class ComputerControl {
	/// Called on main around a capture, so Bol's own voice bar can stay out of the picture.
	var onCapturing: ((Bool) -> Void)?
	/// Called on main around key presses Bol sends, so its own hotkeys (Esc, ⌘J) don't catch them.
	var onSendingKeys: ((Bool) -> Void)?

	private let queue = DispatchQueue(label: "bol.control", qos: .userInitiated)
	/// What the latest screenshot showed; click coordinates are relative to it.
	private var mapping: ScreenMapping?
	/// The display chosen with `switch_display`, or nil to follow the frontmost window.
	private var pinnedDisplayName: String?
	private var isLeftButtonDown = false
	/// Bumped by `cancel()`: a running batch stops before its next action.
	private var epoch = 0
	private let epochLock = NSLock()

	func perform(action: ControlAction, completion: @escaping (ControlResult) -> Void) {
		let startEpoch = currentEpoch
		queue.async {
			var result: ControlResult
			do {
				result = try self.run(action: action, epoch: startEpoch)
			} catch let error as ControlError {
				result = ControlResult(text: error.message, isError: true)
			} catch {
				result = ControlResult(text: "\(error)", isError: true)
			}
			DispatchQueue.main.async { completion(result) }
		}
	}

	/// The user pressed stop: nothing further is clicked or typed, and a held button is released.
	func cancel() {
		epochLock.lock()
		epoch += 1
		epochLock.unlock()
		queue.async {
			guard self.isLeftButtonDown else { return }
			self.isLeftButtonDown = false
			self.postMouse(type: .leftMouseUp, at: self.cursorLocation)
		}
	}

	private var currentEpoch: Int {
		epochLock.lock()
		defer { epochLock.unlock() }
		return epoch
	}

	// MARK: Actions

	private func run(action: ControlAction, epoch startEpoch: Int) throws -> ControlResult {
		guard currentEpoch == startEpoch else { throw ControlError(message: "Stopped by the user.") }
		switch action.name {
		case .screenshot:
			return try screenshot()
		case .zoom:
			return try zoom(region: action.region)
		case .leftClick:
			return try click(action: action, button: .left, count: 1, label: "Left-clicked")
		case .rightClick:
			return try click(action: action, button: .right, count: 1, label: "Right-clicked")
		case .middleClick:
			return try click(action: action, button: .center, count: 1, label: "Middle-clicked")
		case .doubleClick:
			return try click(action: action, button: .left, count: 2, label: "Double-clicked")
		case .tripleClick:
			return try click(action: action, button: .left, count: 3, label: "Triple-clicked")
		case .leftClickDrag:
			return try drag(action: action)
		case .leftMouseDown:
			try requireAccessibility()
			guard !isLeftButtonDown else { throw ControlError(message: "The left button is already held.") }
			postMouse(type: .leftMouseDown, at: cursorLocation)
			isLeftButtonDown = true
			return ControlResult(text: "Left button pressed and held.")
		case .leftMouseUp:
			try requireAccessibility()
			postMouse(type: .leftMouseUp, at: cursorLocation)
			isLeftButtonDown = false
			return ControlResult(text: "Left button released.")
		case .mouseMove:
			try requireAccessibility()
			let point = try screenPoint(coordinate: action.coordinate)
			postMouse(type: isLeftButtonDown ? .leftMouseDragged : .mouseMoved, at: point)
			pause(seconds: 0.08)
			return ControlResult(text: "Moved the pointer to \(describe(coordinate: action.coordinate)).")
		case .scroll:
			return try scroll(action: action)
		case .type:
			return try type(text: action.text)
		case .key:
			return try key(action: action)
		case .holdKey:
			return try holdKey(action: action)
		case .cursorPosition:
			let point = currentMapping().imagePoint(screen: cursorLocation)
			return ControlResult(text: "The pointer is at (\(Int(point.x)), \(Int(point.y))).")
		case .openApplication:
			return try openApplication(name: action.app)
		case .readClipboard:
			let text = onMain { NSPasteboard.general.string(forType: .string) }
			return ControlResult(text: text ?? "The clipboard has no text.")
		case .writeClipboard:
			guard let text = action.text else { throw ControlError(message: "write_clipboard needs text.") }
			onMain {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(text, forType: .string)
			}
			return ControlResult(text: "Copied \(text.count) characters to the clipboard.")
		case .wait:
			let seconds = min(max(action.duration ?? 1, 0), 30)
			let end = Date().addingTimeInterval(seconds)
			while Date() < end, currentEpoch == startEpoch { pause(seconds: 0.1) }
			return ControlResult(text: "Waited \(String(format: "%.1f", seconds)) seconds.")
		case .switchDisplay:
			return try switchDisplay(name: action.display)
		case .batch:
			return try batch(actions: action.actions, epoch: startEpoch)
		}
	}

	private func batch(actions: [ControlAction]?, epoch startEpoch: Int) throws -> ControlResult {
		guard let actions, !actions.isEmpty else { throw ControlError(message: "computer_batch needs actions.") }
		var combined = ControlResult(text: "")
		var lines: [String] = []
		for (index, action) in actions.enumerated() {
			do {
				let result = try run(action: action, epoch: startEpoch)
				lines.append("\(index + 1). \(result.text)")
				combined.imagePaths += result.imagePaths
			} catch let error as ControlError {
				// Like a person would: stop at the first thing that goes wrong.
				lines.append("\(index + 1). \(action.name.rawValue) failed: \(error.message)")
				lines.append("Stopped: the remaining \(actions.count - index - 1) action(s) were not run.")
				combined.isError = true
				break
			}
		}
		combined.text = lines.joined(separator: "\n")
		return combined
	}

	// MARK: Seeing

	private func screenshot() throws -> ControlResult {
		try requireScreenRecording()
		let display = targetDisplay()
		let planned = ScreenMapping(frame: display.frame, displayName: display.name)
		let image = try capture(rect: display.frame, maxEdge: max(planned.imageSize.width, planned.imageSize.height))
		// The scale that was actually produced, so clicks land exactly where the picture shows.
		let actual = ScreenMapping(
			frame: display.frame, scale: image.size.width / display.frame.width, displayName: display.name)
		mapping = actual
		var text = "Screenshot of \(display.name), \(Int(image.size.width))x\(Int(image.size.height)) pixels. "
		text += "Coordinates for clicks are pixels in this image."
		if let app = onMain({ NSWorkspace.shared.frontmostApplication?.localizedName }) {
			text += " Frontmost app: \(app)."
		}
		let others = displays().map(\.name).filter { $0 != display.name }
		if !others.isEmpty { text += " Other displays: \(others.joined(separator: ", "))." }
		return ControlResult(text: text, imagePaths: [image.path])
	}

	private func zoom(region: [Double]?) throws -> ControlResult {
		try requireScreenRecording()
		guard let region, region.count == 4 else {
			throw ControlError(message: "zoom needs region [x0, y0, x1, y1] in screenshot pixels.")
		}
		let mapping = currentMapping()
		let a = mapping.screenPoint(imageX: min(region[0], region[2]), imageY: min(region[1], region[3]))
		let b = mapping.screenPoint(imageX: max(region[0], region[2]), imageY: max(region[1], region[3]))
		let rect = CGRect(x: a.x, y: a.y, width: max(b.x - a.x, 8), height: max(b.y - a.y, 8))
		let image = try capture(rect: rect, maxEdge: ScreenMapping.maxImageEdge)
		return ControlResult(
			text: "Zoomed view of that region. Click coordinates still refer to the full screenshot, not this image.",
			imagePaths: [image.path])
	}

	/// Captures a rectangle (global points) as a JPEG whose longer edge is at most `maxEdge` pixels.
	private func capture(rect: CGRect, maxEdge: CGFloat) throws -> (path: String, size: CGSize) {
		let directory = FileManager.default.temporaryDirectory
		let raw = directory.appendingPathComponent("bol-capture-\(UUID().uuidString).png")
		let output = directory.appendingPathComponent("bol-screen-\(UUID().uuidString).jpg")
		defer { try? FileManager.default.removeItem(at: raw) }

		onMain { self.onCapturing?(true) }
		pause(seconds: 0.06)  // one frame, so the voice bar is gone from the next composite
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
		let area = [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(
			separator: ",")
		process.arguments = ["-x", "-t", "png", "-R", area, raw.path]
		do {
			try process.run()
			process.waitUntilExit()
		} catch {
			onMain { self.onCapturing?(false) }
			throw ControlError(message: "Couldn't run screencapture: \(error.localizedDescription)")
		}
		onMain { self.onCapturing?(false) }

		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Int(maxEdge),
			kCGImageSourceCreateThumbnailWithTransform: true,
		]
		guard let source = CGImageSourceCreateWithURL(raw as CFURL, nil),
			let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
			let destination = CGImageDestinationCreateWithURL(
				output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
		else {
			throw ControlError(
				message: "The screenshot failed. Bol may need Screen Recording permission in System Settings.")
		}
		CGImageDestinationAddImage(
			destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
		guard CGImageDestinationFinalize(destination) else {
			throw ControlError(message: "Couldn't save the screenshot.")
		}
		return (output.path, CGSize(width: image.width, height: image.height))
	}

	// MARK: Pointer

	private func click(action: ControlAction, button: CGMouseButton, count: Int, label: String) throws -> ControlResult
	{
		try requireAccessibility()
		let point = try screenPoint(coordinate: action.coordinate)
		var held = KeyCombo(keyCode: nil, modifiers: [])
		if let text = action.text, !text.isEmpty {
			guard let combo = KeyCombo.parse(text: text), combo.keyCode == nil else {
				throw ControlError(
					message: "Click modifiers must be keys like shift, cmd, ctrl or alt, got \"\(text)\".")
			}
			held = combo
		}
		let (down, up): (CGEventType, CGEventType)
		switch button {
		case .left: (down, up) = (.leftMouseDown, .leftMouseUp)
		case .right: (down, up) = (.rightMouseDown, .rightMouseUp)
		case .center: (down, up) = (.otherMouseDown, .otherMouseUp)
		@unknown default: (down, up) = (.leftMouseDown, .leftMouseUp)
		}
		postMouse(type: .mouseMoved, at: point)
		pause(seconds: 0.04)
		press(modifiers: held.modifiers, isDown: true)
		for state in 1...count {
			postMouse(type: down, at: point, button: button, clickState: state, flags: held.flags)
			pause(seconds: 0.02)
			postMouse(type: up, at: point, button: button, clickState: state, flags: held.flags)
			pause(seconds: 0.05)
		}
		press(modifiers: held.modifiers, isDown: false)
		pause(seconds: 0.12)  // let the app react before the next action or screenshot
		return ControlResult(text: "\(label) at \(describe(coordinate: action.coordinate)).")
	}

	private func drag(action: ControlAction) throws -> ControlResult {
		try requireAccessibility()
		let end = try screenPoint(coordinate: action.coordinate)
		let start = try action.startCoordinate.map { try screenPoint(coordinate: $0) } ?? cursorLocation
		postMouse(type: .mouseMoved, at: start)
		pause(seconds: 0.05)
		postMouse(type: .leftMouseDown, at: start)
		pause(seconds: 0.08)
		let steps = 12
		for step in 1...steps {
			let t = CGFloat(step) / CGFloat(steps)
			let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
			postMouse(type: .leftMouseDragged, at: point)
			pause(seconds: 0.015)
		}
		pause(seconds: 0.08)
		postMouse(type: .leftMouseUp, at: end)
		pause(seconds: 0.12)
		return ControlResult(text: "Dragged to \(describe(coordinate: action.coordinate)).")
	}

	private func scroll(action: ControlAction) throws -> ControlResult {
		try requireAccessibility()
		let point = try screenPoint(coordinate: action.coordinate)
		let amount = Int32(min(max(action.scrollAmount ?? 3, 1), 100))
		var vertical: Int32 = 0
		var horizontal: Int32 = 0
		switch action.scrollDirection {
		case "up": vertical = amount
		case "down": vertical = -amount
		case "left": horizontal = amount
		case "right": horizontal = -amount
		default: throw ControlError(message: "scroll_direction must be up, down, left or right.")
		}
		postMouse(type: .mouseMoved, at: point)
		pause(seconds: 0.04)
		// One wheel notch at a time, as a mouse would send them.
		for _ in 0..<Int(amount) {
			let event = CGEvent(
				scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: vertical.signum() * 3,
				wheel2: horizontal.signum() * 3, wheel3: 0)
			event?.post(tap: .cghidEventTap)
			pause(seconds: 0.012)
		}
		pause(seconds: 0.15)
		return ControlResult(
			text: "Scrolled \(action.scrollDirection ?? "") by \(amount) at \(describe(coordinate: action.coordinate))."
		)
	}

	private func postMouse(
		type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, clickState: Int = 1,
		flags: CGEventFlags = []
	) {
		guard
			let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
		else { return }
		event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
		event.flags = flags
		event.post(tap: .cghidEventTap)
	}

	/// The pointer's position in global screen points (origin top left).
	private var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

	// MARK: Keyboard

	private func type(text: String?) throws -> ControlResult {
		try requireAccessibility()
		guard let text, !text.isEmpty else { throw ControlError(message: "type needs text.") }
		var pending = ""
		func flush() {
			guard !pending.isEmpty else { return }
			let units = Array(pending.utf16)
			// An event carries a short string; longer text goes out in pieces.
			for start in stride(from: 0, to: units.count, by: 16) {
				let chunk = Array(units[start..<min(start + 16, units.count)])
				for isDown in [true, false] {
					let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)
					event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
					event?.post(tap: .cghidEventTap)
				}
				pause(seconds: 0.008)
			}
			pending = ""
		}
		for character in text {
			switch character {
			case "\n", "\r\n":
				flush()
				tap(keyCode: CGKeyCode(kVK_Return), flags: [])
			case "\t":
				flush()
				tap(keyCode: CGKeyCode(kVK_Tab), flags: [])
			default:
				pending.append(character)
			}
		}
		flush()
		pause(seconds: 0.08)
		return ControlResult(text: "Typed \(text.count) characters.")
	}

	private func key(action: ControlAction) throws -> ControlResult {
		try requireAccessibility()
		let combo = try keyCombo(text: action.text)
		let times = min(max(action.repeat ?? 1, 1), 100)
		onMain { self.onSendingKeys?(true) }
		defer { onMain { self.onSendingKeys?(false) } }
		press(modifiers: combo.modifiers, isDown: true)
		for _ in 0..<times {
			if let keyCode = combo.keyCode { tap(keyCode: keyCode, flags: combo.flags) }
			pause(seconds: 0.03)
		}
		press(modifiers: combo.modifiers, isDown: false)
		pause(seconds: 0.1)
		return ControlResult(text: "Pressed \(action.text ?? "")\(times > 1 ? " \(times) times" : "").")
	}

	private func holdKey(action: ControlAction) throws -> ControlResult {
		try requireAccessibility()
		let combo = try keyCombo(text: action.text)
		let seconds = min(max(action.duration ?? 1, 0), 30)
		onMain { self.onSendingKeys?(true) }
		defer { onMain { self.onSendingKeys?(false) } }
		press(modifiers: combo.modifiers, isDown: true)
		if let keyCode = combo.keyCode { postKey(keyCode: keyCode, isDown: true, flags: combo.flags) }
		pause(seconds: seconds)
		if let keyCode = combo.keyCode { postKey(keyCode: keyCode, isDown: false, flags: combo.flags) }
		press(modifiers: combo.modifiers, isDown: false)
		return ControlResult(text: "Held \(action.text ?? "") for \(String(format: "%.1f", seconds)) seconds.")
	}

	private func keyCombo(text: String?) throws -> KeyCombo {
		guard let text, let combo = KeyCombo.parse(text: text) else {
			throw ControlError(
				message:
					"Unknown key \"\(text ?? "")\". Use names like return, escape, tab, space, up, f5, cmd+a, ctrl+shift+tab."
			)
		}
		return combo
	}

	/// Modifier keys go down and up as real key events, so system shortcuts see them too.
	private func press(modifiers: [KeyCombo.Modifier], isDown: Bool) {
		var flags = CGEventFlags()
		for modifier in isDown ? modifiers : modifiers.reversed() {
			if isDown { flags.insert(modifier.flag) }
			postKey(keyCode: modifier.keyCode, isDown: isDown, flags: isDown ? flags : [])
			pause(seconds: 0.01)
		}
	}

	private func tap(keyCode: CGKeyCode, flags: CGEventFlags) {
		postKey(keyCode: keyCode, isDown: true, flags: flags)
		postKey(keyCode: keyCode, isDown: false, flags: flags)
	}

	private func postKey(keyCode: CGKeyCode, isDown: Bool, flags: CGEventFlags) {
		let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown)
		event?.flags = flags
		event?.post(tap: .cghidEventTap)
	}

	// MARK: Apps and displays

	private func openApplication(name: String?) throws -> ControlResult {
		guard let name, !name.isEmpty else { throw ControlError(message: "open_application needs an app name.") }
		for flag in ["-a", "-b"] {  // by name, then by bundle identifier
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
			process.arguments = [flag, name]
			process.standardError = FileHandle.nullDevice
			guard (try? process.run()) != nil else { continue }
			process.waitUntilExit()
			if process.terminationStatus == 0 {
				pause(seconds: 0.6)  // time to come to the front
				return ControlResult(text: "Opened \(name).")
			}
		}
		throw ControlError(message: "Couldn't find an app called \"\(name)\".")
	}

	private func switchDisplay(name: String?) throws -> ControlResult {
		guard let name, !name.isEmpty else {
			throw ControlError(message: "switch_display needs a display name or \"auto\".")
		}
		if name.lowercased() == "auto" {
			pinnedDisplayName = nil
			return ControlResult(text: "Following the frontmost window's display again. Take a screenshot to see it.")
		}
		let all = displays()
		guard let match = all.first(where: { $0.name.lowercased() == name.lowercased() }) else {
			throw ControlError(
				message: "No display called \"\(name)\". Attached: \(all.map(\.name).joined(separator: ", ")).")
		}
		pinnedDisplayName = match.name
		return ControlResult(text: "Switched to \(match.name). Take a screenshot to see it.")
	}

	/// Attached displays, with frames in global points (origin at the primary display's top left).
	private func displays() -> [(name: String, frame: CGRect)] {
		onMain {
			let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
			return NSScreen.screens.map { screen in
				let frame = screen.frame
				return (
					screen.localizedName,
					CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
				)
			}
		}
	}

	/// The pinned display, else the one showing the frontmost app's window, else the primary one.
	private func targetDisplay() -> (name: String, frame: CGRect) {
		let all = displays()
		if let pinnedDisplayName, let pinned = all.first(where: { $0.name == pinnedDisplayName }) { return pinned }
		let fallback = all.first ?? ("Display", CGRect(x: 0, y: 0, width: 1440, height: 900))
		guard let pid = onMain({ NSWorkspace.shared.frontmostApplication?.processIdentifier }),
			let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
				as? [[CFString: Any]]
		else { return fallback }
		for window in windows {
			guard (window[kCGWindowOwnerPID] as? pid_t) == pid, (window[kCGWindowLayer] as? Int) == 0,
				let bounds = window[kCGWindowBounds] as? [String: Any],
				let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
			else { continue }
			let center = CGPoint(x: rect.midX, y: rect.midY)
			return all.first(where: { $0.frame.contains(center) }) ?? fallback
		}
		return fallback
	}

	/// The latest screenshot's mapping, or the one a screenshot taken now would have.
	private func currentMapping() -> ScreenMapping {
		if let mapping { return mapping }
		let display = targetDisplay()
		return ScreenMapping(frame: display.frame, displayName: display.name)
	}

	private func screenPoint(coordinate: [Double]?) throws -> CGPoint {
		guard let coordinate, coordinate.count == 2 else {
			throw ControlError(message: "This action needs coordinate [x, y] in screenshot pixels.")
		}
		return currentMapping().screenPoint(imageX: coordinate[0], imageY: coordinate[1])
	}

	private func describe(coordinate: [Double]?) -> String {
		guard let coordinate, coordinate.count == 2 else { return "the pointer" }
		return "(\(Int(coordinate[0])), \(Int(coordinate[1])))"
	}

	// MARK: Permissions and helpers

	private func requireAccessibility() throws {
		guard AXIsProcessTrusted() else {
			throw ControlError(
				message: "Bol can't control the pointer or keyboard yet: it needs Accessibility permission. "
					+ "Tell the user to enable Bol in System Settings, Privacy & Security, Accessibility.")
		}
	}

	private func requireScreenRecording() throws {
		guard CGPreflightScreenCaptureAccess() else {
			throw ControlError(
				message: "Bol can't see the screen yet: it needs Screen Recording permission. "
					+ "Tell the user to enable Bol in System Settings, Privacy & Security, Screen & System Audio Recording."
			)
		}
	}

	private func pause(seconds: TimeInterval) {
		Thread.sleep(forTimeInterval: seconds)
	}

	/// AppKit state (screens, pasteboard, frontmost app) is read on the main thread.
	private func onMain<T>(_ work: () -> T) -> T {
		Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
	}
}
