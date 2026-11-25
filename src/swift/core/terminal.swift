import AppKit

/// Runs a shell command in a new Terminal window the user can see and interact with (sign-ins,
/// installers). Uses a temporary .command file, which needs no Automation permission.
enum Terminal {
	static func run(command: String) {
		let script = """
			#!/bin/zsh -l
			clear
			echo "Bol: running \\`\(command.replacingOccurrences(of: "`", with: "'"))\\`"
			echo
			\(command)
			echo
			echo "Done. You can close this window and return to Bol."
			"""
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("bol-\(UUID().uuidString).command")
		do {
			try script.write(to: file, atomically: true, encoding: .utf8)
			try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
			NSWorkspace.shared.open(file)
		} catch {
			Log.info(message: "terminal: couldn't open \(command): \(error)")
		}
	}
}
