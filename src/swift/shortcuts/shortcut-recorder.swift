import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click it and press the new combination; it's saved right away. Esc cancels, ⌫ turns the
/// shortcut off. A combination macOS or another Bol shortcut already uses is refused with why.
struct ShortcutRecorder: View {
	@Binding var settings: ShortcutSettings
	let action: ShortcutAction
	@ObservedObject private var state = ShortcutState.shared
	@State private var isRecording = false
	@State private var held: [Shortcut.Modifier] = []
	@State private var problem: String?
	@State private var monitor: Any?
	@State private var isHovering = false

	private static let faceWidth: CGFloat = 150

	var body: some View {
		VStack(alignment: .trailing, spacing: 5) {
			HStack(spacing: 4) {
				Button(action: toggle) { face }
					.buttonStyle(.plain)
					.onHover { isHovering = $0 }
					.help(isRecording ? "Press the new shortcut. Esc cancels, ⌫ turns it off" : "Click to change")
				IconButton(symbol: "xmark", help: "Turn off") { settings[action] = nil }
					.opacity(isRecording || settings[action] == nil ? 0 : 1)
					.disabled(isRecording || settings[action] == nil)
				IconButton(symbol: "arrow.counterclockwise", help: resetHelp) {
					settings[action] = action.defaultShortcut
				}
				.opacity(isRecording || isDefault ? 0 : 1)
				.disabled(isRecording || isDefault)
			}
			if let note {
				Text(note).font(UI.caption).foregroundStyle(.orange)
					.frame(width: Self.faceWidth + 60, alignment: .leading)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.onDisappear { stop() }
		.onReceive(state.$recording) { recording in
			if recording != action, isRecording { stop() }  // another recorder took over
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
		.animation(.easeOut(duration: 0.12), value: isRecording)
	}

	private var face: some View {
		HStack(spacing: 6) {
			if isRecording {
				if held.isEmpty {
					Text("Press keys…").foregroundStyle(.secondary)
				} else {
					KeyCaps(glyphs: held.map(\.glyph))
				}
			} else if let shortcut = settings[action] {
				KeyCaps(shortcut: shortcut)
			} else {
				Text("Record Shortcut").foregroundStyle(.tertiary)
			}
		}
		.font(UI.body)
		.frame(width: Self.faceWidth, height: 30)
		.background(
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.fill(
					isRecording
						? Color.accentColor.opacity(0.08) : isHovering ? UI.fieldFill.opacity(1.6) : UI.fieldFill)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.strokeBorder(
					isRecording ? Color.accentColor.opacity(0.8) : UI.fieldStroke, lineWidth: isRecording ? 1.5 : 1)
		)
		.contentShape(Rectangle())
	}

	private var isDefault: Bool { settings[action] == action.defaultShortcut }

	private var resetHelp: String {
		guard let shortcut = action.defaultShortcut else { return "Reset (no shortcut)" }
		return "Reset to \(shortcut.plainText)"
	}

	private var note: String? {
		if let problem { return problem }
		if !isRecording, settings[action] != nil, state.unavailable.contains(action) {
			return "Another app is using this shortcut. Pick another one."
		}
		return nil
	}

	private func toggle() {
		if isRecording { stop() } else { start() }
	}

	private func start() {
		problem = nil
		held = []
		isRecording = true
		state.recording = action
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
			handle(event: event)
			return nil  // every key goes to the recorder while it listens
		}
	}

	private func stop() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
		held = []
		isRecording = false
		if state.recording == action { state.recording = nil }
	}

	private func handle(event: NSEvent) {
		let modifiers = Shortcut.modifiers(flags: event.modifierFlags)
		if event.type == .flagsChanged {
			held = modifiers
			return
		}
		let keyCode = Int(event.keyCode)
		if modifiers.isEmpty, keyCode == kVK_Escape {
			problem = nil
			stop()
			return
		}
		if modifiers.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
			problem = nil
			stop()
			settings[action] = nil
			return
		}
		let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
		if let problem = settings.problem(shortcut: shortcut, action: action) {
			self.problem = problem  // keep listening for another try
			NSSound.beep()
			return
		}
		problem = nil
		stop()  // the global shortcuts come back first, then the new one takes its place
		settings[action] = shortcut
	}
}
