import Foundation

/// The user's own MCP servers, in ~/.bol/mcp.json (the brain reads it; see src/typescript/mcp-config.ts).
/// The format is the one Claude Code, Claude Desktop and Cursor share, so configs paste in as they are.
/// Edits keep every field Bol doesn't know about (timeout, alwaysLoad…) as written.
enum MCPConfig {
	static let file = Constants.bolDirectory.appendingPathComponent("mcp.json")
	/// Names Bol registers itself (mirrors RESERVED_MCP_NAMES in constants.ts).
	static let reservedNames: Set<String> = ["bol"]

	enum Kind: String, CaseIterable, Identifiable {
		case command, http, sse
		var id: String { rawValue }
		var title: String {
			switch self {
			case .command: return "Command"
			case .http: return "HTTP"
			case .sse: return "SSE"
			}
		}
	}

	/// One server as listed in Settings.
	struct Entry: Identifiable, Equatable {
		let name: String
		let kind: Kind
		/// The command line or URL.
		let summary: String
		let isEnabled: Bool
		var id: String { name }
	}

	struct ConfigError: Error, Equatable {
		let message: String
	}

	// MARK: Reading

	static func entries() -> [Entry] {
		servers().map { name, value in
			let isRemote = value["url"] != nil
			let kind: Kind = isRemote ? ((value["type"] as? String) == "sse" ? .sse : .http) : .command
			let summary =
				isRemote
				? (value["url"] as? String ?? "")
				: ([value["command"] as? String ?? ""] + (value["args"] as? [String] ?? [])).map(shellQuoted).joined(
					separator: " ")
			return Entry(name: name, kind: kind, summary: summary, isEnabled: (value["disabled"] as? Bool) != true)
		}
		.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	private static func document() -> [String: Any] {
		guard let data = try? Data(contentsOf: file),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return [:] }
		return object
	}

