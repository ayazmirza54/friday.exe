import AVFoundation
import SwiftUI

/// OpenAI TTS, streamed as raw 24 kHz mono s16le PCM.
struct OpenAITextToSpeech: TextToSpeechProvider {
	struct Settings: Codable, Equatable {
		var model = "gpt-4o-mini-tts"
		var voice = "nova"
		/// Speaking style; only gpt-4o models follow it.
		var instructions =
			"Speak as a warm, friendly, confident young woman: natural and conversational, relaxed but brisk pace, a hint of a smile in the voice. Never robotic or overly dramatic."
	}

	let id = TextToSpeechProviderID.openai
	let title = "OpenAI"
	let subtitle = "Fast streaming voices"
	let icon = "bolt"
	let credential = ProviderCredential.apiKey(.openai)

	private static let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!
	private static let sourceFormat = PCM.int16Format(sampleRate: 24000)
	private static let voices: [SelectOption] = [
		("nova", "Bright, warm"), ("shimmer", "Soft, gentle"), ("coral", "Warm, friendly"),
		("sage", "Calm, measured"), ("alloy", "Neutral, balanced"), ("ash", "Clear, male"),
		("ballad", "Smooth, male"), ("echo", "Resonant, male"), ("fable", "Expressive, British"),
		("onyx", "Deep, male"), ("verse", "Dynamic, male"),
	].map { SelectOption(id: $0.0, title: $0.0.capitalized, subtitle: $0.1) }
	private static let models: [SelectOption] = [
		SelectOption(id: "gpt-4o-mini-tts", title: "gpt-4o-mini-tts", subtitle: "Expressive, follows a speaking style"),
		SelectOption(id: "tts-1", title: "tts-1", subtitle: "Fastest"),
		SelectOption(id: "tts-1-hd", title: "tts-1-hd", subtitle: "Higher fidelity"),
	]

	private static func isFollowingInstructions(model: String) -> Bool { model.contains("gpt-4o") }

	func synthesize(text: String, config: Config) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
		let settings = config.textToSpeech.openai
		var request = URLRequest(url: Self.endpoint)
		request.httpMethod = "POST"
		request.setValue("Bearer \(config.apiKeys[.openai] ?? "")", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		var body: [String: Any] = [
			"model": settings.model, "voice": settings.voice, "input": text, "response_format": "pcm",
		]
		if !settings.instructions.isEmpty, Self.isFollowingInstructions(model: settings.model) {
			body["instructions"] = settings.instructions
		}
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)

		return AsyncThrowingStream { continuation in
			let task = Task {
				var hasYielded = false
				do {
					let (bytes, response) = try await URLSession.shared.bytes(for: request)
					if let http = response as? HTTPURLResponse, http.statusCode != 200 {
						var message = ""
						for try await line in bytes.lines {
							message += line
							if message.count > 400 { break }
						}
						throw TextToSpeechFailure(
							reason: "OpenAI HTTP \(http.statusCode): \(message)", unspokenText: text)
					}
					// First chunk ~0.1 s for low latency, then ~0.5 s chunks.
					let bytesPerSecond = Int(Self.sourceFormat.sampleRate) * 2
					var chunk = Data()
					for try await byte in bytes {
						chunk.append(byte)
						if chunk.count >= (hasYielded ? bytesPerSecond / 2 : bytesPerSecond / 10) {
							let usable = chunk.count - chunk.count % 2
							if let buffer = PCM.buffer(int16Data: chunk.prefix(usable), format: Self.sourceFormat) {
								continuation.yield(buffer)
								hasYielded = true
							}
							chunk.removeFirst(usable)
						}
					}
					if let buffer = PCM.buffer(int16Data: chunk, format: Self.sourceFormat) {
						continuation.yield(buffer)
					}
					continuation.finish()
				} catch let failure as TextToSpeechFailure {
					continuation.finish(throwing: failure)
				} catch {
					continuation.finish(
						throwing: TextToSpeechFailure(
							reason: "OpenAI stream failed: \(error)", unspokenText: hasYielded ? nil : text))
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	@MainActor func settingsSection(model: SettingsModel) -> AnyView {
		AnyView(
			Group {
				SettingsGroup(title: "OpenAI") {
					SettingsRow("API key", icon: "key") {
						KeyField(value: model.apiKeyBinding(id: .openai), validation: model.keyValidation(id: .openai))
						{
							model.checkKey(id: .openai)
						}
					}
					SettingsRow("Voice", icon: "person.wave.2") {
						Select(
							options: Self.voices,
							selection: Binding(root: model, keyPath: \.config.textToSpeech.openai.voice),
							isSearchable: true, prompt: "Search voices")
					}
					SettingsRow("Model", icon: "cpu") {
						Select(
							options: Self.models,
							selection: Binding(root: model, keyPath: \.config.textToSpeech.openai.model))
					}
				}
				if Self.isFollowingInstructions(model: model.config.textToSpeech.openai.model) {
					SettingsGroup(
						title: "Speaking style", footer: "Tone, pace and personality. Only gpt-4o voices follow this."
					) {
						TextEditor(text: Binding(root: model, keyPath: \.config.textToSpeech.openai.instructions))
							.font(UI.body)
							.scrollContentBackground(.hidden)
							.frame(height: 64)
							.padding(10)
					}
				}
			}
		)
	}
}
