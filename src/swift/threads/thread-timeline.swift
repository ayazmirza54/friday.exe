import Foundation

/// What the Threads window draws, in order: a transcript's items grouped into turns the way t3code
/// shows them. A finished turn's steps (tools, and anything Bol said between them) fold into one
/// "Worked for 42s" row above its reply; the turn still running stays open.
enum TimelineEntry: Identifiable, Equatable {
	/// A fork's history copied from the main conversation, collapsed to one row.
	case inherited(count: Int, isShowing: Bool)
	case prompt(TranscriptItem)
	case work(Work)
	case reply(TranscriptItem)
	/// A task Bol started or messaged: a card that opens the task.
	case task(TranscriptItem)
	/// Compactions and the summary Claude Code carried forward.
	case marker(TranscriptItem)

	struct Work: Equatable {
		let id: String
		let items: [TranscriptItem]
		let startedAt: Date?
		let endedAt: Date?
		/// The turn is still going (the thread is live and this is its last turn).
		let isRunning: Bool
		let isInherited: Bool

		var calls: [ToolCall] {
			items.compactMap { item in
				if case .tool(let call) = item.kind { return call }
				return nil
			}
		}

		var duration: TimeInterval? {
			guard let startedAt, let endedAt else { return nil }
			return max(0, endedAt.timeIntervalSince(startedAt))
		}
	}

	var id: String {
		switch self {
		case .inherited: return "inherited"
		case .prompt(let item), .reply(let item), .marker(let item), .task(let item): return item.id
		case .work(let work): return "work-\(work.id)"
		}
	}

	var isInherited: Bool {
		switch self {
		case .inherited: return false
		case .prompt(let item), .reply(let item), .marker(let item), .task(let item): return item.isInherited
		case .work(let work): return work.isInherited
		}
	}

	/// When it happened, for the time dividers.
	var date: Date? {
		switch self {
		case .inherited: return nil
		case .prompt(let item), .reply(let item), .marker(let item), .task(let item): return item.date
		case .work(let work): return work.startedAt
		}
	}

	/// A gap this long between entries gets a divider with the time.
	static let dividerGap: TimeInterval = 30 * 60

	/// The entries that start after a pause (and the first one), each with the time to show above it.
	static func timeDividers(entries: [TimelineEntry]) -> [String: Date] {
		var dividers: [String: Date] = [:]
		var previous: Date?
		for entry in entries {
			guard let date = entry.date else { continue }
			if previous.map({ date.timeIntervalSince($0) >= dividerGap }) ?? true { dividers[entry.id] = date }
			previous = date
		}
		return dividers
	}

	static func make(items: [TranscriptItem], isLive: Bool, isShowingInherited: Bool) -> [TimelineEntry] {
		var entries: [TimelineEntry] = []
		let inheritedCount = items.filter(\.isInherited).count
		if inheritedCount > 0 { entries.append(.inherited(count: inheritedCount, isShowing: isShowingInherited)) }
		let shown = items.filter { !$0.isInherited || isShowingInherited }

		var turnStart: Date?
		var pending: [TranscriptItem] = []
		func flush(isLastTurn: Bool) {
			defer { pending = [] }
			guard let first = pending.first else { return }
			let isRunning = isLive && isLastTurn
			// Tasks are shown on their own, after the steps that led to them.
			let taskItems = pending.filter { item in
				if case .task = item.kind { return true }
				return false
			}
			var steps = pending.filter { item in
				if case .task = item.kind { return false }
				return true
			}
			var reply: TranscriptItem?
			if !isRunning, let last = steps.last, case .assistant = last.kind {
				reply = steps.removeLast()
			}
			if let firstStep = steps.first {
				let end = (reply ?? steps.last)?.date
				entries.append(
					.work(
						Work(
							id: firstStep.id, items: steps, startedAt: turnStart ?? first.date, endedAt: end,
							isRunning: isRunning, isInherited: firstStep.isInherited)))
			}
			entries.append(contentsOf: taskItems.map { .task($0) })
			if let reply { entries.append(.reply(reply)) }
		}

		for item in shown {
			switch item.kind {
			case .user:
				flush(isLastTurn: false)
				entries.append(.prompt(item))
				turnStart = item.date
			case .assistant, .tool, .task:
				pending.append(item)
			case .compaction, .summary:
				flush(isLastTurn: false)
				entries.append(.marker(item))
			}
		}
		flush(isLastTurn: true)
		return entries
	}
}