	private static func servers() -> [String: [String: Any]] {
		(document()["mcpServers"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
	}

	// MARK: Writing

	static func setEnabled(name: String, isEnabled: Bool) throws {
		try update { servers in
			guard var server = servers[name] as? [String: Any] else { return }
			if isEnabled { server.removeValue(forKey: "disabled") } else { server["disabled"] = true }
			servers[name] = server
		}
	}

	static func remove(name: String) throws {
		try update { $0.removeValue(forKey: name) }
	}

	/// Adds or replaces servers. Returns the names that replaced existing ones.
	@discardableResult
	static func add(servers new: [String: [String: Any]]) throws -> [String] {
		for (name, server) in new { try validate(name: name, server: server) }
		var replaced: [String] = []
		try update { servers in
			for (name, server) in new {
				if servers[name] != nil { replaced.append(name) }
				servers[name] = server
			}
		}
		return replaced.sorted()
	}

	/// Rewrites the file with one change, keeping everything else in it (other top-level keys too).
	private static func update(change: (inout [String: Any]) -> Void) throws {
		var document = document()
		var servers = document["mcpServers"] as? [String: Any] ?? [:]
		change(&servers)
		document["mcpServers"] = servers
		let data = try JSONSerialization.data(
			withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
		try FileManager.default.createDirectory(at: Constants.bolDirectory, withIntermediateDirectories: true)
		try data.write(to: file, options: .atomic)
		// It can hold tokens in env and headers: readable by this user only.
		try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
	}

	// MARK: Building and checking servers

	static func validate(name: String, server: [String: Any]) throws {
		guard name.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
			throw ConfigError(message: "“\(name)”: names can only use letters, digits, - and _.")
		}
		guard !reservedNames.contains(name) else {
			throw ConfigError(message: "“\(name)” is used by Bol itself; pick another name.")
		}
		if let url = server["url"] {
			guard let url = url as? String, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme)
			else { throw ConfigError(message: "“\(name)”: the URL must start with http:// or https://.") }
		} else {
			guard let command = server["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty
			else { throw ConfigError(message: "“\(name)” needs a command or a url.") }
		}
	}

	/// A server from the Add form. `commandLine` is split like a shell would; `pairs` are
	/// "KEY=value" lines (environment) or "Name: value" lines (headers).
	static func server(kind: Kind, commandLine: String, url: String, pairs: String) throws -> [String: Any] {
		switch kind {
		case .command:
			let words = try splitCommand(line: commandLine)
			guard let command = words.first else {
				throw ConfigError(message: "Enter the command that starts the server.")
			}
			var server: [String: Any] = ["command": command]
			if words.count > 1 { server["args"] = Array(words.dropFirst()) }
			let env = try parsePairs(text: pairs, separator: "=")
			if !env.isEmpty { server["env"] = env }
			return server
		case .http, .sse:
			var server: [String: Any] = ["type": kind.rawValue, "url": url.trimmingCharacters(in: .whitespaces)]
			let headers = try parsePairs(text: pairs, separator: ":")
			if !headers.isEmpty { server["headers"] = headers }
			return server
		}
	}

	/// Pasted JSON: a whole config ({"mcpServers": {...}}), a map of servers ({"github": {...}}), or one
	/// server ({"command": ...}), which then takes `name`.
	static func servers(pasted text: String, name: String) throws -> [String: [String: Any]] {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw ConfigError(message: "Paste a JSON config first.") }
		let object: Any
		do {
			object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
		} catch {
			throw ConfigError(message: "That isn't valid JSON.")
		}
		guard var map = object as? [String: Any] else {
			throw ConfigError(message: "Expected a JSON object, like {\"mcpServers\": {...}}.")
		}
		if let inner = map["mcpServers"] as? [String: Any] { map = inner }
		let isSingleServer = map["command"] is String || map["url"] is String
		if isSingleServer {
			let name = name.trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty else { throw ConfigError(message: "This is a single server: give it a name.") }
			map = [name: map]
		}
		var servers: [String: [String: Any]] = [:]
		for (key, value) in map {
			guard let server = value as? [String: Any] else {
				throw ConfigError(message: "“\(key)” isn't a server (expected an object with a command or url).")
			}
			try validate(name: key, server: server)
			servers[key] = server
		}
		guard !servers.isEmpty else { throw ConfigError(message: "No servers found in that JSON.") }
		return servers
	}

	/// Splits a command line into words: spaces separate, quotes group, backslash escapes.
	static func splitCommand(line: String) throws -> [String] {
		var words: [String] = []
		var current = ""
		var hasWord = false
		var quote: Character?
		var isEscaped = false
		for character in line {
			if isEscaped {
				current.append(character)
				isEscaped = false
			} else if character == "\\", quote != "'" {
				isEscaped = true
				hasWord = true
			} else if let open = quote {
				if character == open { quote = nil } else { current.append(character) }
			} else if character == "\"" || character == "'" {
				quote = character
				hasWord = true
			} else if character.isWhitespace {
				if hasWord { words.append(current) }
				current = ""
				hasWord = false
			} else {
				current.append(character)
				hasWord = true
			}
		}
		guard quote == nil else { throw ConfigError(message: "The command has an unclosed quote.") }
		if hasWord { words.append(current) }
		return words
	}

	/// "KEY=value" or "Name: value" lines; blank lines and # comments are skipped.
	static func parsePairs(text: String, separator: Character) throws -> [String: String] {
		var pairs: [String: String] = [:]
		for raw in text.split(whereSeparator: \.isNewline) {
			let line = raw.trimmingCharacters(in: .whitespaces)
			if line.isEmpty || line.hasPrefix("#") { continue }
			guard let index = line.firstIndex(of: separator) else {
				throw ConfigError(
					message: "“\(line)” should look like \(separator == "=" ? "KEY=value" : "Name: value").")
			}
			let key = line[..<index].trimmingCharacters(in: .whitespaces)
			guard !key.isEmpty else { throw ConfigError(message: "“\(line)” is missing its name.") }
			pairs[key] = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
		}
		return pairs
	}

	private static func shellQuoted(_ word: String) -> String {
		word.isEmpty || word.contains(where: { $0.isWhitespace || "\"'\\".contains($0) })
			? "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'" : word
	}
}

/// How the brain's MCP servers are doing, as it last reported (Settings shows it).
struct MCPStatusReport: Decodable, Equatable {
	struct Server: Decodable, Equatable {
		let name: String
		/// connected, failed, needs-auth, pending or disabled.
		let status: String
		let error: String?
		/// Where it's configured: dynamic (mcp.json), user / project / local (Claude Code), claudeai…
		let source: String?
		let tools: Int?
	}

	struct Problem: Decodable, Equatable {
		let name: String
		let error: String
	}

	let servers: [Server]
	let problems: [Problem]
}
