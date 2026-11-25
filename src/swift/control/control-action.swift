import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// One computer-control request from the brain. Mirrors the tools in src/typescript/control.ts, which
/// follow the names and parameters of Claude Code's own computer use (which only runs in interactive
/// sessions, so Bol has its own), minus its per-app permission step.
struct ControlAction: Decodable {
	enum Name: String, Decodable {
		case screenshot, zoom
		case leftClick = "left_click"
		case rightClick = "right_click"
		case middleClick = "middle_click"
		case doubleClick = "double_click"
		case tripleClick = "triple_click"
		case leftClickDrag = "left_click_drag"
		case leftMouseDown = "left_mouse_down"
		case leftMouseUp = "left_mouse_up"
		case mouseMove = "mouse_move"
		case scroll, type, key
		case holdKey = "hold_key"
		case cursorPosition = "cursor_position"
		case openApplication = "open_application"
		case readClipboard = "read_clipboard"
		case writeClipboard = "write_clipboard"
		case wait
		case switchDisplay = "switch_display"
		case batch = "computer_batch"
	}

	let name: Name
	/// [x, y] in pixels of the latest screenshot.
	var coordinate: [Double]?
	var startCoordinate: [Double]?
	/// [x0, y0, x1, y1] in pixels of the latest screenshot.
	var region: [Double]?
	/// Text to type, a key combination, or modifier keys held during a click.
	var text: String?
	var `repeat`: Int?
	var scrollDirection: String?
	var scrollAmount: Int?
	/// Seconds.
	var duration: Double?
	var app: String?
	var display: String?
	var actions: [ControlAction]?
}

struct ControlResult {
	var text: String
	var isError = false
	/// JPEG files for the brain to attach (and delete).
	var imagePaths: [String] = []
}

struct ControlError: Error {
	let message: String
}

/// A key press with modifiers, parsed from text like "cmd+shift+a", "return" or "ctrl+left".
struct KeyCombo: Equatable {
	/// nil when the combination is only modifiers ("shift"), as for a modified click.
	let keyCode: CGKeyCode?
	let modifiers: [Modifier]

	enum Modifier: String, CaseIterable {
		case command, control, option, shift, function

		var flag: CGEventFlags {
			switch self {
			case .command: return .maskCommand
			case .control: return .maskControl
			case .option: return .maskAlternate
			case .shift: return .maskShift
			case .function: return .maskSecondaryFn
			}
		}

		var keyCode: CGKeyCode {
			switch self {
			case .command: return CGKeyCode(kVK_Command)
			case .control: return CGKeyCode(kVK_Control)
			case .option: return CGKeyCode(kVK_Option)
			case .shift: return CGKeyCode(kVK_Shift)
			case .function: return CGKeyCode(kVK_Function)
			}
		}

		init?(name: String) {
			switch name {
			case "cmd", "command", "super", "meta", "win": self = .command
			case "ctrl", "control": self = .control
			case "alt", "option", "opt": self = .option
			case "shift": self = .shift
			case "fn", "function", "globe": self = .function
			default: return nil
			}
		}
	}

	var flags: CGEventFlags { modifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) } }

	/// Returns nil when a part isn't a known key or modifier, or there is more than one key.
	static func parse(text: String) -> KeyCombo? {
		var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map {
			$0.trimmingCharacters(in: .whitespaces)
		}
		// "cmd++" means command and the plus key.
		if parts.count >= 2, parts.suffix(2).allSatisfy(\.isEmpty) { parts = parts.dropLast(2) + ["plus"] }
		guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }

		var modifiers: [Modifier] = []
		var keyCode: CGKeyCode?
		for part in parts {
			if let modifier = Modifier(name: part) {
				if !modifiers.contains(modifier) { modifiers.append(modifier) }
			} else if let code = keyCodes[part], keyCode == nil {
				keyCode = code
			} else if part == "plus", keyCode == nil {
				keyCode = CGKeyCode(kVK_ANSI_Equal)
				if !modifiers.contains(.shift) { modifiers.append(.shift) }
			} else {
				return nil
			}
		}
		return KeyCombo(keyCode: keyCode, modifiers: modifiers)
	}

	/// Key names to virtual key codes (US ANSI positions for the printable keys).
	private static let keyCodes: [String: CGKeyCode] = {
		var codes: [String: Int] = [
			"a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
			"g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
			"m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
			"s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
			"y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
			"0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
			"6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
			"return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "escape": kVK_Escape,
			"esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
			"del": kVK_ForwardDelete, "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow,
			"right": kVK_RightArrow, "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "page_up": kVK_PageUp,
			"pagedown": kVK_PageDown, "page_down": kVK_PageDown,
			"minus": kVK_ANSI_Minus, "-": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "=": kVK_ANSI_Equal,
			"comma": kVK_ANSI_Comma, ",": kVK_ANSI_Comma, "period": kVK_ANSI_Period, ".": kVK_ANSI_Period,
			"slash": kVK_ANSI_Slash, "/": kVK_ANSI_Slash, "backslash": kVK_ANSI_Backslash, "\\": kVK_ANSI_Backslash,
			"semicolon": kVK_ANSI_Semicolon, ";": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote, "'": kVK_ANSI_Quote,
			"grave": kVK_ANSI_Grave, "`": kVK_ANSI_Grave, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
		]
		let functionKeys = [
			kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
		]
		for (index, code) in functionKeys.enumerated() { codes["f\(index + 1)"] = code }
		return codes.mapValues { CGKeyCode($0) }
	}()
}

/// How a screenshot's pixels map to the screen: the captured display and the image's scale.
struct ScreenMapping: Equatable {
	/// The display's frame in global screen points, origin at the top left of the primary display.
	let frame: CGRect
	/// Image pixels per screen point.
	let scale: CGFloat
	let displayName: String

	/// Screenshots are downsampled so the longer edge is at most this many pixels: enough to read
	/// a full screen, small enough to be cheap to look at. `zoom` gives detail.
	static let maxImageEdge: CGFloat = 1568

	init(frame: CGRect, scale: CGFloat, displayName: String) {
		self.frame = frame
		self.scale = scale
		self.displayName = displayName
	}

	/// The mapping a screenshot of `frame` will have.
	init(frame: CGRect, displayName: String) {
		self.init(
			frame: frame, scale: min(1, Self.maxImageEdge / max(frame.width, frame.height)), displayName: displayName)
	}

	var imageSize: CGSize { CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()) }

	/// Image pixel -> global screen point, kept inside the display.
	func screenPoint(imageX: Double, imageY: Double) -> CGPoint {
		let x = frame.minX + CGFloat(imageX) / scale
		let y = frame.minY + CGFloat(imageY) / scale
		return CGPoint(x: min(max(x, frame.minX), frame.maxX - 1), y: min(max(y, frame.minY), frame.maxY - 1))
	}

	/// Global screen point -> image pixel.
	func imagePoint(screen point: CGPoint) -> CGPoint {
		CGPoint(x: ((point.x - frame.minX) * scale).rounded(), y: ((point.y - frame.minY) * scale).rounded())
	}
}
