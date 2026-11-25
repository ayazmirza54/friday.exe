import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Voice

struct VoicePane: View {
	@ObservedObject var model: SettingsModel
	@State private var sampleText = "Hi, I'm Bol. What can I do for you today?"

	private static let providers = TextToSpeechProviders.all.map {
		SelectOption(id: $0.id.rawValue, title: $0.title, subtitle: $0.subtitle, icon: $0.icon)
	}

	private var chosen: TextToSpeechProvider { TextToSpeechProviders.provider(id: model.config.textToSpeech.provider) }
	private var active: TextToSpeechProvider { TextToSpeechProviders.active(config: model.config) }

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Output") {
				SettingsRow("Silent mode", icon: "speaker.slash", help: "Show replies on screen without speaking them")
				{
					Toggle("", isOn: $model.config.isSilentMode).labelsHidden().toggleStyle(.switch).controlSize(.small)
				}
				SettingsRow("Provider", icon: "speaker.wave.2") {
					Select(
						options: Self.providers,
						selection: $model.config.textToSpeech.provider.rawValue,
						isSearchable: true, prompt: "Search providers")
				}
				if active.id != chosen.id {
					SettingsRow("Fallback", icon: "exclamationmark.triangle") {
						Text("No key yet, so the \(active.title) voice is used").font(UI.caption).foregroundStyle(
							.orange)
					}
				}
			}

			chosen.settingsSection(model: model)

			preview
		}
	}

	// MARK: Preview

	private var preview: some View {
		SettingsGroup(title: "Preview") {
			VStack(alignment: .leading, spacing: 12) {
				TextField("Type something to hear it", text: $sampleText, axis: .vertical)
					.textFieldStyle(.plain)
					.font(UI.body)
					.lineLimit(1...3)
					.onSubmit { model.toggleSample(text: sampleText) }
					.padding(10)
					.background(UI.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
					.overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.fieldStroke))
				HStack(spacing: 12) {
					sampleButton
					sampleStatus
					Spacer()
				}
				if let note = model.sampleNote {
					Label(note, systemImage: "info.circle")
						.font(UI.caption).foregroundStyle(.orange)
						.transition(.opacity)
				}
			}
			.padding(14)
			.animation(.easeOut(duration: 0.15), value: model.sample)
			.animation(.easeOut(duration: 0.15), value: model.sampleNote)
		}
	}

	private var sampleButton: some View {
		Button {
			model.toggleSample(text: sampleText)
		} label: {
			HStack(spacing: 7) {
				switch model.sample {
				case .generating:
					ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
					Text("Cancel")
				case .playing:
					Image(systemName: "stop.fill").font(.system(size: 10))
					Text("Stop")
				case .idle, .done, .failed:
					Image(systemName: "play.fill").font(.system(size: 10))
					Text("Play Sample")
				}
			}
			.frame(minWidth: 110)
		}
		.buttonStyle(SubtleButtonStyle(isProminent: !model.sample.isBusy))
		.keyboardShortcut(.return, modifiers: .command)
		.disabled(sampleText.trimmingCharacters(in: .whitespaces).isEmpty && !model.sample.isBusy)
	}

	@ViewBuilder private var sampleStatus: some View {
		switch model.sample {
		case .idle:
			Text("⌘↩ to play · Using \(active.title)").font(UI.caption).foregroundStyle(.tertiary)
		case .generating(let since):
			TimelineView(.periodic(from: since, by: 0.1)) { ctx in
				Text("Generating with \(active.title)… \(String(format: "%.1f", ctx.date.timeIntervalSince(since)))s")
					.font(UI.caption.monospacedDigit()).foregroundStyle(.secondary)
			}
		case .playing(let providerTitle):
			HStack(spacing: 7) {
				PlayingBars()
				Text("Playing · \(providerTitle)").font(UI.caption).foregroundStyle(.secondary)
			}
		case .done:
			Label("Done", systemImage: "checkmark").font(UI.caption).foregroundStyle(.secondary)
		case .failed(let reason):
			Label(reason, systemImage: "xmark.circle").font(UI.caption).foregroundStyle(.red)
		}
	}
}

/// Small animated equalizer shown while audio plays.
struct PlayingBars: View {
	var body: some View {
		TimelineView(.animation) { ctx in
			let t = ctx.date.timeIntervalSinceReferenceDate
			HStack(alignment: .center, spacing: 2) {
				ForEach(0..<4, id: \.self) { i in
					Capsule()
						.fill(Color.accentColor)
						.frame(width: 2.5, height: 4 + 8 * abs(sin(t * 6 + Double(i) * 0.9)))
				}
			}
			.frame(height: 12)
		}
	}
}
