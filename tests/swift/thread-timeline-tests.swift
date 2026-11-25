import Foundation
import Testing

@testable import Bol

@Suite struct ThreadTimelineTests {
	private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

	private func item(_ id: String, _ seconds: TimeInterval, _ kind: TranscriptItem.Kind, isInherited: Bool = false)
		-> TranscriptItem
	{
		TranscriptItem(id: id, date: t0.addingTimeInterval(seconds), isInherited: isInherited, kind: kind)
	}

	private func tool(_ id: String, isError: Bool = false) -> TranscriptItem.Kind {
		.tool(
			ToolCall(
				id: id, name: "Bash", input: "", result: ToolResult(text: "", images: [], isError: isError),
				summary: ""))
	}

	private var turn: [TranscriptItem] {
		[
			item("u1", 0, .user(text: "Clean my desktop", notes: [])),
			item("t1", 2, tool("t1")),
			item("a1", 3, .assistant(text: "Found 12 screenshots, moving them.")),
			item("t2", 5, tool("t2", isError: true)),
			item("a2", 42, .assistant(text: "Done.")),
		]
	}

	@Test func aFinishedTurnFoldsItsStepsAboveTheReply() {
		let entries = TimelineEntry.make(items: turn, isLive: false, isShowingInherited: false)
		#expect(entries.map(\.id) == ["u1", "work-t1", "a2"])
		guard case .work(let work) = entries[1] else {
			Issue.record("expected work")
			return
		}
		#expect(work.items.map(\.id) == ["t1", "a1", "t2"])
		#expect(work.calls.count == 2)
		#expect(work.duration == 42)
		#expect(work.isRunning == false)
	}

	@Test func theRunningTurnStaysOpenWithEverythingInIt() {
		let entries = TimelineEntry.make(items: turn, isLive: true, isShowingInherited: false)
		#expect(entries.map(\.id) == ["u1", "work-t1"])
		guard case .work(let work) = entries[1] else {
			Issue.record("expected work")
			return
		}
		#expect(work.isRunning)
		#expect(work.items.count == 4)
	}

	@Test func onlyTheLastTurnRuns() {
		let items = turn + [item("u2", 60, .user(text: "Thanks", notes: [])), item("a3", 61, .assistant(text: "Sure"))]
		let entries = TimelineEntry.make(items: items, isLive: true, isShowingInherited: false)
		#expect(entries.map(\.id) == ["u1", "work-t1", "a2", "u2", "work-a3"])
	}

	@Test func aPlainReplyHasNoWorkRow() {
		let items = [item("u1", 0, .user(text: "Hi", notes: [])), item("a1", 1, .assistant(text: "Hello"))]
		#expect(TimelineEntry.make(items: items, isLive: false, isShowingInherited: false).map(\.id) == ["u1", "a1"])
	}

	@Test func forkedHistoryCollapsesUntilShown() {
		let items = [
			item("u0", 0, .user(text: "Earlier", notes: []), isInherited: true),
			item("a0", 1, .assistant(text: "Answer"), isInherited: true),
			item("u1", 10, .user(text: "Now", notes: [])),
		]
		#expect(
			TimelineEntry.make(items: items, isLive: false, isShowingInherited: false).map(\.id) == ["inherited", "u1"])
		#expect(
			TimelineEntry.make(items: items, isLive: false, isShowingInherited: true).map(\.id) == [
				"inherited", "u0", "a0", "u1",
			])
	}

	@Test func compactionsSplitTurns() {
		let items = [
			item("u1", 0, .user(text: "Go", notes: [])),
			item("t1", 1, tool("t1")),
			item("c1", 2, .compaction(trigger: "auto", tokensBefore: 1000)),
			item("a1", 3, .assistant(text: "Done")),
		]
		#expect(
			TimelineEntry.make(items: items, isLive: false, isShowingInherited: false).map(\.id) == [
				"u1", "work-t1", "c1", "a1",
			])
	}
}

