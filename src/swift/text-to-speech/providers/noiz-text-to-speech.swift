import AVFoundation
import SwiftUI

/// Noiz AI voices. Noiz returns audio only once a request is fully synthesized (~2.5-8 s), so
/// replies are split into sentences synthesized in parallel (max 3 in flight, Noiz's rate limit)
/// and played in order: the first plays as soon as it's ready while the rest finish behind it.
struct NoizTextToSpeech: TextToSpeechProvider {
	struct Settings: Codable, Equatable {
		var voiceId = "0e4ab6ec"  // Maya: young, calm, empathetic
		var speed = 1.0
		/// 1 (fastest) ... 5 (best quality).
		var qualityPreset = 3
		/// nil = detected from the text.
		var language: String? = nil
		/// nil = chosen by language.
		var model: String? = nil
		/// Emotion weights as JSON, e.g. {"Joy":0.4}; nil = neutral.
		var emotion: String? = nil
	}

	let id = TextToSpeechProviderID.noiz
	let title = "Noiz AI"
	let subtitle = "Lifelike, expressive voices"
	let icon = "waveform"
	let credential = ProviderCredential.apiKey(.noiz)

	private static let endpoint = URL(string: "https://noiz.ai/v1/text-to-speech")!
	private static let maxConcurrentRequests = 3

	func synthesize(text: String, config: Config) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
		let parts = SpeechText.split(text: text)
		let settings = config.textToSpeech.noiz
		let apiKey = config.apiKeys[.noiz] ?? ""
		return AsyncThrowingStream { continuation in
			// Part i waits for part i-3, so at most three requests are in flight.
			let fetches = parts.indices.reduce(into: [Task<AVAudioPCMBuffer?, Error>]()) { fetches, i in
				let prior = i >= Self.maxConcurrentRequests ? fetches[i - Self.maxConcurrentRequests] : nil
				let part = parts[i]
				fetches.append(
					Task {
						if let prior { _ = try? await prior.value }
						return try await Self.fetch(text: part, settings: settings, apiKey: apiKey)
					})
			}
			let player = Task {
				for (i, fetch) in fetches.enumerated() {
					do {
						if let buffer = try await fetch.value { continuation.yield(buffer) }
					} catch {
						continuation.finish(
							throwing: TextToSpeechFailure(
								reason: "Noiz failed: \(error.localizedDescription)",
								unspokenText: parts[i...].joined(separator: " ")))
						return
					}
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in
				player.cancel()
				for fetch in fetches { fetch.cancel() }
			}
		}
	}

	/// One Noiz request: the audio for `text`.
	private static func fetch(text: String, settings: Settings, apiKey: String) async throws -> AVAudioPCMBuffer? {
		let boundary = "bol-\(UUID().uuidString)"
		let fields: [(String, String?)] = [
			("text", text),
			("output_format", "wav"),
			("speed", String(settings.speed)),
			("quality_preset", String(settings.qualityPreset)),
			("trim_silence", "true"),
			("voice_id", settings.voiceId.isEmpty ? nil : settings.voiceId),
			("target_lang", settings.language),
			("model_id", settings.model),
			("emo", settings.emotion),
		]
		var body = Data()
		for (name, value) in fields {
			guard let value else { continue }
			body.append(
				Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
		}
		body.append(Data("--\(boundary)--\r\n".utf8))

		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.setValue(apiKey, forHTTPHeaderField: "Authorization")  // the raw key, no "Bearer"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.httpBody = body
		request.timeoutInterval = 45

		let (data, response) = try await URLSession.shared.data(for: request)
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		// Errors (including rate limits, which arrive as HTTP 200) are JSON, not audio.
		let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
		guard status == 200, !contentType.contains("json") else {
			let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
			throw NSError(
				domain: "Noiz", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status): \(message)"])
		}
		let wav = try PCM.parseWAV(data: data)
		return PCM.buffer(int16Data: wav.pcm, format: wav.format)
	}

	// MARK: Settings UI

	fileprivate static let emotions: [SelectOption] = [
		SelectOption(id: "", title: "Neutral", subtitle: "Plain delivery"),
		SelectOption(id: "{\"Joy\":0.4,\"Tenderness\":0.3}", title: "Warm", subtitle: "Friendly and kind"),
		SelectOption(id: "{\"Joy\":0.7,\"Excitement\":0.3}", title: "Cheerful", subtitle: "Upbeat"),
		SelectOption(id: "{\"Tenderness\":0.5}", title: "Calm", subtitle: "Soft and soothing"),
		SelectOption(id: "{\"Excitement\":0.6,\"Joy\":0.4}", title: "Energetic", subtitle: "Lively"),
	]
	fileprivate static let models: [SelectOption] = [
		SelectOption(id: "", title: "Automatic", subtitle: "Chosen by language"),
		SelectOption(id: "v1", title: "v1"), SelectOption(id: "v2", title: "v2"),
	]
	fileprivate static let qualityPresets: [SelectOption] = [
		SelectOption(id: "1", title: "1", subtitle: "Fastest"),
		SelectOption(id: "2", title: "2"),
		SelectOption(id: "3", title: "3 · Default"),
		SelectOption(id: "4", title: "4"),
		SelectOption(id: "5", title: "5", subtitle: "Best quality"),
	]

	@MainActor func settingsSection(model: SettingsModel) -> AnyView {
		AnyView(NoizSettingsSection(model: model))
	}
}

private struct NoizSettingsSection: View {
	@ObservedObject var model: SettingsModel
	@ObservedObject private var library = NoizVoiceLibrary.shared

	private static let knownVoices = [
		"0e4ab6ec": ("The Mentor (Maya)", "English, young, female, calm, empathetic"),
		"5a68d66b": ("The Healer (Serena)", "English, young, female, calm"),
	]

