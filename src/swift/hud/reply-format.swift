import Foundation

/// Turns a reply (often light Markdown: bullets, bold labels, headings, code) into what the voice bar
/// shows: paragraphs and list items keep their line breaks, block syntax becomes plain typography
/// (headings bold, bullets "•"), and inline emphasis is rendered rather than shown as symbols.
enum ReplyFormat {
	/// The reply as display text: paragraphs separated by a blank line, each line still carrying inline
	/// Markdown (`**bold**`, `*italic*`, `` `code` ``) for `attributed(line:)`.
	static func display(text: String) -> String {
		var lines: [String] = []
		var isInCode = false
		for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
			let trimmed = raw.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
				isInCode.toggle()
				continue
			}
			if isInCode {
				// Code stays verbatim, shown in monospace when it can be.
				let code = raw.replacingOccurrences(of: "\t", with: "  ")
				lines.append(code.isEmpty || code.contains("`") ? code : "`\(code)`")
				continue
			}
			lines.append(format(line: raw))
		}
		// Blank-line runs become one paragraph break; no leading or trailing blanks.
		var out: [String] = []
		for line in lines {
			if line.trimmingCharacters(in: .whitespaces).isEmpty {
				if let last = out.last, !last.isEmpty { out.append("") }
			} else {
				out.append(line)
			}
		}
		while out.last == "" { out.removeLast() }
		return out.joined(separator: "\n")
	}

	/// Display text split into paragraphs (blank-line separated).
	static func paragraphs(display: String) -> [String] {
		display.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	}

	/// A piece of a paragraph: running text, or a list item ("•" or "3.") with its nesting level.
	enum Block: Equatable {
		case text(String)
		case item(marker: String, text: String, level: Int)
	}

	/// A paragraph split into list items and the running text between them.
	static func blocks(paragraph: String) -> [Block] {
		var blocks: [Block] = []
		var pending: [String] = []
		func flush() {
			if !pending.isEmpty { blocks.append(.text(pending.joined(separator: "\n"))) }
			pending = []
		}
		for line in paragraph.components(separatedBy: "\n") {
			let indent = line.prefix { $0 == " " }.count
			let body = line.dropFirst(indent)
			if let range = body.range(of: "^(•|\\d{1,3}\\.)  ", options: .regularExpression) {
				flush()
				let marker = body[range].trimmingCharacters(in: .whitespaces)
				blocks.append(.item(marker: marker, text: String(body[range.upperBound...]), level: indent / 4))
			} else {
				pending.append(line)
			}
		}
		flush()
		return blocks
	}

	/// One paragraph with its inline Markdown rendered (line breaks kept); plain text if it can't be parsed.
	static func attributed(paragraph: String) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(
			interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
		return (try? AttributedString(markdown: paragraph, options: options)) ?? AttributedString(paragraph)
	}

	/// The reply as plain text with its structure, no Markdown symbols (for copying).
	static func plain(text: String) -> String {
		paragraphs(display: display(text: text))
			.map { String(attributed(paragraph: $0).characters) }
			.joined(separator: "\n\n")
	}

	// MARK: Lines

	private static func format(line raw: String) -> String {
		var line = raw.replacingOccurrences(of: "\t", with: "    ")
		let indentWidth = line.prefix { $0 == " " }.count
		line = line.trimmingCharacters(in: .whitespaces)
		// Horizontal rules and table separators carry no text.
		if line.range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil { return "" }
		if line.range(of: "^\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?$", options: .regularExpression) != nil {
			return ""
		}
		line = inline(text: line)
		// Headings: their own bold line.
		if let match = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
			let title = line[match.upperBound...].replacingOccurrences(of: "**", with: "")
				.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
			return title.isEmpty ? "" : "**\(title)**"
		}
		// Block quotes: just the text.
		while line.hasPrefix(">") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
		// Table rows: cells side by side.
		if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 {
			let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
				.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
			return cells.joined(separator: "  ·  ")
		}
		let indent = String(repeating: "    ", count: min(3, indentWidth / 2))
		// Bullets ("- ", "* ", "+ ", task boxes) become "•".
		if let match = line.range(of: "^[-*+]\\s+(\\[[ xX]\\]\\s+)?", options: .regularExpression) {
			return indent + "•  " + line[match.upperBound...]
		}
		// Numbered items keep their number.
		if let match = line.range(of: "^\\d{1,3}[.)]\\s+", options: .regularExpression) {
			let number = line[match].trimmingCharacters(in: .whitespaces).dropLast()
			return indent + "\(number).  " + line[match.upperBound...]
		}
		return line
	}

	/// Inline syntax the renderer doesn't cover (images, links, underscores) made plain or rendered.
	private static func inline(text: String) -> String {
		var t = text
		t = t.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "<(https?://[^>]+)>", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "(?<![\\w_])__([^_]+)__(?![\\w_])", with: "**$1**", options: .regularExpression)
		t = t.replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)
		t = t.replacingOccurrences(of: "(?<=\\S) {2,}", with: " ", options: .regularExpression)
		return t
	}
}
