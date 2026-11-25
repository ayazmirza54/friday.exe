import Foundation
import Testing

@testable import Bol

@Suite struct TermsTests {
	@Test @MainActor func setupCantFinishWithoutAgreeing() {
		let model = OnboardingModel(settings: SettingsModel(config: Config()))
		var didFinish = false
		model.onFinish = { didFinish = true }
		model.step = .terms
		model.goForward()
		#expect(!didFinish)
		#expect(model.settings.config.acceptedTerms == nil)
		#expect(!model.settings.config.hasCompletedOnboarding)
	}

	@Test @MainActor func agreeingRecordsTheCurrentTerms() {
		let model = OnboardingModel(settings: SettingsModel(config: Config()))
		var didFinish = false
		model.onFinish = { didFinish = true }
		model.step = .terms
		model.isAgreeingToTerms = true
		model.goForward()
		#expect(didFinish)
		#expect(model.settings.config.acceptedTerms?.version == Constants.termsVersion)
		#expect(model.settings.config.hasAcceptedCurrentTerms)
		#expect(model.settings.config.hasCompletedOnboarding)
	}

	@Test func termsIsTheLastStep() {
		#expect(OnboardingStep.allCases.last == .terms)
	}

	@Test func olderConfigsHaveNotAgreedAndChangedTermsAskAgain() throws {
		let old = try Config.decoded(data: Data(#"{"hasCompletedOnboarding": true}"#.utf8))
		#expect(old.hasCompletedOnboarding && old.acceptedTerms == nil && !old.hasAcceptedCurrentTerms)
		var config = Config()
		config.acceptedTerms = AcceptedTerms(version: "2000-01-01", acceptedAt: "2000-01-01T00:00:00Z")
		#expect(!config.hasAcceptedCurrentTerms)
		config.acceptedTerms = .now()
		let saved = try Config.decoded(data: JSONEncoder().encode(config))
		#expect(saved.hasAcceptedCurrentTerms)
	}
}
