import Foundation

/// The Claude Code subscription login, read from the login keychain (the same credential
/// `claude` itself uses) and refreshed through the installed Claude Code when needed.
enum ClaudeAuth {
	struct Account: Equatable {
		/// e.g. "Claude Max"; nil when the plan isn't recorded.
		let plan: String?
	}

	private struct Credentials: Sendable {
		let accessToken: String?
		let hasRefreshToken: Bool
		let expiresAt: Date
		let subscriptionType: String?
	}

	/// The last login read from the keychain, and the one refresh that may run at a time.
	private actor Store {
		var cached: (credentials: Credentials, readAt: Date)?
		var refresh: Task<Void, Never>?
		var lastFailedRefresh: Date?

		func credentials() async -> Credentials? {
			if let cached, -cached.readAt.timeIntervalSinceNow < ClaudeAuth.cacheSeconds { return cached.credentials }
			let credentials = await ClaudeAuth.readCredentials()
			cached = credentials.map { ($0, Date()) }
			return credentials
		}

		func forget() { cached = nil }

		/// Asks Claude Code to refresh the login. Callers share a refresh that's running; after one fails, the
		/// next waits `refreshBackoffSeconds`, so a poller can't keep launching `claude` (e.g. offline overnight).
		/// Something the user just did (⌘J, a dictation, a setup test) skips that wait: it may be back online.
		func refreshLogin(isUserAction: Bool) async {
			if let refresh {
				await refresh.value
				return
			}
			if !isUserAction, let failed = lastFailedRefresh,
				-failed.timeIntervalSinceNow < ClaudeAuth.refreshBackoffSeconds
			{
				return
			}
			let task = Task {
				guard let claude = ClaudeCode.executable else { return }
				Log.info(message: "auth: token missing/expiring, asking Claude Code to refresh")
				await Shell.run(executable: claude, arguments: ["auth", "status"], timeoutSeconds: 30)
				self.forget()
				if await ClaudeAuth.validToken(marginSeconds: ClaudeAuth.refreshMarginSeconds) != nil { return }
				// Any real request forces a refresh.
				await Shell.run(
					executable: claude, arguments: ["-p", "Reply with just: ok", "--model", "haiku"],
					timeoutSeconds: 90)
				self.forget()
			}
			refresh = task
			await task.value
			refresh = nil
			let isRefreshed = await ClaudeAuth.validToken(marginSeconds: 0) != nil
			lastFailedRefresh = isRefreshed ? nil : Date()
		}
	}

	private static let store = Store()
	private static let securityTool = URL(fileURLWithPath: "/usr/bin/security")
	private static let keychainService = "Claude Code-credentials"
	/// Tokens closer than this to expiry are refreshed first.
	private static let refreshMarginSeconds: TimeInterval = 120
	/// How long a keychain read is trusted, so ⌘J and pollers don't launch `security` every time.
	private static let cacheSeconds: TimeInterval = 300
	/// After a refresh fails, how long before Bol asks Claude Code again.
	private static let refreshBackoffSeconds: TimeInterval = 600

	/// A valid access token, or nil when not signed in. `isUserAction`: the user is waiting on it (⌘J, a
	/// dictation, a setup test), so a refresh is tried even within the backoff after a failed one.
	static func accessToken(isUserAction: Bool = false) async -> String? {
		if let token = await validToken(marginSeconds: refreshMarginSeconds) { return token }
		await store.refreshLogin(isUserAction: isUserAction)
		return await validToken(marginSeconds: 0)
	}

	/// The signed-in account, or nil when Claude Code has no stored login.
	static func account() async -> Account? {
		guard let credentials = await store.credentials(),
			credentials.accessToken != nil || credentials.hasRefreshToken
		else { return nil }
		return Account(plan: planTitle(subscriptionType: credentials.subscriptionType))
	}

	/// A server turned the token down (signed out, or replaced by a newer login): read the keychain again next time.
	static func forgetCachedLogin() async { await store.forget() }

	private static func validToken(marginSeconds: TimeInterval) async -> String? {
		guard let credentials = await store.credentials(), let token = credentials.accessToken,
			credentials.expiresAt.timeIntervalSinceNow > marginSeconds
		else { return nil }
		return token
	}

	/// Shells out to /usr/bin/security: it's on the keychain item's ACL, so there's no prompt.
	private static func readCredentials() async -> Credentials? {
		let result = await Shell.run(
			executable: securityTool, arguments: ["find-generic-password", "-s", keychainService, "-w"],
			timeoutSeconds: 10)
		guard result.isSuccess,
			let data = result.output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let oauth = object["claudeAiOauth"] as? [String: Any]
		else { return nil }
		let expiresAtMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
		return Credentials(
			accessToken: oauth["accessToken"] as? String,
			hasRefreshToken: oauth["refreshToken"] is String,
			expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1000),
			subscriptionType: oauth["subscriptionType"] as? String)
	}

	private static func planTitle(subscriptionType: String?) -> String? {
		switch subscriptionType?.lowercased() {
		case "max": return "Claude Max"
		case "pro": return "Claude Pro"
		case "team": return "Claude Team"
		case "enterprise": return "Claude Enterprise"
		case let other?: return other.capitalized
		case nil: return nil
		}
	}
}
