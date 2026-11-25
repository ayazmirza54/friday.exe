import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Watches the dictation key in every app with a Quartz event tap. The tap needs Accessibility (which
/// Bol already asks for to control the Mac) and never blocks or changes an event. It runs on its own
/// thread, so typing elsewhere never waits on Bol's main thread; the gesture is worked out on main.
final class DictationKeyMonitor {
	/// Main thread.
	var onOutput: ((DictationGesture.Output) -> Void)?

	private var gesture = DictationGesture()
	private var isInstalled = false
	private var retry: Timer?

	/// Read on the tap thread, written on main.
	private let lock = NSLock()
	private var key = DictationKey.fn
	private var isEnabled = false

	/// Tap thread only.
	private var tap: CFMachPort?
	private var isKeyDown = false

	private static let modifiers: CGEventFlags = [
		.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
	]
	/// The Globe key can also send a key event of its own beside the fn flag change.
	private static let globeKeyCode: Int64 = 179

	/// Main thread. Installs the tap the first time dictation is on (retrying until Accessibility is granted).
	func update(settings: DictationSettings) {
		lock.withLock {
			key = settings.key
			isEnabled = settings.isEnabled
		}
		gesture.isLockEnabled = settings.isDoubleTapLockEnabled
		if !settings.isEnabled { gesture.reset() }
		if settings.isEnabled, !isInstalled, retry == nil { installOrRetry() }
	}

	/// Main thread.
	func reset() { gesture.reset() }

	private func installOrRetry() {
		if install() {
			retry?.invalidate()
			retry = nil
			return
		}
		guard retry == nil else { return }
		Log.info(message: "dictation: key monitor waits for Accessibility")
		let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.installOrRetry() }
		RunLoop.main.add(timer, forMode: .common)
		retry = timer
	}

	private func install() -> Bool {
		guard !isInstalled, AXIsProcessTrusted() else { return isInstalled }
		let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
		let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
		let callback: CGEventTapCallBack = { _, type, event, info in
			if let info {
				Unmanaged<DictationKeyMonitor>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
			}
			return Unmanaged.passUnretained(event)
		}
		// The monitor lives as long as the app (the controller owns it), so an unretained pointer is safe.
		guard
			let tap = CGEvent.tapCreate(
				tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
				callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
			let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
		else {
			Log.info(message: "dictation: couldn't create the key tap")
			return false
		}
		self.tap = tap
		isInstalled = true
		let thread = Thread {
			CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
			CGEvent.tapEnable(tap: tap, enable: true)
			CFRunLoopRun()
		}
		thread.name = "bol.dictation-keys"
		thread.qualityOfService = .userInteractive
		thread.start()
		Log.info(message: "dictation: watching the key")
		return true
	}

	/// Tap thread. Only edges of the dictation key, and interruptions while it's held, go to main.
	private func handle(type: CGEventType, event: CGEvent) {
		switch type {
		case .tapDisabledByTimeout, .tapDisabledByUserInput:
			if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
			return
		default:
			break
		}
		let (key, isEnabled) = lock.withLock { (self.key, self.isEnabled) }
		guard isEnabled else {
			isKeyDown = false
			return
		}
		switch type {
		case .flagsChanged:
			let code = event.getIntegerValueField(.keyboardEventKeycode)
			let flags = event.flags
			let others = flags.intersection(Self.modifiers).subtracting(key.modifier)
			if code == key.keyCode {
				let isDown = flags.rawValue & key.deviceMask != 0
				guard isDown != isKeyDown else { return }
				isKeyDown = isDown
				// Held together with another modifier, it's a shortcut, not dictation.
				if isDown, !others.isEmpty { return }
				send(input: isDown ? .press : .release)
			} else if isKeyDown, !others.isEmpty {
				send(input: .interrupt)
			}
		case .keyDown:
			guard isKeyDown, event.getIntegerValueField(.keyboardEventKeycode) != Self.globeKeyCode else { return }
			send(input: .interrupt)
		case .leftMouseDown, .rightMouseDown, .otherMouseDown:
			if isKeyDown { send(input: .interrupt) }
		default:
			break
		}
	}

	private func send(input: DictationGesture.Input) {
		let now = Date()
		DispatchQueue.main.async { [weak self] in
			guard let self, self.lock.withLock({ self.isEnabled }) else { return }
			if let output = self.gesture.handle(input: input, at: now) { self.onOutput?(output) }
		}
	}
}

/// How macOS's own fn / 🌐 key action is set: anything but "Do Nothing" also fires when you dictate with fn.
enum GlobeKeyAction {
	/// System Settings → Keyboard → "Press 🌐 key to" is "Do Nothing".
	static var isDoingNothing: Bool {
		let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
		return (value as? Int) == 0
	}

	static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
