import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--render-hud"), i + 1 < CommandLine.arguments.count {
	_ = NSApplication.shared
	MainActor.assumeIsolated { HUDPreview.render(to: CommandLine.arguments[i + 1]) }
	exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-hud-spec"), i + 2 < CommandLine.arguments.count {
	_ = NSApplication.shared
	MainActor.assumeIsolated {
		HUDPreview.renderSpec(specPath: CommandLine.arguments[i + 1], to: CommandLine.arguments[i + 2])
	}
	exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-onboarding"), i + 1 < CommandLine.arguments.count {
	_ = NSApplication.shared
	MainActor.assumeIsolated { OnboardingPreview.render(to: CommandLine.arguments[i + 1]) }
	exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-settings"), i + 1 < CommandLine.arguments.count {
	_ = NSApplication.shared
	MainActor.assumeIsolated { SettingsPreview.render(to: CommandLine.arguments[i + 1]) }
	exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-threads"), i + 1 < CommandLine.arguments.count {
	_ = NSApplication.shared
	MainActor.assumeIsolated { ThreadsPreview.render(to: CommandLine.arguments[i + 1]) }
	exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