	private var settings: NoizTextToSpeech.Settings { model.config.textToSpeech.noiz }

	var body: some View {
		SettingsGroup(title: "Noiz AI") {
			SettingsRow("API key", icon: "key") {
				KeyField(value: model.apiKeyBinding(id: .noiz), validation: model.keyValidation(id: .noiz)) {
					model.checkKey(id: .noiz)
				}
			}
			SettingsRow("Voice", icon: "person.wave.2", help: library.error) {
				HStack(spacing: 4) {
					Select(
						options: voiceOptions, selection: $model.config.textToSpeech.noiz.voiceId, isSearchable: true,
						prompt: "Search voices", width: UI.controlWidth - 30)
					IconButton(symbol: "arrow.clockwise", help: "Reload voices", isSpinning: library.isLoading) {
						library.load(apiKey: model.config.apiKeys[.noiz])
					}
				}
			}
			SettingsRow("Voice ID", icon: "number", help: "Any voice ID, including cloned voices") {
				Field(placeholder: "Voice ID", text: $model.config.textToSpeech.noiz.voiceId, isMonospaced: true)
			}
		}
		.onAppear {
			if library.voices.isEmpty, model.keyValidation(id: .noiz) == .valid {
				library.load(apiKey: model.config.apiKeys[.noiz])
			}
		}
		.onChange(of: model.keyValidation(id: .noiz)) { validation in
			if validation == .valid, library.voices.isEmpty { library.load(apiKey: model.config.apiKeys[.noiz]) }
		}

		SettingsGroup(title: "Delivery") {
			SettingsRow("Emotion", icon: "face.smiling") {
				Select(options: emotionOptions, selection: $model.config.textToSpeech.noiz.emotion.emptyAsNil)
			}
			SettingsRow("Speed", icon: "gauge.with.dots.needle.33percent") {
				ValueSlider(value: $model.config.textToSpeech.noiz.speed, range: 0.5...2.0, step: 0.05) {
					String(format: "%.2f×", $0)
				}
			}
			SettingsRow("Model", icon: "cpu") {
				Select(options: NoizTextToSpeech.models, selection: $model.config.textToSpeech.noiz.model.emptyAsNil)
			}
			SettingsRow("Quality", icon: "dial.medium") {
				Select(
					options: NoizTextToSpeech.qualityPresets,
					selection: Binding(
						get: { String(settings.qualityPreset) },
						set: { model.config.textToSpeech.noiz.qualityPreset = Int($0) ?? 3 }))
			}
		}
	}

	private var emotionOptions: [SelectOption] {
		var options = NoizTextToSpeech.emotions
		if let custom = settings.emotion, !options.contains(where: { $0.id == custom }) {
			options.append(SelectOption(id: custom, title: "Custom", subtitle: custom))
		}
		return options
	}

	private var voiceOptions: [SelectOption] {
		var options = library.voices.map { SelectOption(id: $0.id, title: $0.name, subtitle: $0.detail) }
		let id = settings.voiceId
		if !id.isEmpty, !options.contains(where: { $0.id == id }) {
			let known = Self.knownVoices[id]
			options.insert(SelectOption(id: id, title: known?.0 ?? id, subtitle: known?.1 ?? "Custom voice"), at: 0)
		}
		return options
	}
}

struct NoizVoice: Identifiable, Hashable {
	let id: String
	let name: String
	let detail: String
}

/// Built-in and custom Noiz voices, loaded once and kept for the app's lifetime.
final class NoizVoiceLibrary: ObservableObject {
	static let shared = NoizVoiceLibrary()

	@Published private(set) var voices: [NoizVoice] = []
	@Published private(set) var isLoading = false
	@Published private(set) var error: String?

	func load(apiKey: String?) {
		guard let apiKey else {
			error = "Add your API key to load voices."
			return
		}
		guard !isLoading else { return }
		isLoading = true
		error = nil
		Task { @MainActor in
			async let builtIn = Self.fetch(type: "built-in", apiKey: apiKey)
			async let custom = Self.fetch(type: "custom", apiKey: apiKey)
			let found = await builtIn + custom
			var seen = Set<String>()
			voices = found.filter { seen.insert($0.id).inserted }
			isLoading = false
			error = found.isEmpty ? "Couldn't load voices. Check the key and try again." : nil
		}
	}

	private static func fetch(type: String, apiKey: String) async -> [NoizVoice] {
		guard let url = URL(string: "https://noiz.ai/v1/voices?voice_type=\(type)&limit=100") else { return [] }
		var request = URLRequest(url: url)
		request.setValue(apiKey, forHTTPHeaderField: "Authorization")
		request.timeoutInterval = 15
		guard let (data, _) = try? await URLSession.shared.data(for: request),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let voices = (object["data"] as? [String: Any])?["voices"] as? [[String: Any]]
		else { return [] }
		return voices.compactMap { voice in
			guard let id = voice["voice_id"] as? String else { return nil }
			let labels = Self.labels(value: voice["labels"])
			let detail = type == "custom" ? "Your voice" + (labels.isEmpty ? "" : " · \(labels)") : labels
			return NoizVoice(id: id, name: voice["display_name"] as? String ?? id, detail: detail)
		}
	}

	/// Noiz returns labels as an array, an object or a comma-separated string.
	private static func labels(value: Any?) -> String {
		let parts: [String]
		switch value {
		case let list as [String]: parts = list
		case let object as [String: Any]: parts = object.values.map { "\($0)" }
		case let text as String: parts = text.split(separator: ",").map(String.init)
		default: parts = []
		}
		return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
	}
}
