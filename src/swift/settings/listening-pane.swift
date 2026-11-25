import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Listening

struct ListeningPane: View {
	@ObservedObject var model: SettingsModel

	private static let providers = SpeechToTextProviders.all.map {
		SelectOption(id: $0.id.rawValue, title: $0.title, subtitle: $0.subtitle, icon: $0.icon)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Speech to text") {
				SettingsRow("Provider", icon: "text.bubble") {
					Select(
						options: Self.providers,
						selection: $model.config.speechToText.provider.rawValue,
						isSearchable: true, prompt: "Search providers")
				}
				SpeechToTextProviders.provider(id: model.config.speechToText.provider).settingsSection(model: model)
			}
		}
	}
}
