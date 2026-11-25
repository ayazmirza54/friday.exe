import SwiftUI

// MARK: - Shortcuts

/// Every key Bol answers to: the global shortcuts (changeable), the dictation key, and the keys
/// that only work while the voice bar is up.
struct ShortcutsPane: View {
	@ObservedObject var model: SettingsModel

	private static let dictationKeys = DictationKey.allCases.map {
		SelectOption(
			id: $0.rawValue, title: $0.title,
			subtitle: $0 == .fn ? "The Globe key on Apple keyboards" : "Held on its own")
	}

	private var isCustomized: Bool { model.config.shortcuts != ShortcutSettings() }

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(
				title: "Anywhere on your Mac",
				footer: "Click a shortcut and press the new keys. ⌫ turns it off, Esc cancels.",
				trailing: isCustomized
					? AnyView(
						Button("Reset All") { model.config.shortcuts = ShortcutSettings() }
							.buttonStyle(.plain).font(UI.caption).foregroundStyle(.secondary))
					: nil
			) {
				ForEach(ShortcutAction.allCases) { action in
					SettingsRow(action.title, icon: action.icon, help: help(action: action)) {
						ShortcutRecorder(settings: $model.config.shortcuts, action: action)
					}
				}
			}
			SettingsGroup(title: "Dictation") {
				SettingsRow("Hold to dictate", icon: "text.cursor", help: "Double-tap to go hands-free") {
					Select(
						options: Self.dictationKeys,
						selection: Binding(
							get: { model.config.dictation.key.rawValue },
							set: { model.config.dictation.key = DictationKey(rawValue: $0) ?? .fn }))
				}
			}
			SettingsGroup(
				title: "While the voice bar is up",
				footer:
					"These only belong to Bol while it's listening, working or speaking, so other apps keep Return and Esc."
			) {
				SettingsRow("Send", icon: "arrow.up.circle", help: "While Bol listens; pauses never send") {
					KeyCaps(glyphs: [.returnKey])
				}
				SettingsRow("Stop", icon: "stop.circle", help: "While it speaks: silences it, again to close") {
					KeyCaps(glyphs: [.escape])
				}
			}
			SettingsGroup(title: "In the Bol window") {
				SettingsRow("Previous / next thread", icon: "arrow.up.arrow.down") {
					HStack(spacing: 8) {
						KeyCaps(glyphs: [.command, .shift, KeyGlyph(label: "[")])
						KeyCaps(glyphs: [.command, .shift, KeyGlyph(label: "]")])
					}
				}
				SettingsRow("Search threads", icon: "magnifyingglass") {
					KeyCaps(glyphs: [.command, KeyGlyph(label: "F")])
				}
			}
		}
	}

	private func help(action: ShortcutAction) -> String {
		if !GlobalShortcuts.isAvailable(action: action, config: model.config) {
			return "Turn on Dictation to use it"
		}
		return action.subtitle
	}
}
