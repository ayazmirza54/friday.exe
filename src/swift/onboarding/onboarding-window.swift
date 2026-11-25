import AppKit
import SwiftUI

/// The first-run setup window. Closing it before the end leaves setup unfinished; the menu
/// offers to continue it.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
	let model: OnboardingModel
	private var window: NSWindow?

	init(model: OnboardingModel) {
		self.model = model
	}

	func show() {
		let window = self.window ?? makeWindow()
		self.window = window
		model.windowShown()
		AppPresence.show(window: window)
	}

	func close() {
		window?.close()
	}

	private func makeWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: AppPresence.fittedRect(size: NSSize(width: 880, height: 600)),
			styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
			backing: .buffered, defer: false)
		window.title = "Set up Bol"
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
		window.isMovableByWindowBackground = true
		window.isReleasedWhenClosed = false
		window.delegate = self
		window.contentView = NSHostingView(rootView: OnboardingView(model: model, settings: model.settings))
		window.center()
		return window
	}

	func windowWillClose(_ notification: Notification) {
		model.windowClosed()  // never leave the mic open or a watcher polling behind a closed window
		AppPresence.windowClosed()
	}
}
