import AppKit

/// The menu bar shown while Bol acts as a regular app. The Edit menu is what makes ⌘C / ⌘V /
/// ⌘A work in text fields (pasting API keys).
enum MainMenu {
	static func make(settingsAction: Selector, target: AnyObject) -> NSMenu {
		let menu = NSMenu()

		let app = NSMenu(title: "Bol")
		app.addItem(
			withTitle: "About Bol", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""
		)
		app.addItem(.separator())
		let settings = app.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
		settings.target = target
		app.addItem(.separator())
		app.addItem(withTitle: "Hide Bol", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		let hideOthers = app.addItem(
			withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
		hideOthers.keyEquivalentModifierMask = [.command, .option]
		app.addItem(.separator())
		app.addItem(withTitle: "Quit Bol", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		menu.addItem(submenu: app, title: "Bol")

		let edit = NSMenu(title: "Edit")
		edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
		let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
		redo.keyEquivalentModifierMask = [.command, .shift]
		edit.addItem(.separator())
		edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		menu.addItem(submenu: edit, title: "Edit")

		let window = NSMenu(title: "Window")
		window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
		window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		menu.addItem(submenu: window, title: "Window")
		NSApp.windowsMenu = window

		return menu
	}
}

extension NSMenu {
	fileprivate func addItem(submenu: NSMenu, title: String) {
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.submenu = submenu
		addItem(item)
	}
}
