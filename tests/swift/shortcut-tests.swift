import Carbon.HIToolbox
import Foundation
import Testing

@testable import Bol

@Suite struct ShortcutTests {
	@Test func showsModifiersInMacOrder() {
		let shortcut = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.shift, .option])
		#expect(shortcut.plainText == "⌥⇧V")
		#expect(shortcut.spokenText == "Option Shift V")
		#expect(shortcut.glyphs.map(\.symbol) == ["option", "shift", nil])
		#expect(shortcut.carbonModifiers == optionKey | shiftKey)
		#expect(shortcut.menuKeyEquivalent == "v")
		#expect(shortcut.menuModifierMask == [.option, .shift])
	}

	@Test func defaultsAreTalkAndPasteLast() {
		let settings = ShortcutSettings()
		#expect(settings.talk?.plainText == "⌘J")
		#expect(settings.pasteLastDictation?.plainText == "⌥⇧V")
		#expect(settings.openBol == nil)
		#expect(settings.newConversation == nil)
	}

	@Test func refusesCombinationsThatGetInTheWay() {
		let settings = ShortcutSettings()
		let plainLetter = Shortcut(keyCode: kVK_ANSI_K, modifiers: [.shift])
		#expect(settings.problem(shortcut: plainLetter, action: .openBol) != nil)
		let copy = Shortcut(keyCode: kVK_ANSI_C, modifiers: [.command])
		#expect(settings.problem(shortcut: copy, action: .openBol) == "⌘C is Copy in every app")
		let taken = Shortcut(keyCode: kVK_ANSI_J, modifiers: [.command])
		#expect(settings.problem(shortcut: taken, action: .openBol) == "Already used for Talk to Bol")
		#expect(settings.problem(shortcut: taken, action: .talk) == nil)  // its own shortcut again
		#expect(settings.problem(shortcut: Shortcut(keyCode: kVK_F5, modifiers: []), action: .openBol) == nil)
		#expect(
			settings.problem(shortcut: Shortcut(keyCode: kVK_ANSI_B, modifiers: [.control, .option]), action: .openBol)
				== nil)
	}

	@Test func aClearedShortcutStaysCleared() throws {
		var config = Config()
		config.shortcuts.talk = nil
		config.shortcuts.openBol = Shortcut(keyCode: kVK_ANSI_B, modifiers: [.command, .option])
		let reloaded = try Config.decoded(data: JSONEncoder().encode(config))
		#expect(reloaded.shortcuts.talk == nil)
		#expect(reloaded.shortcuts.openBol == config.shortcuts.openBol)
		#expect(reloaded.shortcuts.pasteLastDictation == ShortcutSettings().pasteLastDictation)
	}

	@Test func missingShortcutsTakeTheirDefaults() throws {
		let config = try Config.decoded(data: Data(#"{"shortcuts": {"openBol": null}}"#.utf8))
		#expect(config.shortcuts.talk == ShortcutSettings().talk)
		#expect(config.shortcuts.openBol == nil)
	}

	@Test func theOldPasteLastSwitchClearsItsShortcut() throws {
		let off = try Config.decoded(data: Data(#"{"dictation": {"isPasteLastEnabled": false}}"#.utf8))
		#expect(off.shortcuts.pasteLastDictation == nil)
		let on = try Config.decoded(data: Data(#"{"dictation": {"isPasteLastEnabled": true}}"#.utf8))
		#expect(on.shortcuts.pasteLastDictation == ShortcutSettings().pasteLastDictation)
	}

	@Test func namesSpecialKeys() {
		#expect(KeyNames.glyph(keyCode: kVK_Space).plain == "Space")
		#expect(KeyNames.glyph(keyCode: kVK_F12).plain == "F12")
		#expect(KeyNames.glyph(keyCode: kVK_Return).symbol == "return")
		#expect(DictationKey.rightOption.glyph.plain == "right ⌥")
	}
}
