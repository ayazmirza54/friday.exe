import AppKit

/// Bol lives in the menu bar. While one of its windows (setup, Settings) is open it acts as a
/// regular app: Dock icon, ⌘-Tab, its own menu bar. When the last one closes it goes back.
enum AppPresence {
	static func show(window: NSWindow) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
		fitOnScreen(window: window)
		window.makeKeyAndOrderFront(nil)
		// SwiftUI sizes a window to its content after it's shown; fit again once that has happened.
		DispatchQueue.main.async { fitOnScreen(window: window) }
	}

	/// A window rect of `size`, shrunk to fit the main screen's visible area.
	static func fittedRect(size: NSSize) -> NSRect {
		let visible = NSScreen.main?.visibleFrame.size ?? size
		return NSRect(x: 0, y: 0, width: min(size.width, visible.width), height: min(size.height, visible.height))
	}

	/// Keeps the whole window inside the visible screen area (clear of the menu bar and Dock), so
	/// footers and buttons are never hidden on small displays.
	private static func fitOnScreen(window: NSWindow) {
		guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
		var frame = window.frame
		frame.size.width = min(frame.width, visible.width)
		frame.size.height = min(frame.height, visible.height)
		frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
		frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
		if frame != window.frame { window.setFrame(frame, display: false) }
	}

	/// Call when a window closes; decides once the close has finished.
	static func windowClosed() {
		DispatchQueue.main.async {
			// Titled windows only: the voice bar is a borderless panel and doesn't count.
			let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
			NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
		}
	}
}
