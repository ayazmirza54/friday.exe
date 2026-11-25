import Foundation
import os

/// Something Bol depends on isn't working, worded for the person using Bol: what's wrong and what to do.
struct ServiceProblem: Error, Equatable {
	enum Fix: Equatable {
		case useOpenAIForListening, signInToClaude, installClaudeCode, checkConnection, tryAgain, none
	}

	let title: String
	let detail: String
	var fix = Fix.none
	/// The service itself is down or has changed (not a one-off failure): Bol stops relying on it until a
	/// health check passes again.
	var isOutage = false
}

/// Bol's listening and plan usage use two Anthropic endpoints that aren't public APIs: the ones behind
/// Claude Code's `/voice` and `/usage`. They can change or close without notice, so every failure is
/// classified here into a message that says what happened and what to do about it.
enum ServiceDiagnosis {
	static let openAIHint = "Switch Settings → Listening to OpenAI to keep talking to Bol."

	static func claudeSpeechToText(status: Int?, error: Error?, serverMessage: String?) -> ServiceProblem {
		if let status, status != 101 {
			switch status {
			case 401:
				return ServiceProblem(
					title: "Claude didn't accept Bol's sign-in",
					detail: "Sign in to Claude Code again from Settings → Assistant. \(openAIHint)",
					fix: .signInToClaude, isOutage: true)
			case 403:
				return ServiceProblem(
					title: "This Claude account can't use voice",
					detail:
						"Claude's speech-to-text needs a Claude Pro or Max plan, and Anthropic may limit it. \(openAIHint)",
					fix: .useOpenAIForListening, isOutage: true)
			case 429:
				return ServiceProblem(
					title: "Claude's voice service is rate limited",
					detail: "Wait a minute and try again. \(openAIHint)", fix: .tryAgain)
			case 500...599:
				return ServiceProblem(
					title: "Claude's voice service is having trouble",
					detail: "Anthropic's side failed (HTTP \(status)). Try again shortly. \(openAIHint)",
					fix: .tryAgain)
			default:
				return ServiceProblem(
					title: "Claude's speech-to-text has changed",
					detail:
						"Bol listens through the service behind Claude Code's /voice, which isn't a public API, and it answered with HTTP \(status). \(openAIHint) An update to Bol will fix it.",
					fix: .useOpenAIForListening, isOutage: true)
			}
		}
		if let problem = connection(error: error, service: "Anthropic") { return problem }
		if let serverMessage, !serverMessage.isEmpty {
			return ServiceProblem(title: "Claude couldn't transcribe that", detail: serverMessage, fix: .tryAgain)
		}
		return ServiceProblem(
			title: "Claude's speech-to-text didn't respond",
			detail: "Try again. If it keeps happening, \(openAIHint.prefix(1).lowercased() + openAIHint.dropFirst())",
			fix: .tryAgain)
	}

	static func planUsage(status: Int?, error: Error?) -> ServiceProblem {
		if let problem = connection(error: error, service: "Anthropic") { return problem }
		switch status {
		case 401?:
			return ServiceProblem(
				title: "Usage needs a fresh sign-in", detail: "Sign in to Claude Code again from Settings → Assistant.",
				fix: .signInToClaude)
		case 403?:
			return ServiceProblem(
				title: "Claude didn't accept this login",
				detail: "Bol needs a Claude Pro or Max subscription. Sign in with one from Settings → Assistant.",
				fix: .signInToClaude)
		case 429?:
			return ServiceProblem(title: "Usage is rate limited", detail: "It refreshes in a minute.", fix: .tryAgain)
		default:
			let code = status.map { " (HTTP \($0))" } ?? ""
			return ServiceProblem(
				title: "Plan usage isn't available",
				detail:
					"The usage service behind Claude Code's /usage didn't answer\(code). Everything else in Bol works without it.",
				isOutage: status.map { $0 < 500 } ?? false)
		}
	}

	/// Network-level failures, the same for every service.
	static func connection(error: Error?, service: String) -> ServiceProblem? {
		guard let error = error as? URLError else { return nil }
		switch error.code {
		case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
			return ServiceProblem(
				title: "You're offline", detail: "Bol needs the internet to reach \(service).", fix: .checkConnection)
		case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
			return ServiceProblem(
				title: "Can't reach \(service)",
				detail: "Check your connection, VPN or firewall, then try again.", fix: .checkConnection)
		case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
			.clientCertificateRejected:
			return ServiceProblem(
				title: "Secure connection to \(service) failed",
				detail: "A proxy, VPN or security tool may be intercepting traffic.", fix: .checkConnection)
		case .cancelled:
			return nil
		default:
			return ServiceProblem(
				title: "Couldn't reach \(service)", detail: error.localizedDescription, fix: .checkConnection)
		}
	}
}

/// Whether Claude speech-to-text is known to be out. While it is, listening uses OpenAI when it has a key
/// (see `SpeechToTextProviders.active`). Read from any thread.
enum SpeechToTextOutage {
	private static let lock = OSAllocatedUnfairLock<ServiceProblem?>(initialState: nil)

	static var current: ServiceProblem? { lock.withLock { $0 } }

	static func record(problem: ServiceProblem?) {
		lock.withLock { $0 = problem }
	}
}

