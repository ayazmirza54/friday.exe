import SwiftUI

/// The speech-to-text WebSocket that Claude Code's `/voice` uses, authenticated with the
/// Claude subscription OAuth token. Live interim text, any language (detected automatically).
struct ClaudeSpeechToText: SpeechToTextProvider {
	let id = SpeechToTextProviderID.claude
	let title = "Claude"
	let subtitle = "Live, any language, included with your subscription"
	let icon = "sparkle"
	let credential = ProviderCredential.claudeSubscription

	func makeSession(config: Config) -> SpeechToTextSession {
		ClaudeSpeechToTextSession()
	}

	@MainActor func settingsSection(model: SettingsModel) -> AnyView {
		AnyView(
			SettingsRow("Language", icon: "character.bubble") {
				Text("Detected automatically").font(UI.body).foregroundStyle(.secondary)
			}
		)
	}
}

final class ClaudeSpeechToTextSession: NSObject, SpeechToTextSession, URLSessionWebSocketDelegate {
	private static let endpoint = "wss://api.anthropic.com/api/ws/speech_to_text/voice_stream"
	private static let keepAliveMessage = "{\"type\":\"KeepAlive\"}"

	var onTranscript: ((Transcript) -> Void)?
	var onError: ((ServiceProblem) -> Void)?
	var onFinished: (() -> Void)?
	let isStreamingInterim = true

	private enum Phase { case idle, streaming, closing, finished }

	private var phase = Phase.idle
	private var session: URLSession?
	private var task: URLSessionWebSocketTask?
	private var keepAlive: Timer?
	/// Interim text of the current segment, not yet confirmed final.
	private var pending = ""

