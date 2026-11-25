import AVFoundation
import SwiftUI

// Voice (text-to-speech) providers are plugins. To add one:
//  1. add a case to `TextToSpeechProviderID`,
//  2. write a `TextToSpeechProvider` in Providers/ (synthesis, settings and settings UI),
//  3. return it from `TextToSpeechProviders.provider(id:)` and add its settings to
//     `TextToSpeechSettings`.
// The compiler points at every switch that must handle the new case. `Speaker` plays whatever
// PCM a provider streams, and falls back to the macOS voice when a cloud provider fails.

enum TextToSpeechProviderID: String, Codable, CaseIterable, Identifiable {
	case openai, noiz, system
	var id: String { rawValue }
}

struct TextToSpeechSettings: Codable, Equatable {
	var provider = TextToSpeechProviderID.openai
	var openai = OpenAITextToSpeech.Settings()
	var noiz = NoizTextToSpeech.Settings()
	var system = SystemTextToSpeech.Settings()
}

protocol TextToSpeechProvider {
	var id: TextToSpeechProviderID { get }
	var title: String { get }
	var subtitle: String { get }
	/// SF Symbol name.
	var icon: String { get }
	var credential: ProviderCredential { get }
	/// Audio for `text` in any PCM format, as it becomes available. Throw `TextToSpeechFailure`
	/// to say what is still unspoken, so the macOS voice can say it instead.
	func synthesize(text: String, config: Config) -> AsyncThrowingStream<AVAudioPCMBuffer, Error>
	/// Provider-specific sections for Settings → Voice.
	@MainActor func settingsSection(model: SettingsModel) -> AnyView
}

struct TextToSpeechFailure: Error {
	let reason: String
	/// Text not yet spoken, if known; nil when the provider failed mid-sentence.
	let unspokenText: String?
}

enum TextToSpeechProviders {
	static func provider(id: TextToSpeechProviderID) -> TextToSpeechProvider {
		switch id {
		case .openai: return OpenAITextToSpeech()
		case .noiz: return NoizTextToSpeech()
		case .system: return SystemTextToSpeech()
		}
	}

	static var all: [TextToSpeechProvider] { TextToSpeechProviderID.allCases.map { provider(id: $0) } }

	/// The provider actually used: one without its API key falls back to the macOS voice.
	static func active(config: Config) -> TextToSpeechProvider {
		let chosen = provider(id: config.textToSpeech.provider)
		return chosen.credential.isSatisfied(by: config) ? chosen : SystemTextToSpeech()
	}
}

/// Text cleanup and splitting shared by providers.
enum SpeechText {
	/// Markdown and code stripped: what should be read aloud.
	static func cleaned(text: String) -> String {
		var t = text
		t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
		t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "(?m)^\\s*[#>*-]+\\s*", with: "", options: .regularExpression)
		t = t.replacingOccurrences(of: "[*_#]", with: "", options: .regularExpression)
		t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
		return t.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Sentence-sized pieces (short sentences merged); the first is kept short so audio starts quickly.
	static func split(text: String, firstLimit: Int = 80, limit: Int = 140) -> [String] {
		var sentences: [String] = []
		text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
			if let s = sentence?.trimmingCharacters(in: .whitespaces), !s.isEmpty { sentences.append(s) }
		}
		guard !sentences.isEmpty else { return [text] }
		var parts: [String] = []
		var current = ""
		for sentence in sentences {
			let partLimit = parts.isEmpty ? firstLimit : limit
			if current.isEmpty {
				current = sentence
			} else if current.count + sentence.count + 1 <= partLimit {
				current += " " + sentence
			} else {
				parts.append(current)
				current = sentence
			}
		}
		if !current.isEmpty { parts.append(current) }
		return parts
	}

	/// Short, human version of a provider error.
	static func friendlyFailure(reason: String) -> String {
		let r = reason.lowercased()
		if r.contains("401") || (r.contains("invalid") && r.contains("key")) { return "API key was rejected" }
		if r.contains("402") || r.contains("payment") || r.contains("credit") || r.contains("quota") {
			return "Out of credits"
		}
		if r.contains("429") || r.contains("rate") { return "Rate limited, try again in a moment" }
		if r.contains("timed out") || r.contains("timeout") { return "The voice service timed out" }
		if r.contains("offline") || r.contains("network") || r.contains("internet") { return "No internet connection" }
		return "The voice service returned an error"
	}
}
