import Foundation
import Testing

@testable import Bol

@Suite struct PlanUsageTests {
	@Test func leavesOutTheCurrentSession() {
		let limits = PlanUsage.parse(object: [
			"limits": [
				["kind": "session", "group": "session", "percent": 40],
				["kind": "weekly", "group": "weekly", "percent": 12],
				[
					"kind": "weekly", "group": "weekly", "percent": 30,
					"scope": ["model": ["display_name": "Opus"]],
				],
			]
		])
		#expect(limits.map(\.title) == ["Weekly · all models", "Weekly · Opus"])
	}

	@Test func leavesItOutOfOlderResponsesToo() {
		let limits = PlanUsage.parse(object: [
			"five_hour": ["utilization": 55], "seven_day": ["utilization": 20], "seven_day_opus": NSNull(),
		])
		#expect(limits.map(\.title) == ["Weekly · all models"])
		#expect(!PlanUsage.parse(object: ["five_hour": NSNull()]).contains { $0.title.contains("session") })
	}
}