@Suite struct MarkdownBlockTests {
	@Test func splitsBlocks() {
		let text = """
			## Plan
			First **this**,
			then that.

			- one
			- two
			  wrapped
			  - nested
			1. first
			> quoted

			```swift
			let x = 1

			print(x)
			```
			| a | b |
			|---|---|
			"""
		#expect(
			MarkdownBlock.parse(text: text) == [
				.heading(level: 2, text: "Plan"),
				.paragraph("First **this**,\nthen that."),
				.list([
					.init(marker: "•", text: "one", depth: 0), .init(marker: "•", text: "two wrapped", depth: 0),
					.init(marker: "•", text: "nested", depth: 1), .init(marker: "1.", text: "first", depth: 0),
				]),
				.quote("quoted"),
				.code(language: "swift", text: "let x = 1\n\nprint(x)"),
				.table("| a | b |\n|---|---|"),
			])
	}

	@Test func anUnclosedFenceKeepsItsCode() {
		#expect(MarkdownBlock.parse(text: "```\nrm -rf build") == [.code(language: "", text: "rm -rf build")])
	}

	@Test func hashtagsAreNotHeadings() {
		#expect(MarkdownBlock.parse(text: "#general is busy") == [.paragraph("#general is busy")])
	}
}

@Suite struct ThreadFormatTests {
	@Test func labelsSteps() {
		#expect(TranscriptParser.label(name: "Read", input: ["file_path": "/tmp/a/hud.swift"]) == "Read hud.swift")
		#expect(TranscriptParser.label(name: "Edit", input: ["file_path": "/x/config.swift"]) == "Edited config.swift")
		#expect(TranscriptParser.label(name: "Grep", input: ["pattern": "TODO"]) == "Searched for “TODO”")
		#expect(
			TranscriptParser.label(name: "Bash", input: ["command": "ls", "description": "List files"]) == "List files")
		#expect(TranscriptParser.label(name: "Bash", input: ["command": "ls -la"]) == "Ran ls -la")
		#expect(TranscriptParser.label(name: "WebFetch", input: ["url": "https://example.com/a"]) == "Read example.com")
		#expect(TranscriptParser.label(name: "mcp__bol__screenshot", input: [:]) == "Screenshot")
	}

	@Test func formatsDurationsAndTimes() {
		#expect(Format.duration(seconds: 42) == "42s")
		#expect(Format.duration(seconds: 192) == "3m 12s")
		#expect(Format.duration(seconds: 120) == "2m")
		#expect(Format.duration(seconds: 3840) == "1h 4m")
		let now = Date(timeIntervalSinceReferenceDate: 100_000)
		#expect(Format.compact(date: now.addingTimeInterval(-20), now: now) == "now")
		#expect(Format.compact(date: now.addingTimeInterval(-300), now: now) == "5m")
		#expect(Format.compact(date: now.addingTimeInterval(-3 * 3600), now: now) == "3h")
		#expect(Format.compact(date: now.addingTimeInterval(-2 * 86_400), now: now) == "2d")
	}
}

@Suite struct ThreadTaskTests {
	private func jsonl(_ entries: [[String: Any]]) -> Data {
		Data(
			entries.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
				.joined(separator: "\n").utf8)
	}

