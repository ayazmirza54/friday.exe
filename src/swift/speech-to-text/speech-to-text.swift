import SwiftUI

// Speech-to-text providers are plugins. To add one:
//  1. add a case to `SpeechToTextProviderID`,
//  2. write a `SpeechToTextProvider` in Providers/ (its session, settings and settings UI),
//  3. return it from `SpeechToTextProviders.provider(id:)`, and add its settings to
//     `SpeechToTextSettings` if it has any.
// The compiler points at every switch that must handle the new case.

enum SpeechToTextProviderID: String, Codable, CaseIterable, Identifiable {
	case claude, openai
	var id: String { rawValue }
}

struct SpeechToTextSettings: Codable, Equatable {
	var provider = SpeechToTextProviderID.claude
	var openai = OpenAISpeechToText.Settings()
}

protocol SpeechToTextProvider {
	var id: SpeechToTextProviderID { get }
	var title: String { get }
	var subtitle: String { get }
	/// SF Symbol name.
	var icon: String { get }
	var credential: ProviderCredential { get }
	func makeSession(config: Config) -> SpeechToTextSession
	/// Provider-specific rows for Settings → Listening.
	@MainActor func settingsSection(model: SettingsModel) -> AnyView
}

enum SpeechToTextProviders {
	static func provider(id: SpeechToTextProviderID) -> SpeechToTextProvider {
		switch id {
		case .claude: return ClaudeSpeechToText()
		case .openai: return OpenAISpeechToText()
		}
	}

	static var all: [SpeechToTextProvider] { SpeechToTextProviderID.allCases.map { provider(id: $0) } }

	/// The provider actually used: one whose credential is missing falls back to Claude (included with the
	/// subscription), and while Claude's is out (see `ServiceHealth`) Bol listens with OpenAI if it has a key.
	static func active(config: Config) -> SpeechToTextProvider {
		let chosen = provider(id: config.speechToText.provider)
		let openAI = OpenAISpeechToText()
		if chosen.id == .claude, SpeechToTextOutage.current != nil, openAI.credential.isSatisfied(by: config) {
			return openAI
		}
		return chosen.credential.isSatisfied(by: config) ? chosen : ClaudeSpeechToText()
	}
}

struct Transcript {
	let text: String
	/// Streaming providers send growing interim text, then a final one per segment.
	let isFinal: Bool
}

/// One utterance. Audio is 16 kHz mono signed 16-bit PCM.
protocol SpeechToTextSession: AnyObject {
	var onTranscript: ((Transcript) -> Void)? { get set }
	/// Why transcription failed, worded for the user (see `ServiceDiagnosis`).
	var onError: ((ServiceProblem) -> Void)? { get set }
	/// Called once, after `flush()` produced its final text (or failed).
	var onFinished: (() -> Void)? { get set }
	/// Whether text arrives while the user is still speaking.
	var isStreamingInterim: Bool { get }

	/// `claudeToken` is set when the provider's credential is `.claudeSubscription`.
	func start(claudeToken: String?)
	func send(pcm: Data)
	func flush()
	func cancel()
}
