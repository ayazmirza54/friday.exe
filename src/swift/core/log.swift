import Foundation

enum Log {
	private static let queue = DispatchQueue(label: "bol.log")
	private static let formatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return formatter
	}()

	/// Only Bol.app writes the log file: tests and debug renders (`swift test`, `.build/debug/Bol`) log to
	/// stderr alone, so they never touch the user's ~/.bol/bol.log.
	private static let writesToFile = Bundle.main.bundleURL.pathExtension == "app"

	/// Appends a timestamped line to ~/.bol/bol.log (and stderr), off the calling thread.
	static func info(message: String) {
		let line = Data("[\(formatter.string(from: Date()))] \(message)\n".utf8)
		queue.async {
			FileHandle.standardError.write(line)
			guard writesToFile else { return }
			if let handle = try? FileHandle(forWritingTo: Constants.logFile) {
				handle.seekToEndOfFile()
				handle.write(line)
				try? handle.close()
			} else {
				try? line.write(to: Constants.logFile)
			}
		}
	}
}
