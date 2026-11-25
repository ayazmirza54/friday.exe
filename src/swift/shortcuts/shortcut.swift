import AppKit
import Carbon.HIToolbox

/// A key combination: a virtual key code (the key's position, US ANSI names) plus modifiers.
/// Stored in config.json as `{"keyCode": 38, "modifiers": ["command"]}`.
struct Shortcut: Codable, Equatable, Hashable {
	let keyCode: Int
	let modifiers: [Modifier]

	/// Listed in the order macOS shows them: ⌃ ⌥ ⇧ ⌘.
	enum Modifier: String, Codable, CaseIterable {
		case control, option, shift, command

		var glyph: KeyGlyph {
			switch self {
			case .control: return KeyGlyph(symbol: "control", plain: "⌃", spoken: "Control")
			case .option: return KeyGlyph(symbol: "option", plain: "⌥", spoken: "Option")
			case .shift: return KeyGlyph(symbol: "shift", plain: "⇧", spoken: "Shift")
			case .command: return KeyGlyph(symbol: "command", plain: "⌘", spoken: "Command")
			}
		}

		var carbonFlag: Int {
			switch self {
			case .control: return controlKey
			case .option: return optionKey
			case .shift: return shiftKey
			case .command: return cmdKey
			}
		}

		var eventFlag: NSEvent.ModifierFlags {
			switch self {
			case .control: return .control
			case .option: return .option
			case .shift: return .shift
			case .command: return .command
			}
		}
	}

	init(keyCode: Int, modifiers: [Modifier]) {
		self.keyCode = keyCode
		self.modifiers = Modifier.allCases.filter(modifiers.contains)  // canonical order, no repeats
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			keyCode: try container.decode(Int.self, forKey: .keyCode),
			modifiers: try container.decode([String].self, forKey: .modifiers).compactMap(Modifier.init(rawValue:)))
	}

	/// The modifiers held in an event, in canonical order.
	static func modifiers(flags: NSEvent.ModifierFlags) -> [Modifier] {
		Modifier.allCases.filter { flags.contains($0.eventFlag) }
	}

	var carbonModifiers: Int { modifiers.reduce(0) { $0 | $1.carbonFlag } }

	/// One glyph per key: the modifiers, then the key.
	var glyphs: [KeyGlyph] { modifiers.map(\.glyph) + [KeyNames.glyph(keyCode: keyCode)] }

	/// "⌥⇧V", for menus, tooltips and sentences.
	var plainText: String { glyphs.map(\.plain).joined() }

	/// "Option Shift V", for VoiceOver.
	var spokenText: String { glyphs.map(\.spoken).joined(separator: " ") }

	/// The menu item key equivalent, when the key has one a menu can show.
	var menuKeyEquivalent: String? { KeyNames.menuKeyEquivalent(keyCode: keyCode) }

	var menuModifierMask: NSEvent.ModifierFlags {
		modifiers.reduce(into: NSEvent.ModifierFlags()) { $0.insert($1.eventFlag) }
	}

	var isFunctionKey: Bool { KeyNames.functionKeys.contains(keyCode) }
}

/// What a key looks like on a key cap: an SF Symbol for modifiers and special keys, so ⌥ and ⇧
/// are drawn at the weight and size of the letter next to them, or text for everything else.
struct KeyGlyph: Equatable, Hashable {
	/// Shown before the symbol ("right" in "right ⌥"), or alone.
	var text: String? = nil
	var symbol: String? = nil
	/// The key as a character: "⌘", "J", "right ⌥".
	let plain: String
	/// The key's name for VoiceOver: "Command".
	let spoken: String

	init(text: String? = nil, symbol: String? = nil, plain: String, spoken: String) {
		self.text = text
		self.symbol = symbol
		self.plain = plain
		self.spoken = spoken
	}

	/// A key shown as its own label ("J", "esc").
	init(label: String, spoken: String? = nil) {
		self.init(text: label, plain: label, spoken: spoken ?? label)
	}

	static let returnKey = KeyGlyph(symbol: "return", plain: "↩", spoken: "Return")
	static let escape = KeyGlyph(label: "esc", spoken: "Escape")
	static let command = Shortcut.Modifier.command.glyph
	static let shift = Shortcut.Modifier.shift.glyph
	static let option = Shortcut.Modifier.option.glyph
}

