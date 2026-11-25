import Testing

@testable import Bol

@Suite struct IntentTests {
	@Test(arguments: [
		"Send it to the background.", "background", "Background it", "move this to background",
		"Keep going in the background", "do it in the background please", "put that in the background",
	])
	func recognizesBackgroundCommands(text: String) {
		#expect(Intent.isBackgroundCommand(text: text))
	}

	@Test(arguments: [
		"what apps are running in the background", "change my desktop background", "send an email to Priya",
		"in the background, find flights to Goa",
	])
	func ignoresOtherSentences(text: String) {
		#expect(!Intent.isBackgroundCommand(text: text))
	}

	@Test(arguments: [
		"Stop.", "stop it", "Never mind", "nevermind that", "Cancel that please", "OK stop", "Shut up", "Forget it.",
	])
	func recognizesStopCommands(text: String) {
		#expect(Intent.isStopCommand(text: text))
	}

	@Test(arguments: [
		"Never mind that. What is 12 plus 30?", "Stop the music and open Notes", "Cancel my 3pm meeting",
		"Quiet hours start at ten, set that up", "What is the stop loss on this order",
	])
	func treatsRequestsStartingWithStopWordsAsRequests(text: String) {
		#expect(!Intent.isStopCommand(text: text))
	}

	@Test func extractsBackgroundRequests() {
		#expect(Intent.backgroundRequest(text: "In the background, find flights to Goa.") == "find flights to Goa")
		#expect(
			Intent.backgroundRequest(text: "Summarize my unread email and do it in the background")
				== "Summarize my unread email")
		#expect(
			Intent.backgroundRequest(text: "Clean up my Downloads folder as a background task")
				== "Clean up my Downloads folder")
		#expect(Intent.backgroundRequest(text: "what apps are running in the background") == nil)
		#expect(Intent.backgroundRequest(text: "change my desktop background to blue") == nil)
	}

	@Test func extractsForegroundRequests() {
		#expect(
			Intent.foregroundRequest(text: "In the foreground, open Notes and write a list.")
				== "open Notes and write a list")
		#expect(Intent.foregroundRequest(text: "Book a table for two, stay with me") == "Book a table for two")
		#expect(
			Intent.foregroundRequest(text: "Fill in the form on screen and do it in front of me")
				== "Fill in the form on screen")
		#expect(Intent.foregroundRequest(text: "Rename these files, keep it in the foreground") == "Rename these files")
		// Ordinary requests run in the background.
		#expect(Intent.foregroundRequest(text: "What's the weather tomorrow?") == nil)
		#expect(Intent.foregroundRequest(text: "bring Safari to the foreground") == nil)
		#expect(Intent.foregroundRequest(text: "Play something to dance with me") == nil)
	}
}
