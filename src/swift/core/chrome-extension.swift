import AppKit

/// Claude in Chrome: the extension Claude Code drives the user's own Chrome through (Bol passes
/// `--chrome` when Settings → Access → Chrome is on).
enum ChromeExtension {
	static let id = "fcoeoabgfenejglbffodgkkbkcdhcgfn"
	static let storeURL = URL(string: "https://chromewebstore.google.com/detail/claude/\(id)")!
	private static let chromeBundleID = "com.google.Chrome"

	/// Installed in any Chrome profile.
	static var isInstalled: Bool {
		let chrome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
			"Library/Application Support/Google/Chrome")
		let profiles = (try? FileManager.default.contentsOfDirectory(atPath: chrome.path)) ?? []
		return profiles.contains { profile in
			FileManager.default.fileExists(
				atPath: chrome.appendingPathComponent(profile).appendingPathComponent("Extensions/\(id)").path)
		}
	}

	/// The Web Store page, in Chrome when it's installed (the extension is Chrome-only).
	static func openStorePage() {
		guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleID) else {
			NSWorkspace.shared.open(storeURL)
			return
		}
		NSWorkspace.shared.open([storeURL], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
	}
}
