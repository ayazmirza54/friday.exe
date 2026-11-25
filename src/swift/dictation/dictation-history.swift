import Foundation

/// One dictation pasted into an app.
struct DictationRecord: Codable, Identifiable, Equatable {
	var id = UUID()
	let at: Date
	let text: String
	/// The app it was dictated into.
	let app: String?
}

/// Recent dictations, newest first, kept a week in ~/.bol/dictations.jsonl (on this Mac only), for
/// "Paste Last Dictation" and Settings. Main thread; file work runs on a background queue.
final class DictationHistory: ObservableObject {
	static let keepDays = 7

	@Published private(set) var records: [DictationRecord] = []
	private let queue = DispatchQueue(label: "bol.dictations")

	var last: DictationRecord? { records.first }

	func load() {
		queue.async {
			let cutoff = Date().addingTimeInterval(-Double(Self.keepDays) * 86_400)
			let text = (try? String(contentsOf: Constants.dictationsFile, encoding: .utf8)) ?? ""
			let lines = text.split(whereSeparator: \.isNewline)
			let records = lines.compactMap { Self.decoder.decodeRecord(line: $0) }.filter { $0.at > cutoff }
			if records.count != lines.count { Self.write(records: records) }
			DispatchQueue.main.async { self.records = records.reversed() }
		}
	}

	func add(text: String, app: String?) {
		let record = DictationRecord(at: Date(), text: text, app: app)
		records.insert(record, at: 0)
		queue.async {
			guard var line = try? Self.encoder.encode(record) else { return }
			line.append(UInt8(ascii: "\n"))
			Self.append(line: line)
		}
	}

	func clear() {
		records = []
		queue.async { Self.write(records: []) }
	}

	// MARK: File (background queue)

	private static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		return encoder
	}()

	private static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}()

	private static func append(line: Data) {
		let url = Constants.dictationsFile
		guard let handle = try? FileHandle(forWritingTo: url) else {
			try? line.write(to: url, options: .atomic)
			chmod(url.path, 0o600)
			return
		}
		defer { try? handle.close() }
		_ = try? handle.seekToEnd()
		try? handle.write(contentsOf: line)
	}

	private static func write(records: [DictationRecord]) {
		let lines = records.compactMap { try? encoder.encode($0) }
		var data = Data(lines.joined(separator: Data("\n".utf8)))
		if !lines.isEmpty { data.append(UInt8(ascii: "\n")) }
		try? data.write(to: Constants.dictationsFile, options: .atomic)
		chmod(Constants.dictationsFile.path, 0o600)
	}
}

extension JSONDecoder {
	fileprivate func decodeRecord(line: Substring) -> DictationRecord? {
		try? decode(DictationRecord.self, from: Data(line.utf8))
	}
}