/// Checks everything Bol relies on and keeps the results for Settings → Assistant → Health, the menu and
/// launch. Runs at launch, when Settings asks, and every 15 minutes while something is out.
@MainActor final class ServiceHealth: ObservableObject {
	enum Item: String, CaseIterable, Identifiable {
		case claudeCode, claudeAccount, speechToText, planUsage
		var id: String { rawValue }

		var title: String {
			switch self {
			case .claudeCode: return "Claude Code"
			case .claudeAccount: return "Claude sign-in"
			case .speechToText: return "Listening"
			case .planUsage: return "Plan usage"
			}
		}

		var icon: String {
			switch self {
			case .claudeCode: return "terminal"
			case .claudeAccount: return "person.crop.circle"
			case .speechToText: return "mic"
			case .planUsage: return "chart.bar"
			}
		}

		/// Bol can't take requests while this fails (plan usage is only informational).
		var isEssential: Bool { self != .planUsage }
	}

	enum Status: Equatable {
		case unknown, checking
		case ok(String)
		case problem(ServiceProblem)
	}

	static let shared = ServiceHealth()

	@Published private(set) var statuses: [Item: Status] = [:]
	@Published private(set) var checkedAt: Date?
	@Published private(set) var isChecking = false
	/// Called when an essential check newly fails, with that problem (the app shows it once).
	var onNewProblem: ((Item, ServiceProblem) -> Void)?
	/// The current settings, read again for each scheduled recheck.
	var currentConfig: () -> Config = { Config.load() }

	private var recheck: Task<Void, Never>?
	private static let recheckSeconds: UInt64 = 15 * 60

	func status(item: Item) -> Status { statuses[item] ?? .unknown }

	/// The first essential problem, for the menu.
	var essentialProblem: (Item, ServiceProblem)? {
		for item in Item.allCases where item.isEssential {
			if case .problem(let problem) = status(item: item) { return (item, problem) }
		}
		return nil
	}

	func run(config: Config) {
		guard !isChecking else { return }
		isChecking = true
		for item in Item.allCases { statuses[item] = .checking }
		Task { @MainActor in
			let previous = statuses
			await check(config: config)
			isChecking = false
			checkedAt = Date()
			for item in Item.allCases where item.isEssential {
				guard case .problem(let problem) = status(item: item) else { continue }
				if case .problem(let old) = previous[item], old == problem { continue }
				onNewProblem?(item, problem)
			}
			scheduleRecheck()
		}
	}

	/// A live failure (e.g. while listening) updates the matching row without a full check.
	func report(item: Item, problem: ServiceProblem) {
		statuses[item] = .problem(problem)
		if item == .speechToText, problem.isOutage { SpeechToTextOutage.record(problem: problem) }
		scheduleRecheck()
	}

	private func check(config: Config) async {
		guard ClaudeCode.executable != nil else {
			let problem = ServiceProblem(
				title: "Claude Code isn't installed",
				detail:
					"Bol thinks with the Claude Code on this Mac. Install it from Settings → General → Run Setup Again.",
				fix: .installClaudeCode)
			statuses = [
				.claudeCode: .problem(problem), .claudeAccount: .unknown, .speechToText: .unknown, .planUsage: .unknown,
			]
			return
		}
		statuses[.claudeCode] = .ok("Installed")

		guard let token = await ClaudeAuth.accessToken() else {
			let problem = ServiceProblem(
				title: "Not signed in to Claude Code",
				detail: "Sign in from Settings → Assistant, or run `claude auth login` in Terminal.",
				fix: .signInToClaude)
			statuses[.claudeAccount] = .problem(problem)
			statuses[.speechToText] = config.speechToText.provider == .claude ? .problem(problem) : .ok("OpenAI")
			statuses[.planUsage] = .unknown
			return
		}
		statuses[.claudeAccount] = .ok(await ClaudeAuth.account()?.plan ?? "Signed in")

		async let speech = checkSpeechToText(config: config, token: token)
		async let usage = checkPlanUsage()
		statuses[.speechToText] = await speech
		statuses[.planUsage] = await usage
	}

	private func checkSpeechToText(config: Config, token: String) async -> Status {
		guard config.speechToText.provider == .claude else {
			SpeechToTextOutage.record(problem: nil)
			return .ok("OpenAI")
		}
		if let problem = await ClaudeSpeechToTextSession.probe(token: token) {
			if problem.isOutage { SpeechToTextOutage.record(problem: problem) }
			let hasFallback = ProviderCredential.apiKey(.openai).isSatisfied(by: config)
			if problem.isOutage, hasFallback {
				return .problem(
					ServiceProblem(
						title: problem.title, detail: "Bol is listening with OpenAI until Claude's works again.",
						fix: problem.fix, isOutage: true))
			}
			return .problem(problem)
		}
		SpeechToTextOutage.record(problem: nil)
		return .ok("Claude · working")
	}

	private func checkPlanUsage() async -> Status {
		do {
			_ = try await PlanUsage.fetch()
			return .ok("Available")
		} catch let problem as ServiceProblem {
			return .problem(problem)
		} catch {
			return .problem(ServiceDiagnosis.planUsage(status: nil, error: error))
		}
	}

	private func scheduleRecheck() {
		recheck?.cancel()
		let hasProblem = statuses.values.contains { if case .problem = $0 { return true } else { return false } }
		guard hasProblem else { return }
		recheck = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: Self.recheckSeconds * 1_000_000_000)
			guard !Task.isCancelled, let self else { return }
			self.run(config: self.currentConfig())
		}
	}
}
