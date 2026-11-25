import Foundation
import Testing

@testable import Bol

@Suite struct DictationAppsTests {
	private func installed(files: Set<String> = [], bundleIDs: Set<String> = [], running: Set<String> = [])
		-> [String]
	{
		DictationApps.installed(
			fileExists: { files.contains($0) }, isRegistered: { bundleIDs.contains($0) }, runningNames: running
		).map(\.name)
	}

	@Test func findsAppsInApplicationsFolders() {
		#expect(installed(files: ["/Applications/Wispr Flow.app"]) == ["Wispr Flow"])
		#expect(installed(files: ["/Applications/Setapp/superwhisper.app"]) == ["superwhisper"])
		#expect(installed(files: [NSHomeDirectory() + "/Applications/Willow.app"]) == ["Willow Voice"])
	}

	@Test func findsAppsByBundleIDOrWhileRunning() {
		#expect(installed(bundleIDs: ["com.kitlangton.Hex"]) == ["Hex"])
		#expect(installed(running: ["MacWhisper"]) == ["MacWhisper"])
	}

	@Test func findsNothingOnACleanMac() {
		#expect(installed(files: ["/Applications/Safari.app"], running: ["Finder"]).isEmpty)
	}

	@Test func listsNamesForSentences() {
		let apps = DictationApps.known
		#expect(DictationApps.list(apps: []) == "")
		#expect(DictationApps.list(apps: [apps[0]]) == "Wispr Flow")
		#expect(DictationApps.list(apps: Array(apps.prefix(2))) == "Wispr Flow and Hex")
		#expect(DictationApps.list(apps: Array(apps.prefix(3))) == "Wispr Flow, Hex and Willow Voice")
	}
}

@Suite struct DictationStepTests {
	private func model(apps: [DictationApp], hasCompletedOnboarding: Bool = false, isEnabled: Bool = true)
		-> OnboardingModel
	{
		var config = Config()
		config.hasCompletedOnboarding = hasCompletedOnboarding
		config.dictation.isEnabled = isEnabled
		let model = OnboardingModel(settings: SettingsModel(config: config))
		model.findDictationApps = { apps }
		return model
	}

	@Test @MainActor func suggestsOffWhenAnotherDictationAppIsInstalled() {
		let model = model(apps: [DictationApps.known[0]])
		model.checkDictationApps()
		#expect(!model.isDictationRecommended)
		#expect(!model.settings.config.dictation.isEnabled)
	}

	@Test @MainActor func keepsDictationOnWithoutOtherApps() {
		let model = model(apps: [])
		model.checkDictationApps()
		#expect(model.isDictationRecommended)
		#expect(model.settings.config.dictation.isEnabled)
	}

	@Test @MainActor func neverOverridesAChoiceAlreadyMade() {
		// Running setup again: the recommendation shows, but the setting stays as the user left it.
		let rerun = model(apps: [DictationApps.known[1]], hasCompletedOnboarding: true)
		rerun.checkDictationApps()
		#expect(!rerun.isDictationRecommended)
		#expect(rerun.settings.config.dictation.isEnabled)
		// Coming back to the step in the same setup: a choice made there isn't reset.
		let first = model(apps: [DictationApps.known[1]])
		first.checkDictationApps()
		first.settings.config.dictation.isEnabled = true
		first.checkDictationApps()
		#expect(first.settings.config.dictation.isEnabled)
	}
}
