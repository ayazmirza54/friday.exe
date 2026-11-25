import Foundation

/// One Claude subscription limit (session, weekly...).
struct PlanLimit: Identifiable, Equatable {
	enum Severity: String {
		case normal, warning, critical

		/// The API's open-ended severity names; anything unknown reads as normal.
		init(apiValue: String?) {
			switch apiValue {
			case "critical", "exceeded", "blocked": self = .critical
			case "warning": self = .warning
			default: self = .normal
			}
		}
	}

	let id: String
	let title: String
	let subtitle: String
	/// 0...100.
	let percent: Double
	let severity: Severity
	let resetsAt: Date?
	let isActive: Bool
}

/// Claude subscription usage, from the same endpoint Claude Code's /usage uses.
enum PlanUsage {
	private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

	/// Throws a `ServiceProblem` that says what went wrong.
	static func fetch() async throws -> [PlanLimit] {
		guard let token = await ClaudeAuth.accessToken() else {
			throw ServiceProblem(
				title: "Not signed in to Claude Code", detail: "Sign in from Settings → Assistant.",
				fix: .signInToClaude)
		}
		var request = URLRequest(url: endpoint)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
		request.timeoutInterval = 15
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw ServiceDiagnosis.planUsage(status: nil, error: error)
		}
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		if status == 401 { await ClaudeAuth.forgetCachedLogin() }
		guard status == 200, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw ServiceDiagnosis.planUsage(status: status, error: nil)
		}
		return parse(object: object)
	}

	static func parse(object: [String: Any]) -> [PlanLimit] {
		let isoFractional = ISO8601DateFormatter()
		isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let isoPlain = ISO8601DateFormatter()
		func date(value: Any?) -> Date? {
			guard let text = value as? String else { return nil }
			return isoFractional.date(from: text) ?? isoPlain.date(from: text)
		}
		var limits: [PlanLimit] = []
		for (i, limit) in ((object["limits"] as? [[String: Any]]) ?? []).enumerated() {
			let kind = limit["kind"] as? String ?? "limit"
			let group = limit["group"] as? String ?? ""
			let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
			let isSession = group == "session" || group == "five_hour"
			// The all-models 5-hour session isn't shown: plan usage lists the weekly and per-model limits.
			if isSession, model == nil { continue }
			let title: String
			let subtitle: String
			if group == "weekly" {
				title = model.map { "Weekly · \($0)" } ?? "Weekly · all models"
				subtitle = "Resets every 7 days"
			} else if isSession {
				title = "Session · \(model ?? "all models")"
				subtitle = "5-hour window"
			} else {
				title = model ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
				subtitle = ""
			}
			limits.append(
				PlanLimit(
					id: "\(kind)-\(i)", title: title, subtitle: subtitle,
					percent: (limit["percent"] as? NSNumber)?.doubleValue ?? 0,
					severity: PlanLimit.Severity(apiValue: limit["severity"] as? String),
					resetsAt: date(value: limit["resets_at"]), isActive: limit["is_active"] as? Bool ?? false))
		}
		// Older responses: top-level windows.
		if limits.isEmpty {
			let windows = [
				("seven_day", "Weekly · all models", "Resets every 7 days"),
				("seven_day_opus", "Weekly · Opus", "Resets every 7 days"),
				("seven_day_sonnet", "Weekly · Sonnet", "Resets every 7 days"),
			]
			for (key, title, subtitle) in windows {
				guard let window = object[key] as? [String: Any],
					let utilization = (window["utilization"] as? NSNumber)?.doubleValue
				else { continue }
				let severity: PlanLimit.Severity =
					utilization >= 90 ? .critical : utilization >= 75 ? .warning : .normal
				limits.append(
					PlanLimit(
						id: key, title: title, subtitle: subtitle, percent: utilization, severity: severity,
						resetsAt: date(value: window["resets_at"]), isActive: true))
			}
		}
		return limits
	}

	static func resetText(date: Date?) -> String {
		guard let date else { return "Starts with your next request" }
		let seconds = date.timeIntervalSinceNow
		guard seconds > 0 else { return "Resetting now" }
		let hours = Int(seconds) / 3600
		let minutes = (Int(seconds) % 3600) / 60
		if hours < 24 { return hours > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(minutes)m" }
		let formatter = DateFormatter()
		formatter.dateFormat = "EEE h:mm a"
		return "Resets \(formatter.string(from: date))"
	}
}
