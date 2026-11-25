import AppKit

/// A dictation app someone may already use. With one installed, Bol suggests leaving its own dictation off:
/// both would react to a held key (often the same fn key) and paste twice.
struct DictationApp: Equatable {
	let name: String
	/// Bundle file names without `.app`, as they appear in /Applications.
	let fileNames: [String]
	var bundleIDs: [String] = []
}

enum DictationApps {
	static let known: [DictationApp] = [
		DictationApp(name: "Wispr Flow", fileNames: ["Wispr Flow"], bundleIDs: ["com.electron.wispr-flow"]),
		DictationApp(name: "Hex", fileNames: ["Hex"], bundleIDs: ["com.kitlangton.Hex"]),
		DictationApp(name: "Willow Voice", fileNames: ["Willow Voice", "Willow"]),
		DictationApp(name: "superwhisper", fileNames: ["superwhisper"], bundleIDs: ["com.superduper.superwhisper"]),
		DictationApp(name: "MacWhisper", fileNames: ["MacWhisper"], bundleIDs: ["com.goodsnooze.MacWhisper"]),
		DictationApp(name: "VoiceInk", fileNames: ["VoiceInk"]),
		DictationApp(name: "Aqua Voice", fileNames: ["Aqua Voice"]),
		DictationApp(name: "Spokenly", fileNames: ["Spokenly"]),
	]

	private static let folders = [
		"/Applications", "/Applications/Setapp", NSHomeDirectory() + "/Applications",
	]

	/// Known dictation apps on this Mac: in an Applications folder, registered with Launch Services, or running.
	static func installed(
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
		isRegistered: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
		runningNames: Set<String> = runningNames()
	) -> [DictationApp] {
		known.filter { app in
			app.fileNames.contains { name in
				runningNames.contains(name) || folders.contains { fileExists("\($0)/\(name).app") }
			} || app.bundleIDs.contains(where: isRegistered)
		}
	}

	/// Known dictation apps running right now.
	static func running(runningNames: Set<String> = runningNames()) -> [DictationApp] {
		known.filter { app in app.fileNames.contains { runningNames.contains($0) } }
	}

	static func runningNames() -> Set<String> {
		Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName))
	}

	/// "Wispr Flow", "Wispr Flow and Hex", "Wispr Flow, Hex and superwhisper".
	static func list(apps: [DictationApp]) -> String {
		let names = apps.map(\.name)
		guard names.count > 1 else { return names.first ?? "" }
		return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
	}
}
