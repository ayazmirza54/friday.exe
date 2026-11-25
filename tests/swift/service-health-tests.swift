import Foundation
import Testing

@testable import Bol

@Suite struct ServiceDiagnosisTests {
	@Test func rejectedSignInAsksToSignInAgain() {
		let problem = ServiceDiagnosis.claudeSpeechToText(status: 401, error: nil, serverMessage: nil)
		#expect(problem.fix == .signInToClaude && problem.isOutage)
		#expect(problem.detail.contains("OpenAI"))
	}

	@Test func aChangedEndpointIsAnOutageWithTheOpenAIWayOut() {
		for status in [400, 404, 410, 426] {
			let problem = ServiceDiagnosis.claudeSpeechToText(status: status, error: nil, serverMessage: nil)
			#expect(problem.title == "Claude's speech-to-text has changed")
			#expect(problem.fix == .useOpenAIForListening && problem.isOutage)
		}
	}

	@Test func temporaryTroubleIsNotAnOutage() {
		for status in [429, 500, 503] {
			let problem = ServiceDiagnosis.claudeSpeechToText(status: status, error: nil, serverMessage: nil)
			#expect(problem.fix == .tryAgain && !problem.isOutage)
		}
	}

	@Test func networkFailuresTalkAboutTheConnection() {
		let offline = ServiceDiagnosis.claudeSpeechToText(
			status: nil, error: URLError(.notConnectedToInternet), serverMessage: nil)
		#expect(offline.title == "You're offline" && offline.fix == .checkConnection && !offline.isOutage)
		let unreachable = ServiceDiagnosis.planUsage(status: nil, error: URLError(.cannotFindHost))
		#expect(unreachable.title == "Can't reach Anthropic")
	}

	@Test func serverMessagesPassThrough() {
		let problem = ServiceDiagnosis.claudeSpeechToText(status: nil, error: nil, serverMessage: "audio too short")
		#expect(problem.detail == "audio too short" && problem.fix == .tryAgain)
	}

	@Test func aSuccessfulUpgradeIsNotTreatedAsAnHTTPError() {
		let problem = ServiceDiagnosis.claudeSpeechToText(status: 101, error: nil, serverMessage: nil)
		#expect(problem.title == "Claude's speech-to-text didn't respond")
	}

	@Test func planUsageOnlyBlocksOnLoginProblems() {
		#expect(ServiceDiagnosis.planUsage(status: 401, error: nil).fix == .signInToClaude)
		#expect(ServiceDiagnosis.planUsage(status: 403, error: nil).fix == .signInToClaude)
		let changed = ServiceDiagnosis.planUsage(status: 404, error: nil)
		#expect(changed.fix == .none && changed.isOutage)
		#expect(changed.detail.contains("works without it"))
	}
}

@Suite(.serialized) struct SpeechToTextFallbackTests {
	private func config(openAIKey: String?) -> Config {
		var config = Config()
		config.speechToText.provider = .claude
		config.apiKeys[.openai] = openAIKey
		return config
	}

	@Test func listensWithOpenAIWhileClaudeIsOut() {
		defer { SpeechToTextOutage.record(problem: nil) }
		SpeechToTextOutage.record(
			problem: ServiceDiagnosis.claudeSpeechToText(status: 404, error: nil, serverMessage: nil))
		#expect(SpeechToTextProviders.active(config: config(openAIKey: "sk-test")).id == .openai)
		// Without an OpenAI key there's nothing to fall back to.
		#expect(SpeechToTextProviders.active(config: config(openAIKey: nil)).id == .claude)
	}

	@Test func usesClaudeWhenItWorks() {
		SpeechToTextOutage.record(problem: nil)
		#expect(SpeechToTextProviders.active(config: config(openAIKey: "sk-test")).id == .claude)
	}
}
