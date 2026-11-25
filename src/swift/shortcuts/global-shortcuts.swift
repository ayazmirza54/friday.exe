import AppKit
import Combine

/// The shortcuts as configured, for the windows and the voice bar that show them. Kept in step
/// with the config by `GlobalShortcuts.apply`.
final class ShortcutState: ObservableObject {
	static let shared = ShortcutState()

	@Published private(set) var settings = ShortcutSettings()
	/// Actions whose shortcut macOS refused: another app already has that combination.
	@Published private(set) var unavailable: Set<ShortcutAction> = []
	/// The action whose shortcut recorder is listening for keys. Meanwhile the global shortcuts
	/// step aside, so pressing the current one records it instead of triggering it.
	@Published var recording: ShortcutAction? {
		didSet {
			let isRecording = recording != nil
			if isRecording != (oldValue != nil) { HotKey.setAllSuspended(isSuspended: isRecording) }
		}
	}

	/// The Talk shortcut as text, for sentences ("Press ⌘J anywhere to talk"), or a pointer to
	/// the menu bar when it's off.
	var talkText: String { settings.talk?.plainText ?? "the menu bar icon" }

	fileprivate func update(settings: ShortcutSettings, unavailable: Set<ShortcutAction>) {
		if self.settings != settings { self.settings = settings }
		if self.unavailable != unavailable { self.unavailable = unavailable }
	}
}

/// Registers Bol's global shortcuts from the config, and re-registers only what changed.
final class GlobalShortcuts {
	private var hotKeys: [ShortcutAction: HotKey] = [:]
	private var registered: [ShortcutAction: Shortcut] = [:]
	private var unavailable: Set<ShortcutAction> = []
	private let handler: (ShortcutAction) -> Void

	init(handler: @escaping (ShortcutAction) -> Void) {
		self.handler = handler
	}

	/// Shows the config's shortcuts everywhere; registers them only once `isActive` (after setup).
	func apply(config: Config, isActive: Bool) {
		let wanted = Dictionary(
			uniqueKeysWithValues: ShortcutAction.allCases.map { action in
				(action, isActive && Self.isAvailable(action: action, config: config) ? config.shortcuts[action] : nil)
			})
		let changed = ShortcutAction.allCases.filter { action in
			wanted[action] != registered[action] || (wanted[action] != nil && hotKeys[action] == nil)
		}
		// Unregister everything that changes first: two actions may swap combinations.
		for action in changed {
			hotKeys[action] = nil
			registered[action] = wanted[action] ?? nil
			unavailable.remove(action)
		}
		for action in changed {
			guard let wanted = wanted[action] ?? nil else { continue }
			if let hotKey = HotKey(
				keyCode: wanted.keyCode, modifiers: wanted.carbonModifiers,
				handler: { [weak self] in
					self?.handler(action)
				})
			{
				hotKeys[action] = hotKey
			} else {
				unavailable.insert(action)
				Log.info(
					message:
						"shortcuts: \(wanted.plainText) for \(action.rawValue) unavailable (another app may own it)")
			}
		}
		ShortcutState.shared.update(settings: config.shortcuts, unavailable: unavailable)
	}

	/// Paste Last only exists while dictation is on.
	static func isAvailable(action: ShortcutAction, config: Config) -> Bool {
		switch action {
		case .pasteLastDictation: return config.dictation.isEnabled
		case .talk, .openBol, .newConversation: return true
		}
	}
}
