import Foundation
import Testing

@testable import Bol

@Suite struct ThreadTranscriptTests {
	private func jsonl(_ entries: [[String: Any]]) -> Data {
		Data(
			entries.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
				.joined(separator: "\n").utf8)
	}

	@Test func splitsBolNotesFromTheRequest() {
		let (request, notes) = TranscriptParser.splitNotes(
			text: "[A background task finished.]\n\n[You are running this as a task.]\n\nOpen Notes [please]")
		#expect(request == "Open Notes [please]")
		#expect(notes == ["A background task finished.", "You are running this as a task."])
	}

	@Test func namesTools() {
		#expect(TranscriptParser.displayName(tool: "mcp__bol__look_at_screen") == "look at screen")
		#expect(TranscriptParser.displayName(tool: "mcp__github__get_issue") == "github · get_issue")
		#expect(TranscriptParser.displayName(tool: "Bash") == "Bash")
	}

	@Test func parsesATurnWithToolsAndUsage() {
		let data = jsonl([
			["type": "attachment", "uuid": "a0"],
			[
				"type": "user", "uuid": "u1", "timestamp": "2026-11-17T08:40:50.924Z",
				"message": ["role": "user", "content": "[Note]\n\nWhat's on my calendar?"],
			],
			[
				"type": "assistant", "uuid": "a1", "timestamp": "2026-11-17T08:40:52.000Z",
				"message": [
					"model": "claude-opus-5-5",
					"usage": ["input_tokens": 2, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 500],
					"content": [
						["type": "thinking", "thinking": ""],
						[
							"type": "tool_use", "id": "t1", "name": "Bash",
							"input": ["command": "icalBuddy", "description": "List today's events"],
						],
					],
				],
			],
			[
				"type": "user", "uuid": "u2", "timestamp": "2026-11-17T08:40:53.000Z",
				"message": [
					"role": "user",
					"content": [
						["type": "tool_result", "tool_use_id": "t1", "content": "10:00 Standup", "is_error": false]
					],
				],
			],
			[
				"type": "assistant", "uuid": "s1", "isSidechain": true,
				"message": ["content": [["type": "text", "text": "subagent chatter"]]],
			],
			[
				"type": "assistant", "uuid": "a2", "timestamp": "2026-11-17T08:40:55.000Z",
				"message": [
					"model": "claude-opus-5-5", "content": [["type": "text", "text": "Just standup at ten."]],
				],
			],
		])
		let transcript = TranscriptParser.parse(data: data)
		#expect(transcript.title == "What's on my calendar?")
		#expect(transcript.model == "claude-opus-5-5")
		#expect(transcript.contextTokens == 1502)
		#expect(transcript.items.count == 3)
		#expect(transcript.items[0].kind == .user(text: "What's on my calendar?", notes: ["Note"]))
		guard case .tool(let call) = transcript.items[1].kind else {
			Issue.record("expected a tool call")
			return
		}
		#expect(call.summary == "List today's events")
		#expect(call.result == ToolResult(text: "10:00 Standup", images: [], isError: false))
		#expect(transcript.items[2].kind == .assistant(text: "Just standup at ten."))
		#expect(TranscriptParser.title(data: data) == "What's on my calendar?")
	}

	@Test func showsCompactionAndMarksForkedHistory() {
		let data = jsonl([
			[
				"type": "user", "uuid": "u1", "timestamp": "2026-11-17T08:00:00.000Z",
				"message": ["content": "Earlier request"],
			],
			[
				"type": "system", "subtype": "compact_boundary", "uuid": "c1", "timestamp": "2026-11-17T09:00:00.000Z",
				"compactMetadata": ["trigger": "auto", "preTokens": 167_000],
			],
			[
				"type": "user", "uuid": "u2", "isCompactSummary": true, "timestamp": "2026-11-17T09:00:01.000Z",
				"message": ["content": "Summary of what happened"],
			],
		])
		let since = TranscriptParser.parseDate("2026-11-17T08:30:00.000Z")
		let transcript = TranscriptParser.parse(data: data, since: since)
		#expect(transcript.items.map(\.isInherited) == [true, false, false])
		#expect(transcript.items[1].kind == .compaction(trigger: "auto", tokensBefore: 167_000))
		#expect(transcript.items[2].kind == .summary(text: "Summary of what happened"))
	}
}

@Suite struct ThreadIndexTests {
	@Test func mergesStartsAndMoves() {
		let records = ThreadIndex.records(
			indexText: """
				{"sessionId":"s1","job":null,"forkedFrom":null,"at":"2026-11-17T08:00:00.000Z"}
				{"sessionId":"s2","job":"j2","forkedFrom":"s1","at":"2026-11-17T08:05:00.000Z"}
				{"sessionId":"s1","job":"j9","forkedFrom":null,"at":"2026-11-17T08:10:00.000Z"}
				not json
				""")
		let merged = ThreadIndex.merge(records: records)
		#expect(merged.count == 2)
		#expect(merged["s1"]?.job == "j9")
		#expect(merged["s1"]?.at == TranscriptParser.parseDate("2026-11-17T08:00:00.000Z"))
		#expect(merged["s2"]?.forkedFrom == "s1")
	}

	@Test func readsSessionsFromTheLog() {
		let records = ThreadIndex.records(
			logText: """
				[2026-11-17 14:10:11.342] brain: session cb5dce2e-4c48-4f6e-8c51-117f4561f528 model=claude-opus-5-5 effort=medium job=j07754f71
				[2026-11-15 19:39:52.548] brain: session 0a192b00-c306-4887-aba6-629f83bb48be model=claude-fable-5-2
				[2026-11-15 19:39:52.600] brain: mcp servers: bol=connected
				""")
		#expect(
			records.map(\.sessionId) == [
				"cb5dce2e-4c48-4f6e-8c51-117f4561f528", "0a192b00-c306-4887-aba6-629f83bb48be",
			])
		#expect(records.map(\.job) == ["j07754f71", nil])
	}
}
