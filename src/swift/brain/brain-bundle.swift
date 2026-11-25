import Foundation

/// The brain ships inside Bol.app as a self-contained executable (compiled with
/// `bun build --compile`, see build.sh). It drives the Claude Code installed on this Mac.
enum BrainBundle {
	/// Resources/brain/ in the app; build/brain/ in the repo when run with `swift run`.
	static var brainExecutable: URL? {
		let candidates = [
			Bundle.main.resourceURL?.appendingPathComponent("brain/bol-brain"),
			URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
				"build/brain/bol-brain"),
		]
		return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
	}
}
