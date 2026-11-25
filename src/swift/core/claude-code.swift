import Foundation

/// The Claude Code CLI installed on this Mac. Bol needs it: the brain runs on it, and its
/// login (a Claude subscription) also powers speech-to-text, which an API key can't.
enum ClaudeCode {
	/// The official installer, shown to the user before it runs.
	static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

	static var executable: URL? { Shell.which(name: "claude") }

	/// The installed path for typing into a shell, short and readable: `~/.local/bin/claude`.
	static var shellPath: String {
		guard let path = executable?.path else { return "claude" }
		let short = path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
		return short.contains(" ") ? "\"\(path)\"" : short
	}

	/// e.g. "2.1.325"; nil when not installed or not runnable.
	static func version() async -> String? {
		guard let executable else { return nil }
		let result = await Shell.run(executable: executable, arguments: ["--version"], timeoutSeconds: 10)
		guard result.isSuccess else { return nil }
		return result.output.split(separator: " ").first.map(String.init)
	}
}
