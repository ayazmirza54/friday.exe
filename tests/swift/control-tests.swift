import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import Bol

@Suite struct KeyComboTests {
	@Test func parsesPlainKeys() {
		#expect(KeyCombo.parse(text: "return") == KeyCombo(keyCode: CGKeyCode(kVK_Return), modifiers: []))
		#expect(KeyCombo.parse(text: "Escape")?.keyCode == CGKeyCode(kVK_Escape))
		#expect(KeyCombo.parse(text: "f5")?.keyCode == CGKeyCode(kVK_F5))
		#expect(KeyCombo.parse(text: "a")?.keyCode == CGKeyCode(kVK_ANSI_A))
	}

	@Test func parsesCombinations() {
		#expect(
			KeyCombo.parse(text: "cmd+shift+a")
				== KeyCombo(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: [.command, .shift]))
		#expect(
			KeyCombo.parse(text: "ctrl + alt + delete")
				== KeyCombo(keyCode: CGKeyCode(kVK_Delete), modifiers: [.control, .option]))
		#expect(KeyCombo.parse(text: "command+tab")?.flags == .maskCommand)
		#expect(
			KeyCombo.parse(text: "cmd++")
				== KeyCombo(keyCode: CGKeyCode(kVK_ANSI_Equal), modifiers: [.command, .shift])
		)
	}

	@Test func parsesModifiersAloneForClicks() {
		#expect(KeyCombo.parse(text: "shift") == KeyCombo(keyCode: nil, modifiers: [.shift]))
		#expect(KeyCombo.parse(text: "cmd+shift")?.flags == [.maskCommand, .maskShift])
	}

	@Test(arguments: ["", "cmd+", "banana", "a+b", "cmd+notakey"])
	func rejectsUnknownKeys(text: String) {
		#expect(KeyCombo.parse(text: text) == nil)
	}
}

@Suite struct ScreenMappingTests {
	@Test func keepsSmallDisplaysAtOnePixelPerPoint() {
		let mapping = ScreenMapping(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), displayName: "Built-in")
		#expect(mapping.scale == 1)
		#expect(mapping.imageSize == CGSize(width: 1512, height: 982))
		#expect(mapping.screenPoint(imageX: 100, imageY: 50) == CGPoint(x: 100, y: 50))
	}

	@Test func downsamplesLargeDisplaysAndMapsBack() {
		let mapping = ScreenMapping(frame: CGRect(x: 0, y: 0, width: 3136, height: 1764), displayName: "Big")
		#expect(mapping.scale == 0.5)
		#expect(mapping.imageSize == CGSize(width: 1568, height: 882))
		#expect(mapping.screenPoint(imageX: 784, imageY: 441) == CGPoint(x: 1568, y: 882))
		#expect(mapping.imagePoint(screen: CGPoint(x: 1568, y: 882)) == CGPoint(x: 784, y: 441))
	}

	@Test func offsetsSecondaryDisplaysAndClampsToTheirBounds() {
		let mapping = ScreenMapping(frame: CGRect(x: 1512, y: -200, width: 1000, height: 800), displayName: "Side")
		#expect(mapping.screenPoint(imageX: 10, imageY: 20) == CGPoint(x: 1522, y: -180))
		#expect(mapping.screenPoint(imageX: 5000, imageY: -40) == CGPoint(x: 2511, y: -200))
	}
}

@Suite struct ControlActionTests {
	private func decode(json: String) throws -> ControlAction {
		try JSONDecoder().decode(ControlAction.self, from: Data(json.utf8))
	}

	@Test func decodesAClick() throws {
		let action = try decode(json: #"{"name":"left_click","coordinate":[640,400],"text":"shift"}"#)
		#expect(action.name == .leftClick)
		#expect(action.coordinate == [640, 400])
		#expect(action.text == "shift")
	}

	@Test func decodesABatch() throws {
		let action = try decode(
			json:
				#"{"name":"computer_batch","actions":[{"name":"scroll","coordinate":[1,2],"scrollDirection":"down","scrollAmount":5},{"name":"key","text":"cmd+a","repeat":2}]}"#
		)
		#expect(action.name == .batch)
		#expect(action.actions?.count == 2)
		#expect(action.actions?[0].scrollDirection == "down")
		#expect(action.actions?[0].scrollAmount == 5)
		#expect(action.actions?[1].repeat == 2)
	}

	@Test func rejectsUnknownActions() {
		#expect(throws: (any Error).self) { try decode(json: #"{"name":"format_disk"}"#) }
	}
}