/// Bol's global shortcuts. Each one works from any app.
enum ShortcutAction: String, CaseIterable, Identifiable {
	case talk, pasteLastDictation, openBol, newConversation

	var id: String { rawValue }

	var title: String {
		switch self {
		case .talk: return "Talk to Bol"
		case .pasteLastDictation: return "Paste last dictation"
		case .openBol: return "Open Bol"
		case .newConversation: return "New conversation"
		}
	}

	var subtitle: String {
		switch self {
		case .talk: return "Start talking, or interrupt Bol and talk"
		case .pasteLastDictation: return "Pastes it again where you're typing"
		case .openBol: return "Threads, tasks and what Bol did"
		case .newConversation: return "Bol starts fresh from here"
		}
	}

	var icon: String {
		switch self {
		case .talk: return "mic"
		case .pasteLastDictation: return "doc.on.clipboard"
		case .openBol: return "bubble.left.and.text.bubble.right"
		case .newConversation: return "square.and.pencil"
		}
	}

	var defaultShortcut: Shortcut? {
		switch self {
		case .talk: return Shortcut(keyCode: kVK_ANSI_J, modifiers: [.command])
		case .pasteLastDictation: return Shortcut(keyCode: kVK_ANSI_V, modifiers: [.option, .shift])
		case .openBol, .newConversation: return nil
		}
	}
}

/// The shortcut chosen for each action. nil turns an action's shortcut off; it's stored as null,
/// so a cleared shortcut stays cleared instead of falling back to its default on the next launch.
struct ShortcutSettings: Equatable {
	var talk = ShortcutAction.talk.defaultShortcut
	var pasteLastDictation = ShortcutAction.pasteLastDictation.defaultShortcut
	var openBol = ShortcutAction.openBol.defaultShortcut
	var newConversation = ShortcutAction.newConversation.defaultShortcut

	subscript(action: ShortcutAction) -> Shortcut? {
		get {
			switch action {
			case .talk: return talk
			case .pasteLastDictation: return pasteLastDictation
			case .openBol: return openBol
			case .newConversation: return newConversation
			}
		}
		set {
			switch action {
			case .talk: talk = newValue
			case .pasteLastDictation: pasteLastDictation = newValue
			case .openBol: openBol = newValue
			case .newConversation: newConversation = newValue
			}
		}
	}

	/// The other action already using `shortcut`, if any.
	func action(using shortcut: Shortcut, except action: ShortcutAction) -> ShortcutAction? {
		ShortcutAction.allCases.first { $0 != action && self[$0] == shortcut }
	}

	/// Why `shortcut` can't be used for `action`, or nil when it can.
	func problem(shortcut: Shortcut, action: ShortcutAction) -> String? {
		let modifiers = Set(shortcut.modifiers)
		if modifiers.isDisjoint(with: [.command, .control, .option]), !shortcut.isFunctionKey {
			return "Add ⌘, ⌥ or ⌃ so it doesn't get in the way of typing"
		}
		if let owner = ShortcutSettings.systemOwner(shortcut: shortcut) {
			return "\(shortcut.plainText) is \(owner) in every app"
		}
		if let other = self.action(using: shortcut, except: action) {
			return "Already used for \(other.title)"
		}
		return nil
	}

	/// Shortcuts every Mac user relies on, which a global shortcut would take away from every app.
	private static func systemOwner(shortcut: Shortcut) -> String? {
		let names: [Int: String]
		switch shortcut.modifiers {
		case [.command]:
			names = [
				kVK_ANSI_Q: "Quit", kVK_ANSI_W: "Close", kVK_ANSI_C: "Copy", kVK_ANSI_V: "Paste", kVK_ANSI_X: "Cut",
				kVK_ANSI_Z: "Undo", kVK_ANSI_A: "Select All", kVK_ANSI_S: "Save", kVK_ANSI_H: "Hide",
				kVK_ANSI_M: "Minimize", kVK_ANSI_N: "New", kVK_ANSI_O: "Open", kVK_ANSI_P: "Print", kVK_ANSI_F: "Find",
				kVK_ANSI_T: "New Tab", kVK_Tab: "the app switcher", kVK_Space: "Spotlight",
				kVK_ANSI_Comma: "Settings",
			]
		case [.shift, .command]:
			names = [
				kVK_ANSI_3: "a screenshot", kVK_ANSI_4: "a screenshot", kVK_ANSI_5: "a screenshot", kVK_ANSI_Z: "Redo",
			]
		case [.control]:
			names = [kVK_Space: "the input source switcher"]
		default:
			names = [:]
		}
		return names[shortcut.keyCode]
	}
}