	@Test func parsesStartedAndMessagedTasks() {
		let data = jsonl([
			[
				"type": "user", "uuid": "u1", "timestamp": "2026-11-18T10:00:00.000Z",
				"message": ["role": "user", "content": "Make the extension icon nicer"],
			],
			[
				"type": "assistant", "uuid": "a1", "timestamp": "2026-11-18T10:00:02.000Z",
				"message": [
					"content": [
						[
							"type": "tool_use", "id": "t1", "name": "mcp__bol__start_task",
							"input": ["name": "Extension icon", "brief": "Redesign the icon"],
						]
					]
				],
			],
			[
				"type": "user", "uuid": "u2", "timestamp": "2026-11-18T10:00:03.000Z",
				"message": [
					"content": [
						["type": "tool_result", "tool_use_id": "t1", "content": "Started task \"Extension icon\"."]
					]
				],
			],
			[
				"type": "assistant", "uuid": "a2", "timestamp": "2026-11-18T10:00:04.000Z",
				"message": [
					"content": [
						[
							"type": "tool_use", "id": "t2", "name": "mcp__bol__start_task",
							"input": ["name": "Extension icon", "brief": "Again"],
						]
					]
				],
			],
			[
				"type": "user", "uuid": "u3", "timestamp": "2026-11-18T10:00:05.000Z",
				"message": [
					"content": [
						[
							"type": "tool_result", "tool_use_id": "t2",
							"content": "There's already a task named \"Extension icon\" (running).",
						]
					]
				],
			],
			[
				"type": "assistant", "uuid": "a3", "timestamp": "2026-11-18T10:00:06.000Z",
				"message": ["content": [["type": "text", "text": "On it."]]],
			],
		])
		let transcript = TranscriptParser.parse(data: data)
		let entries = TimelineEntry.make(items: transcript.items, isLive: false, isShowingInherited: false)
		#expect(entries.map(\.id) == ["u1", "t1", "t2", "a3-0"])
		guard case .task(let item) = entries[1], case .task(let mention) = item.kind,
			case .task(let refusedItem) = entries[2], case .task(let refused) = refusedItem.kind
		else {
			Issue.record("expected task cards")
			return
		}
		#expect(
			mention
				== TaskMention(
					name: "Extension icon", text: "Redesign the icon", isStart: true,
					reply: "Started task \"Extension icon\"."))
		#expect(!mention.isRefused)
		#expect(refused.isRefused)
		#expect(transcript.searchableText.contains("Redesign the icon"))
	}

	@Test func readsTheTaskIndex() {
		let text = """
			{"taskId":"t1","name":"Icon","sessionId":"s1","threadId":"th","at":"2026-11-18T10:00:00.000Z"}
			{"taskId":"t2","name":"Report","sessionId":"s2","threadId":null,"at":"2026-11-18T11:00:00.000Z"}
			{"taskId":"t1","name":"Icon","sessionId":"s3","threadId":"th","at":"2026-11-18T12:00:00.000Z"}
			not json
			"""
		let records = TaskIndex.records(text: text)
		#expect(records.map(\.taskId) == ["t1", "t2"])
		#expect(records[0].sessionId == "s3")
		#expect(records[0].at == TranscriptParser.parseDate("2026-11-18T10:00:00.000Z"))
		#expect(records[1].threadId == nil)
	}
}

@Suite struct ThreadDeletionTests {
	@Test func deletedThreadsDropOutOfTheIndex() {
		let text = """
			{"sessionId":"s1","job":null,"forkedFrom":null,"at":"2026-11-18T10:00:00.000Z"}
			{"sessionId":"s2","job":null,"forkedFrom":null,"at":"2026-11-18T11:00:00.000Z"}
			{"sessionId":"s1","isDeleted":true,"at":"2026-11-18T12:00:00.000Z"}
			"""
		#expect(ThreadIndex.deletedIds(indexText: text) == ["s1"])
		// The tombstone isn't a thread start; the store drops deleted ids afterwards.
		#expect(ThreadIndex.records(indexText: text).map(\.sessionId) == ["s1", "s2"])
	}

	@Test func deletedTasksDropOutOfTheIndex() {
		let text = """
			{"taskId":"t1","name":"Icon","sessionId":"a","threadId":"s1","at":"2026-11-18T10:00:00.000Z"}
			{"taskId":"t2","name":"Report","sessionId":"b","threadId":"s2","at":"2026-11-18T10:00:00.000Z"}
			{"taskId":"t1","isDeleted":true,"at":"2026-11-18T12:00:00.000Z"}
			"""
		#expect(TaskIndex.records(text: text).map(\.taskId) == ["t2"])
	}
}
