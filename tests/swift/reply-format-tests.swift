import Foundation
import Testing

@testable import Bol

@Suite struct ReplyFormatTests {
	@Test func keepsParagraphsAndListItemsOnTheirOwnLines() {
		let reply = """
			Done, restart Bol to pick it up.


			- **What changed:** no more prompts.
			* What I deleted: the checker.
			  - nested
			1) Open Settings
			"""
		#expect(
			ReplyFormat.display(text: reply)
				== "Done, restart Bol to pick it up.\n\n•  **What changed:** no more prompts.\n•  What I deleted: the checker.\n    •  nested\n1.  Open Settings"
		)
	}

	@Test func turnsBlockSyntaxIntoPlainTypography() {
		let reply =
			"## Tests\n> quoted\n---\n| a | b |\n|---|---|\n| 1 | 2 |\nSee [the docs](https://x.y) and __this__."
		#expect(
			ReplyFormat.display(text: reply)
				== "**Tests**\nquoted\n\na  ·  b\n\n1  ·  2\nSee the docs and **this**.")
	}

	@Test func showsCodeVerbatimInMonospace() {
		#expect(ReplyFormat.display(text: "Run:\n```sh\nls -la\n```") == "Run:\n`ls -la`")
	}

	@Test func splitsListItemsFromRunningText() {
		let blocks = ReplyFormat.blocks(paragraph: "Intro\n•  one\n    •  two\n12.  three")
		#expect(
			blocks == [
				.text("Intro"), .item(marker: "•", text: "one", level: 0), .item(marker: "•", text: "two", level: 1),
				.item(marker: "12.", text: "three", level: 0),
			])
	}

	@Test func plainTextHasNoMarkdownSymbols() {
		#expect(ReplyFormat.plain(text: "- **Bold** and `code`\n\nNext") == "•  Bold and code\n\nNext")
	}

	@Test func dropsFilesIntoTheMessageAsPaths() {
		let file = URL(fileURLWithPath: "/tmp/Screen Shot.png")
		#expect(Controller.message(text: "what is this", files: []) == "what is this")
		#expect(
			Controller.message(text: "what is this", files: [file])
				== "[Attached file: /tmp/Screen Shot.png]\n\nwhat is this")
		#expect(Controller.message(text: "", files: [file]).hasPrefix("[Attached file: /tmp/Screen Shot.png]\n\n("))
	}
}
