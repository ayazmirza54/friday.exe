import CoreGraphics
import Foundation

/// Dictation in any app: hold a key, speak, let go and the text is pasted
/// where you're typing. Double-tap the key to keep listening hands-free; tap it again to paste.
struct DictationSettings: Codable, Equatable {
	var isEnabled = true
	var key = DictationKey.fn
	/// Double-tap the key to keep dictating without holding it; tap again to paste.
	var isDoubleTapLockEnabled = true
}

/// A modifier key held on its own to dictate.
enum DictationKey: String, Codable, CaseIterable {
	case fn, rightOption, rightCommand

	init(from decoder: Decoder) throws {
		self = DictationKey(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .fn
	}

	var title: String {
		switch self {
		case .fn: return "fn (Globe)"
		case .rightOption: return "Right Option"
		case .rightCommand: return "Right Command"
		}
	}

	/// The key on a key cap.
	var glyph: KeyGlyph {
		switch self {
		case .fn: return KeyGlyph(label: "fn", spoken: "Function")
		case .rightOption: return KeyGlyph(text: "right", symbol: "option", plain: label, spoken: title)
		case .rightCommand: return KeyGlyph(text: "right", symbol: "command", plain: label, spoken: title)
		}
	}

	/// Short label for sentences.
	var label: String {
		switch self {
		case .fn: return "fn"
		case .rightOption: return "right ⌥"
		case .rightCommand: return "right ⌘"
		}
	}

	/// The virtual key code macOS reports in the key's flagsChanged event.
	var keyCode: Int64 {
		switch self {
		case .fn: return 63  // kVK_Function
		case .rightOption: return 61  // kVK_RightOption
		case .rightCommand: return 54  // kVK_RightCommand
		}
	}

	/// The bit in an event's flags that is set while this physical key is down.
	var deviceMask: UInt64 {
		switch self {
		case .fn: return CGEventFlags.maskSecondaryFn.rawValue
		case .rightOption: return 0x40  // NX_DEVICERALTKEYMASK
		case .rightCommand: return 0x10  // NX_DEVICERCMDKEYMASK
		}
	}

	/// The device-independent modifier this key sets.
	var modifier: CGEventFlags {
		switch self {
		case .fn: return .maskSecondaryFn
		case .rightOption: return .maskAlternate
		case .rightCommand: return .maskCommand
		}
	}
}

/// Turns presses of the dictation key into start / lock / finish / discard. Pure, so it's tested
/// without a keyboard. Only a single modifier key held on its own counts.
///
/// - Hold for longer than a tap: dictate until the key is let go, then paste.
/// - A quick tap is dropped (it was probably meant for something else), but a second tap right
///   after it locks dictation on; the next press pastes.
/// - Another key, modifier or click within a tap of pressing means the key was part of a shortcut
///   (fn-Delete, ⌥-click): dropped. Later ones are ignored.
struct DictationGesture {
	enum Input: Equatable {
		case press, release
		/// Another key, modifier or mouse button went down while the dictation key was held.
		case interrupt
	}

	enum Output: Equatable {
		/// Start listening (it may still be dropped).
		case start
		/// Keep listening after the key is let go.
		case lock
		/// Stop listening and paste.
		case finish
		/// Stop listening and throw it away, quietly.
		case discard
	}

	enum State: Equatable {
		case idle
		case holding(since: Date, isSecondTap: Bool)
		case locked
	}

	/// Shorter than this is a tap, not a hold; two taps closer than this are a double-tap.
	static let tapSeconds: TimeInterval = 0.3

	var isLockEnabled = true
	private(set) var state = State.idle
	/// When a quick tap ended, for spotting the second tap of a double-tap.
	private var lastTapAt: Date?

	mutating func handle(input: Input, at now: Date) -> Output? {
		switch (state, input) {
		case (.idle, .press):
			let isSecondTap = isLockEnabled && lastTapAt.map { now.timeIntervalSince($0) < Self.tapSeconds } == true
			lastTapAt = nil
			state = .holding(since: now, isSecondTap: isSecondTap)
			return .start
		case (.holding(let since, let isSecondTap), .release):
			guard now.timeIntervalSince(since) < Self.tapSeconds else {
				state = .idle
				return .finish
			}
			if isSecondTap {
				state = .locked
				return .lock
			}
			state = .idle
			lastTapAt = isLockEnabled ? now : nil
			return .discard
		case (.holding(let since, _), .interrupt):
			guard now.timeIntervalSince(since) < Self.tapSeconds else { return nil }
			state = .idle
			lastTapAt = nil
			return .discard
		case (.locked, .press):
			state = .idle
			return .finish
		case (.idle, .release), (.idle, .interrupt), (.holding, .press), (.locked, .release), (.locked, .interrupt):
			return nil
		}
	}

	/// Dictation ended some other way (Esc, ⌘J, an error): forget any tap in progress.
	mutating func reset() {
		state = .idle
		lastTapAt = nil
	}
}