extension ShortcutSettings: Codable {
	private enum CodingKeys: String, CodingKey {
		case talk, pasteLastDictation, openBol, newConversation
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = ShortcutSettings()
		func value(key: CodingKeys, fallback: Shortcut?) throws -> Shortcut? {
			guard container.contains(key) else { return fallback }
			return try container.decodeIfPresent(Shortcut.self, forKey: key)
		}
		talk = try value(key: .talk, fallback: defaults.talk)
		pasteLastDictation = try value(key: .pasteLastDictation, fallback: defaults.pasteLastDictation)
		openBol = try value(key: .openBol, fallback: defaults.openBol)
		newConversation = try value(key: .newConversation, fallback: defaults.newConversation)
	}

	/// Writes null for a shortcut that's off.
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(talk, forKey: .talk)
		try container.encode(pasteLastDictation, forKey: .pasteLastDictation)
		try container.encode(openBol, forKey: .openBol)
		try container.encode(newConversation, forKey: .newConversation)
	}
}

/// Names for virtual key codes: US ANSI positions for the printable keys (the same positions the
/// hotkeys register), SF Symbols for the special ones.
enum KeyNames {
	static let functionKeys: [Int] = [
		kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13,
		kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
	]

	private static let characters: [Int: String] = [
		kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
		kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
		kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
		kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
		kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
		kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
		kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
		kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
		kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
		kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
	]

	/// (symbol, plain, spoken) for keys drawn as SF Symbols.
	private static let symbols: [Int: (String, String, String)] = [
		kVK_Return: ("return", "↩", "Return"), kVK_ANSI_KeypadEnter: ("return", "⌤", "Enter"),
		kVK_Tab: ("arrow.right.to.line", "⇥", "Tab"), kVK_Delete: ("delete.left", "⌫", "Delete"),
		kVK_ForwardDelete: ("delete.right", "⌦", "Forward Delete"), kVK_UpArrow: ("arrow.up", "↑", "Up Arrow"),
		kVK_DownArrow: ("arrow.down", "↓", "Down Arrow"), kVK_LeftArrow: ("arrow.left", "←", "Left Arrow"),
		kVK_RightArrow: ("arrow.right", "→", "Right Arrow"), kVK_PageUp: ("arrow.up.to.line", "⇞", "Page Up"),
		kVK_PageDown: ("arrow.down.to.line", "⇟", "Page Down"), kVK_Home: ("arrow.up.left", "↖", "Home"),
		kVK_End: ("arrow.down.right", "↘", "End"),
	]

	static func glyph(keyCode: Int) -> KeyGlyph {
		if let character = characters[keyCode] { return KeyGlyph(label: character) }
		if let (symbol, plain, spoken) = symbols[keyCode] {
			return KeyGlyph(symbol: symbol, plain: plain, spoken: spoken)
		}
		if let index = functionKeys.firstIndex(of: keyCode) { return KeyGlyph(label: "F\(index + 1)") }
		switch keyCode {
		case kVK_Space: return KeyGlyph(label: "Space")
		case kVK_Escape: return .escape
		default: return KeyGlyph(label: "Key \(keyCode)")
		}
	}

	static func menuKeyEquivalent(keyCode: Int) -> String? {
		if let character = characters[keyCode] { return character.lowercased() }
		if let index = functionKeys.firstIndex(of: keyCode), let scalar = UnicodeScalar(NSF1FunctionKey + index) {
			return String(Character(scalar))
		}
		switch keyCode {
		case kVK_Space: return " "
		case kVK_Return: return "\r"
		case kVK_Tab: return "\t"
		default: return nil
		}
	}
}
