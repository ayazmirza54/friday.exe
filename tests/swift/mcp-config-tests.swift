import Foundation
import Testing

@testable import Bol

@Suite struct MCPConfigTests {
	@Test func splitsCommandLinesLikeAShell() throws {
		#expect(try MCPConfig.splitCommand(line: "npx -y @scope/server") == ["npx", "-y", "@scope/server"])
		#expect(
			try MCPConfig.splitCommand(line: #"uvx mcp-server --root "/Users/me/My Docs" --name='a b'"#)
				== ["uvx", "mcp-server", "--root", "/Users/me/My Docs", "--name=a b"])
		#expect(
			try MCPConfig.splitCommand(line: #"node /path/with\ space/index.js """#) == [
				"node", "/path/with space/index.js", "",
			])
		#expect(try MCPConfig.splitCommand(line: "   ") == [])
		#expect(throws: MCPConfig.ConfigError.self) { try MCPConfig.splitCommand(line: #"npx "unclosed"#) }
	}

	@Test func parsesEnvironmentAndHeaderLines() throws {
		#expect(
			try MCPConfig.parsePairs(text: "TOKEN=abc=def\n\n# comment\n KEY = value ", separator: "=")
				== ["TOKEN": "abc=def", "KEY": "value"])
		#expect(
			try MCPConfig.parsePairs(text: "Authorization: Bearer x:y", separator: ":")
				== ["Authorization": "Bearer x:y"])
		#expect(throws: MCPConfig.ConfigError.self) { try MCPConfig.parsePairs(text: "NOEQUALS", separator: "=") }
	}

	@Test func buildsServersFromTheForm() throws {
		let local = try MCPConfig.server(kind: .command, commandLine: "npx -y pkg", url: "", pairs: "A=1")
		#expect(local["command"] as? String == "npx")
		#expect(local["args"] as? [String] == ["-y", "pkg"])
		#expect(local["env"] as? [String: String] == ["A": "1"])
		let remote = try MCPConfig.server(kind: .sse, commandLine: "", url: " https://x.dev/sse ", pairs: "")
		#expect(remote["type"] as? String == "sse")
		#expect(remote["url"] as? String == "https://x.dev/sse")
		#expect(remote["headers"] == nil)
	}

	@Test func importsAWholeConfig() throws {
		let servers = try MCPConfig.servers(
			pasted:
				#"{"mcpServers": {"fs": {"command": "npx", "args": ["x"]}, "web": {"type": "http", "url": "https://a.b/mcp"}}}"#,
			name: "")
		#expect(Set(servers.keys) == ["fs", "web"])
	}

	@Test func importsAMapOfServersAndASingleNamedServer() throws {
		#expect(try MCPConfig.servers(pasted: #"{"gh": {"command": "gh-mcp"}}"#, name: "").keys.sorted() == ["gh"])
		#expect(
			try MCPConfig.servers(pasted: #"{"url": "https://a.b/mcp"}"#, name: "remote").keys.sorted() == ["remote"])
		#expect(throws: MCPConfig.ConfigError.self) { try MCPConfig.servers(pasted: #"{"command": "x"}"#, name: "") }
	}

	@Test(arguments: [
		#"not json"#, #"[1, 2]"#, #"{"bol": {"command": "x"}}"#, #"{"bad name": {"command": "x"}}"#,
		#"{"x": {"url": "ftp://nope"}}"#, #"{"x": {"args": ["no command"]}}"#, #"{"x": "string"}"#, "",
	])
	func rejectsBadConfigs(text: String) {
		#expect(throws: MCPConfig.ConfigError.self) { try MCPConfig.servers(pasted: text, name: "") }
	}
}
