import AVFoundation

/// Plays what the active text-to-speech provider streams. Any cloud failure falls back to the
/// macOS voice for whatever is still unspoken, so Bol never goes silent. Main thread only.
final class Speaker {
	/// Progress of one utterance, for UI feedback (e.g. the Settings "Play Sample" button).
	enum Event {
		/// First audio is playing.
		case started(TextToSpeechProviderID)
		/// The cloud voice failed; the macOS voice is used instead.
		case fellBack(reason: String)
	}

	/// One `speak` call. Callbacks from a stopped utterance are ignored by identity.
	private final class Utterance {
		let onEvent: ((Event) -> Void)?
		let completion: () -> Void
		var task: Task<Void, Never>?
		var scheduledBufferCount = 0
		var isStreamFinished = false
		var hasStarted = false

		init(onEvent: ((Event) -> Void)?, completion: @escaping () -> Void) {
			self.onEvent = onEvent
			self.completion = completion
		}
	}

	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	/// Everything is converted to this before scheduling.
	private let format = AVAudioFormat(
		commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
	private var converters: [AVAudioFormat: AVAudioConverter] = [:]
	private var utterance: Utterance?
	/// Pauses the engine after a silence, so nothing renders (and no output device stays open) while idle.
	private var idleWork: DispatchWorkItem?
	/// Loudness of what Bol is saying right now (0...1), for the voice visualizer.
	private(set) var level: Float = 0

	var isSpeaking: Bool { utterance != nil }

	init() {
		engine.attach(player)
		engine.connect(player, to: engine.mainMixerNode, format: format)
		// Measure the output so the HUD's bars move with Bol's actual voice.
		engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
			if let level = PCM.level(buffer: buffer, gain: 5) { self?.level = level }
		}
	}

	func speak(text raw: String, config: Config, onEvent: ((Event) -> Void)? = nil, completion: @escaping () -> Void) {
		stop()
		let text = SpeechText.cleaned(text: raw)
		guard !text.isEmpty else {
			completion()
			return
		}
		let current = Utterance(onEvent: onEvent, completion: completion)
		utterance = current
		idleWork?.cancel()
		idleWork = nil
		if !engine.isRunning {
			do {
				try engine.start()
			} catch {
				// No output device (a Mac mini with nothing plugged in): nothing can play, so finish now
				// rather than wait forever for buffers that never drain. The reply stays on screen.
				Log.info(message: "tts: engine start failed \(error)")
				DispatchQueue.main.async { [weak self] in
					if current === self?.utterance { self?.stop() }
				}
				return
			}
		}
		player.play()
		let provider = TextToSpeechProviders.active(config: config)
		current.task = Task { @MainActor [weak self] in
			await self?.play(text: text, provider: provider, config: config, utterance: current)
		}
	}

	func stop() {
		guard let current = utterance else { return }
		utterance = nil
		current.task?.cancel()
		level = 0
		player.stop()
		scheduleIdlePause()
		current.completion()
	}

	private func scheduleIdlePause() {
		idleWork?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self, self.utterance == nil else { return }
			self.idleWork = nil
			if self.engine.isRunning { self.engine.pause() }
		}
		idleWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Constants.speakerIdleSeconds, execute: work)
	}

	@MainActor
	private func play(text: String, provider: TextToSpeechProvider, config: Config, utterance current: Utterance) async
	{
		do {
			for try await buffer in provider.synthesize(text: text, config: config) {
				guard current === utterance else { return }
				schedule(buffer: buffer, providerID: provider.id, utterance: current)
			}
		} catch {
			guard current === utterance, !Task.isCancelled else { return }
			let failure =
				error as? TextToSpeechFailure
				?? TextToSpeechFailure(reason: "\(error)", unspokenText: current.hasStarted ? nil : text)
			Log.info(message: "tts: \(provider.id) failed: \(failure.reason)")
			if provider.id != .system, let unspoken = failure.unspokenText {
				current.onEvent?(.fellBack(reason: SpeechText.friendlyFailure(reason: failure.reason)))
				await play(text: unspoken, provider: SystemTextToSpeech(), config: config, utterance: current)
				return
			}
		}
		guard current === utterance else { return }
		current.isStreamFinished = true
		finishIfDrained(utterance: current)
	}

	private func schedule(buffer: AVAudioPCMBuffer, providerID: TextToSpeechProviderID, utterance current: Utterance) {
		guard let converted = converted(buffer: buffer) else { return }
		if !current.hasStarted {
			current.hasStarted = true
			current.onEvent?(.started(providerID))
		}
		current.scheduledBufferCount += 1
		player.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
			DispatchQueue.main.async {
				guard let self, current === self.utterance else { return }
				current.scheduledBufferCount -= 1
				self.finishIfDrained(utterance: current)
			}
		}
	}

	private func converted(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
		if buffer.format == format { return buffer }
		let converter = converters[buffer.format] ?? AVAudioConverter(from: buffer.format, to: format)
		guard let converter else { return nil }
		converters[buffer.format] = converter
		return PCM.convert(buffer: buffer, converter: converter)
	}

	private func finishIfDrained(utterance current: Utterance) {
		guard current === utterance, current.isStreamFinished, current.scheduledBufferCount <= 0 else { return }
		stop()
	}
}