	func start(claudeToken: String?) {
		guard phase == .idle, let request = Self.makeRequest(token: claudeToken ?? "") else { return }

		let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
		let task = session.webSocketTask(with: request)
		self.session = session
		self.task = task
		phase = .streaming
		task.resume()
		receive()
		sendText(text: Self.keepAliveMessage)
		keepAlive = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
			self?.sendText(text: Self.keepAliveMessage)
		}
	}

	private static func makeRequest(token: String) -> URLRequest? {
		guard var components = URLComponents(string: endpoint) else { return nil }
		components.queryItems = [
			.init(name: "encoding", value: "linear16"),
			.init(name: "sample_rate", value: "16000"),
			.init(name: "channels", value: "1"),
			.init(name: "endpointing_ms", value: "300"),
			.init(name: "utterance_end_ms", value: "1000"),
			.init(name: "use_conversation_engine", value: "true"),
		]
		guard let url = components.url else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("cli", forHTTPHeaderField: "x-app")
		request.setValue("claude-cli/bol (external, cli)", forHTTPHeaderField: "User-Agent")
		let terms = Constants.speechKeyterms.map { $0.replacingOccurrences(of: ",", with: " ") }.joined(separator: ",")
		if !terms.isEmpty { request.setValue(String(terms.prefix(1024)), forHTTPHeaderField: "x-config-keyterms") }
		return request
	}

	/// Thread-safe: URLSessionWebSocketTask.send can be called from any thread.
	func send(pcm: Data) {
		guard phase == .streaming, let task else { return }
		task.send(.data(pcm)) { _ in }
	}

	/// Ask the server to flush the final transcript.
	func flush() {
		switch phase {
		case .idle:
			finish()
		case .streaming:
			phase = .closing
			sendText(text: "{\"type\":\"CloseStream\"}")
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.finish() }
		case .closing, .finished:
			break
		}
	}

	func cancel() {
		phase = .finished
		teardown()
	}

	private func sendText(text: String) { task?.send(.string(text)) { _ in } }

	private func receive() {
		task?.receive { [weak self] result in
			guard let self else { return }
			switch result {
			case .success(.string(let text)):
				self.handle(message: text)
				self.receive()
			case .success(.data(let data)):
				self.handle(message: String(decoding: data, as: UTF8.self))
				self.receive()
			case .success:
				self.receive()
			case .failure(let error):
				if self.phase == .streaming, !self.hasReportedError {
					self.report(
						problem: ServiceDiagnosis.claudeSpeechToText(
							status: (self.task?.response as? HTTPURLResponse)?.statusCode, error: error,
							serverMessage: nil))
				}
				self.finish()
			}
		}
	}

	private func handle(message: String) {
		guard let data = message.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let type = object["type"] as? String
		else { return }
		switch type {
		case "TranscriptText", "TranscriptInterim":
			if let text = object["data"] as? String, !text.isEmpty {
				pending = text
				onTranscript?(Transcript(text: text, isFinal: false))
			}
		case "TranscriptEndpoint":
			emitPendingAsFinal()
			if phase == .closing { finish() }
		case "TranscriptError", "error":
			let message =
				object["description"] as? String ?? object["message"] as? String ?? object["error_code"] as? String
				?? "transcription error"
			Log.info(message: "stt: server error \(message)")
			if phase == .streaming {
				report(problem: ServiceDiagnosis.claudeSpeechToText(status: nil, error: nil, serverMessage: message))
			}
		default:
			break  // the server's message set is open-ended; others carry nothing we use
		}
	}

	private func emitPendingAsFinal() {
		guard !pending.isEmpty else { return }
		let text = pending
		pending = ""
		onTranscript?(Transcript(text: text, isFinal: true))
	}

	private func finish() {
		guard phase != .finished else { return }
		phase = .finished
		emitPendingAsFinal()
		teardown()
		onFinished?()
	}

	private func teardown() {
		keepAlive?.invalidate()
		keepAlive = nil
		task?.cancel(with: .normalClosure, reason: nil)
		task = nil
		session?.finishTasksAndInvalidate()
		session = nil
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let http = task.response as? HTTPURLResponse, http.statusCode != 101 else { return }
		Log.info(message: "stt: upgrade rejected HTTP \(http.statusCode)")
		if http.statusCode == 401 { Task { await ClaudeAuth.forgetCachedLogin() } }
		if phase == .streaming {
			report(
				problem: ServiceDiagnosis.claudeSpeechToText(status: http.statusCode, error: error, serverMessage: nil))
		}
		finish()
	}

	/// One report per session: a rejected upgrade also fails the pending receive.
	private var hasReportedError = false

	private func report(problem: ServiceProblem) {
		guard !hasReportedError else { return }
		hasReportedError = true
		onError?(problem)
	}

	/// Health check: opens the speech-to-text connection, sends nothing and closes it. Nil when it works.
	static func probe(token: String, timeoutSeconds: Double = 10) async -> ServiceProblem? {
		guard let request = makeRequest(token: token) else { return nil }
		return await withCheckedContinuation { continuation in
			let probe = ConnectionProbe(continuation: continuation)
			let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: .main)
			let task = session.webSocketTask(with: request)
			probe.session = session
			task.resume()
			task.receive { _ in }  // surfaces a rejected upgrade through didCompleteWithError
			DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
				probe.resolve(
					problem: ServiceDiagnosis.claudeSpeechToText(
						status: nil, error: URLError(.timedOut), serverMessage: nil))
			}
		}
	}
}

/// Resolves a health-check connection once: opened (nil), rejected or failed (the problem), or timed out.
private final class ConnectionProbe: NSObject, URLSessionWebSocketDelegate {
	private var continuation: CheckedContinuation<ServiceProblem?, Never>?
	var session: URLSession?

	init(continuation: CheckedContinuation<ServiceProblem?, Never>) {
		self.continuation = continuation
	}

	func resolve(problem: ServiceProblem?) {
		guard let continuation else { return }
		self.continuation = nil
		continuation.resume(returning: problem)
		session?.invalidateAndCancel()
		session = nil
	}

	func urlSession(
		_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?
	) {
		webSocketTask.cancel(with: .normalClosure, reason: nil)
		resolve(problem: nil)
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		let status = (task.response as? HTTPURLResponse)?.statusCode
		resolve(problem: ServiceDiagnosis.claudeSpeechToText(status: status, error: error, serverMessage: nil))
	}
}
