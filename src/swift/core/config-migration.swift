import Foundation

/// One-time upgrade of the old flat config.json (before providers became plugins) to the
/// current nested shape. `Config.load` saves right after, so this only ever runs once per
/// install. Delete this file once every install has launched a newer build.
enum ConfigMigration {
	/// Paste Last Dictation used to have its own on/off switch; now turning it off clears its shortcut.
	static func pasteLastToggle(stored: [String: Any]) -> [String: Any] {
		guard stored["shortcuts"] == nil, let dictation = stored["dictation"] as? [String: Any],
			dictation["isPasteLastEnabled"] as? Bool == false
		else { return stored }
		var upgraded = stored
		upgraded["shortcuts"] = ["pasteLastDictation": NSNull()]
		return upgraded
	}

	static func migrated(stored: [String: Any]) -> [String: Any] {
		guard stored["textToSpeech"] == nil, stored["ttsProvider"] != nil else { return stored }
		Log.info(message: "config: migrating to the provider-plugin layout")

		func value(key: String) -> Any? {
			guard let v = stored[key], !(v is NSNull) else { return nil }
			if let s = v as? String, s.isEmpty { return nil }  // "" used to mean "automatic"
			return v
		}
		func object(pairs: [(String, Any?)]) -> [String: Any] {
			pairs.reduce(into: [:]) { result, pair in
				if let v = pair.1 { result[pair.0] = v }
			}
		}
		// Older configs stored short model aliases.
		let modelAliases = [
			"opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5",
			"fable": "claude-fable-5-2",
		]
		let claudeModel = (value(key: "claudeModel") as? String).map { modelAliases[$0.lowercased()] ?? $0 }

		return object(pairs: [
			("apiKeys", object(pairs: [("openai", value(key: "openaiApiKey")), ("noiz", value(key: "noizApiKey"))])),
			(
				"textToSpeech",
				object(pairs: [
					("provider", value(key: "ttsProvider")),
					(
						"openai",
						object(pairs: [
							("model", value(key: "ttsModel")), ("voice", value(key: "ttsVoice")),
							("instructions", value(key: "ttsInstructions")),
						])
					),
					(
						"noiz",
						object(pairs: [
							("voiceId", value(key: "noizVoiceId")), ("speed", value(key: "noizSpeed")),
							("qualityPreset", value(key: "noizQualityPreset")),
							("language", value(key: "noizLanguage")),
							("model", value(key: "noizModel")), ("emotion", value(key: "noizEmotion")),
						])
					),
					("system", object(pairs: [("voiceId", value(key: "systemVoiceId"))])),
				])
			),
			(
				"speechToText",
				object(pairs: [
					("provider", value(key: "sttProvider")),
					(
						"openai",
						object(pairs: [("model", value(key: "sttModel")), ("language", value(key: "language"))])
					),
				])
			),
			("isFollowUpEnabled", value(key: "followUpEnabled")),
			("followUpSeconds", value(key: "followUpSeconds")),
			("endOfSpeechSeconds", value(key: "endOfSpeechSeconds")),
			("isSilentMode", value(key: "silentMode")),
			("isChromeEnabled", value(key: "claudeInChrome")),
			("screenAccess", value(key: "screenAccess")),
			("claudeModel", claudeModel),
			("workingDirectory", value(key: "workingDirectory")),
		])
	}
}