/// Markdown split into blocks for the Threads window. Inline styling (bold, code, links) is left to
/// AttributedString; this handles what it doesn't: code fences, headings, lists, quotes and tables.
enum MarkdownBlock: Equatable {
	case paragraph(String)
	case heading(level: Int, text: String)
	/// List items, each with its marker ("•" or "3.").
	case list([ListItem])
	case quote(String)
	case code(language: String, text: String)
	/// Pipe tables, kept as monospaced text.
	case table(String)

	struct ListItem: Equatable {
		let marker: String
		let text: String
		/// Nesting level, from the indentation.
		let depth: Int
	}

	static func parse(text: String) -> [MarkdownBlock] {
		var blocks: [MarkdownBlock] = []
		var paragraph: [String] = []
		var listItems: [ListItem] = []
		var quote: [String] = []
		var table: [String] = []
		var code: (language: String, lines: [String])?

		func flushText() {
			if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
			if !listItems.isEmpty { blocks.append(.list(listItems)) }
			if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
			if !table.isEmpty { blocks.append(.table(table.joined(separator: "\n"))) }
			paragraph = []
			listItems = []
			quote = []
			table = []
		}

		for line in text.components(separatedBy: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if var open = code {
				if trimmed.hasPrefix("```") {
					blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
					code = nil
				} else {
					open.lines.append(line)
					code = open
				}
				continue
			}
			if trimmed.hasPrefix("```") {
				flushText()
				code = (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
				continue
			}
			if trimmed.isEmpty {
				flushText()
				continue
			}
			if let heading = heading(line: trimmed) {
				flushText()
				blocks.append(heading)
				continue
			}
			if let item = listItem(line: line) {
				if !paragraph.isEmpty || !quote.isEmpty || !table.isEmpty { flushText() }
				listItems.append(item)
				continue
			}
			if trimmed.hasPrefix(">") {
				if !paragraph.isEmpty || !listItems.isEmpty || !table.isEmpty { flushText() }
				quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
				continue
			}
			if trimmed.hasPrefix("|") {
				if !paragraph.isEmpty || !listItems.isEmpty || !quote.isEmpty { flushText() }
				table.append(trimmed)
				continue
			}
			if let last = listItems.last, line.hasPrefix(" ") {
				// A wrapped list item continues on an indented line.
				listItems[listItems.count - 1] = ListItem(
					marker: last.marker, text: last.text + " " + trimmed, depth: last.depth)
				continue
			}
			if !listItems.isEmpty || !quote.isEmpty || !table.isEmpty { flushText() }
			paragraph.append(line)
		}
		if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
		flushText()
		return blocks
	}

	private static func heading(line: String) -> MarkdownBlock? {
		let hashes = line.prefix { $0 == "#" }.count
		guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
		return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
	}

	private static func listItem(line: String) -> ListItem? {
		let indent = line.prefix { $0 == " " || $0 == "\t" }
		let depth = min(3, indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2)
		let rest = line.dropFirst(indent.count)
		for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
			return ListItem(marker: "•", text: String(rest.dropFirst(2)), depth: depth)
		}
		let digits = rest.prefix { $0.isNumber }
		if !digits.isEmpty, digits.count <= 3, rest.dropFirst(digits.count).hasPrefix(". ") {
			return ListItem(marker: "\(digits).", text: String(rest.dropFirst(digits.count + 2)), depth: depth)
		}
		return nil
	}
}
