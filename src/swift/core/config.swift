import Foundation

/// User-editable settings, persisted at ~/.bol/config.json.
///
/// Every field declares its default right here: on load, the stored JSON is laid over the
/// defaults, so a missing key (new setting, older file) simply takes its default.
struct Config: Codable, Equatable {
	var apiKeys = APIKeys()
	var textToSpeech = TextToSpeechSettings()
	var speechToText = SpeechToTextSettings()
	/// Hold a key in any app, speak, let go: the text is pasted where you're typing.
	var dictation = DictationSettings()
	/// Bol's global shortcuts (⌘J to talk…), each changeable or off in Settings → Shortcuts.
	var shortcuts = ShortcutSettings()

	var isFollowUpEnabled = true
	var followUpSeconds = 6.0
	/// Unused: pauses no longer end a turn (Enter sends). Kept so existing config files round-trip.
	var endOfSpeechSeconds = 1.4
	/// Show replies in the voice bar without speaking them.
	var isSilentMode = false
	/// What other apps' sound does while Bol listens or speaks.
	var otherAudio = OtherAudioBehavior.lower
	/// What `lower` takes other apps down to: a share of their volume.
	var otherAudioLevel = 0.2

	var isChromeEnabled = true
	var screenAccess = ScreenAccess.auto
	var claudeModel = ClaudeModel.opus
	var claudeEffort = ClaudeEffort.medium
	/// nil = Bol's own workspace (~/.bol/workspace), which keeps its sessions apart from yours.
	var workingDirectory: String? = nil
	/// The first-run setup was finished (it checks Claude Code, the login, the mic and the voice).
	var hasCompletedOnboarding = false
	/// The Terms and Privacy Policy the user agreed to in setup, and when. Kept only on this Mac.
	var acceptedTerms: AcceptedTerms? = nil

	/// Bol starts only once the current Terms are agreed to (see `Constants.termsVersion`).
	var hasAcceptedCurrentTerms: Bool { acceptedTerms?.version == Constants.termsVersion }
}

struct AcceptedTerms: Codable, Equatable {
	let version: String
	/// ISO 8601, e.g. "2026-11-25T13:40:00Z".
	let acceptedAt: String

	static func now() -> AcceptedTerms {
		AcceptedTerms(version: Constants.termsVersion, acceptedAt: ISO8601DateFormatter().string(from: Date()))
	}
}

/// The frontier models Bol offers. A stored choice that isn't one of them (older builds offered
/// Sonnet, Haiku and "Claude Code's default") becomes Opus.
enum ClaudeModel: String, Codable, CaseIterable {
	case opus = "claude-opus-5-5"
	case fable = "claude-fable-5-2"

	init(from decoder: Decoder) throws {
		self = ClaudeModel(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .opus
	}

	var title: String {
		switch self {
		case .opus: return "Claude Opus 5.5"
		case .fable: return "Claude Fable 5.2"
		}
	}

	var subtitle: String {
		switch self {
		case .opus: return "Recommended: frontier capability at voice speed"
		case .fable: return "Most capable, slower replies"
		}
	}
}

/// How hard Claude thinks before answering. Higher is more thorough and slower.
/// How hard Claude thinks. Bol never goes below medium: a voice request is a real task, and lighter thinking
/// gets it wrong. A `low` saved by an older version reads as medium.
enum ClaudeEffort: String, Codable, CaseIterable {
	case medium, high, xhigh, max

	init(from decoder: Decoder) throws {
		self = ClaudeEffort(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .medium
	}

	var title: String {
		switch self {
		case .medium: return "Medium"
		case .high: return "High"
		case .xhigh: return "Extra high"
		case .max: return "Max"
		}
	}

	var subtitle: String {
		switch self {
		case .medium: return "Recommended: quick and capable (the minimum)"
		case .high: return "More thorough, slower"
		case .xhigh: return "Deep work on hard tasks"
		case .max: return "Slowest, thinks the longest"
		}
	}
}

/// Other apps' sound while Bol listens or speaks. Lower and mute keep Bol's own voice as it is.
enum OtherAudioBehavior: String, Codable, CaseIterable {
	case lower, mute, pauseMedia, nothing

	var title: String {
		switch self {
		case .lower: return "Lower audio"
		case .mute: return "Mute"
		case .pauseMedia: return "Pause media"
		case .nothing: return "Do nothing"
		}
	}

	var subtitle: String {
		switch self {
		case .lower: return "Turn other apps down"
		case .mute: return "Silence other apps"
		case .pauseMedia: return "Music, Spotify and VLC"
		case .nothing: return "Leave other apps alone"
		}
	}
}

/// Whether the agent may see and operate the screen: screenshots, pointer and keyboard.
/// A stored value that isn't one of these (older builds offered "ask") becomes `auto`.
enum ScreenAccess: String, Codable, CaseIterable {
	case auto, off

	init(from decoder: Decoder) throws {
		self = ScreenAccess(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .auto
	}
}

// MARK: - Persistence

extension Config {
	private static let saveQueue = DispatchQueue(label: "bol.config")

	/// Reads the config at launch (before anything else runs, so this one read is synchronous).
	static func load() -> Config {
		try? FileManager.default.createDirectory(at: Constants.bolDirectory, withIntermediateDirectories: true)
		var config = Config()
		do {
			config = try decoded(data: Data(contentsOf: Constants.configFile))
		} catch CocoaError.fileReadNoSuchFile {
			Log.info(message: "config: none yet, using defaults")
		} catch {
			Log.info(message: "config: unreadable (\(error)), using defaults")
		}
		// Keys found elsewhere are adopted into the config, which is the only place they're read from.
		if config.apiKeys[.openai] == nil {
			config.apiKeys[.openai] = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
		}
		if config.apiKeys[.noiz] == nil {
			let legacyNoizKeyFile = Constants.bolDirectory.appendingPathComponent("noiz_key")
			config.apiKeys[.noiz] = try? String(contentsOf: legacyNoizKeyFile, encoding: .utf8)
		}
		config.save()  // writes back new defaults and the current shape
		return config
	}

	/// Saves in the background; saves run in order, so the last write wins.
	func save() {
		let config = self
		Self.saveQueue.async {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			do {
				try encoder.encode(config).write(to: Constants.configFile, options: .atomic)
				chmod(Constants.configFile.path, 0o600)
			} catch {
				Log.info(message: "config: save failed: \(error)")
			}
		}
	}

	/// A stored config.json (any version), upgraded and laid over the defaults.
	static func decoded(data: Data) throws -> Config {
		guard let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw CocoaError(.fileReadCorruptFile)
		}
		return try decode(stored: ConfigMigration.pasteLastToggle(stored: ConfigMigration.migrated(stored: stored)))
	}

	/// Lays `stored` over the defaults, then decodes.
	private static func decode(stored: [String: Any]) throws -> Config {
		let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as? [String: Any] ?? [:]
		let merged = merge(base: defaults, overlay: stored)
		return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
	}

	private static func merge(base: [String: Any], overlay: [String: Any]) -> [String: Any] {
		var result = base
		for (key, value) in overlay {
			if let nested = value as? [String: Any], let baseNested = base[key] as? [String: Any] {
				result[key] = merge(base: baseNested, overlay: nested)
			} else {
				result[key] = value
			}
		}
		return result
	}
}
