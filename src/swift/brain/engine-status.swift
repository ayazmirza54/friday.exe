import Foundation

/// What Bol's brain needs: Claude Code installed, and signed in with a Claude subscription.
struct EngineStatus: Equatable {
	struct Step: Equatable, Identifiable {
		let id: String
		let title: String
		let isDone: Bool
		let detail: String
		let fixHint: String
		let fixCommand: String
	}

	var claudeVersion: String?
	var account: ClaudeAuth.Account?

	var isInstalled: Bool { claudeVersion != nil }
	var isSignedIn: Bool { account != nil }
	var isReady: Bool { isInstalled && isSignedIn }

	var steps: [Step] {
		[
			Step(
				id: "install", title: "Claude Code installed", isDone: isInstalled,
				detail: claudeVersion.map { "Version \($0)" } ?? "Not installed",
				fixHint: "Install Claude Code:", fixCommand: ClaudeCode.installCommand),
			Step(
				id: "login", title: "Signed in to Claude", isDone: isSignedIn,
				detail: account.map { $0.plan.map { "\($0) subscription" } ?? "Signed in" } ?? "Not signed in",
				fixHint: "Sign in with your Claude subscription:",
				fixCommand: "\(ClaudeCode.shellPath) auth login"),
		]
	}

	static func check() async -> EngineStatus {
		async let version = ClaudeCode.version()
		async let account = ClaudeAuth.account()
		return EngineStatus(claudeVersion: await version, account: await account)
	}
}
