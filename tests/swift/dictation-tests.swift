import Foundation
import Testing

@testable import Bol

@Suite struct DictationGestureTests {
	private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

	private func run(
		_ steps: [(DictationGesture.Input, TimeInterval)], isLockEnabled: Bool = true
	) -> [DictationGesture.Output?] {
		var gesture = DictationGesture()
		gesture.isLockEnabled = isLockEnabled
		return steps.map { input, seconds in gesture.handle(input: input, at: t0.addingTimeInterval(seconds)) }
	}

	@Test func holdingDictatesUntilReleased() {
		#expect(run([(.press, 0), (.release, 2)]) == [.start, .finish])
	}

	@Test func aQuickTapIsDropped() {
		#expect(run([(.press, 0), (.release, 0.1)]) == [.start, .discard])
	}

	@Test func aDoubleTapLocksAndTheNextPressPastes() {
		let outputs = run([
			(.press, 0), (.release, 0.1), (.press, 0.25), (.release, 0.35), (.press, 4), (.release, 4.1),
		])
		#expect(outputs == [.start, .discard, .start, .lock, .finish, nil])
	}

	@Test func aSlowSecondTapIsJustAnotherTap() {
		#expect(
			run([(.press, 0), (.release, 0.1), (.press, 0.6), (.release, 0.7)]) == [.start, .discard, .start, .discard])
	}

	@Test func aSecondTapThatIsHeldIsAHold() {
		#expect(
			run([(.press, 0), (.release, 0.1), (.press, 0.2), (.release, 3)]) == [.start, .discard, .start, .finish])
	}

	@Test func doubleTapDoesNothingWhenLockIsOff() {
		let outputs = run([(.press, 0), (.release, 0.1), (.press, 0.2), (.release, 0.3)], isLockEnabled: false)
		#expect(outputs == [.start, .discard, .start, .discard])
	}

	@Test func aShortcutWithTheKeyIsDropped() {
		// fn-Delete: another key right after pressing the dictation key.
		#expect(run([(.press, 0), (.interrupt, 0.05), (.release, 0.2)]) == [.start, .discard, nil])
	}

	@Test func keysWellIntoAHoldAreIgnored() {
		#expect(run([(.press, 0), (.interrupt, 1), (.release, 2)]) == [.start, nil, .finish])
	}

	@Test func aLockedDictationIgnoresOtherKeys() {
		let outputs = run([(.press, 0), (.release, 0.1), (.press, 0.2), (.release, 0.3), (.interrupt, 1), (.press, 2)])
		#expect(outputs == [.start, .discard, .start, .lock, nil, .finish])
	}

	@Test func resetForgetsAPendingTap() {
		var gesture = DictationGesture()
		_ = gesture.handle(input: .press, at: t0)
		_ = gesture.handle(input: .release, at: t0.addingTimeInterval(0.1))
		gesture.reset()
		_ = gesture.handle(input: .press, at: t0.addingTimeInterval(0.2))
		#expect(gesture.handle(input: .release, at: t0.addingTimeInterval(0.3)) == .discard)
		#expect(gesture.state == .idle)
	}
}

@Suite struct DictationSettingsTests {
	@Test func dictationIsOnWithFnByDefault() throws {
		let config = try Config.decoded(data: Data("{}".utf8))
		#expect(config.dictation == DictationSettings())
		#expect(config.dictation.isEnabled)
		#expect(config.dictation.key == .fn)
	}

	@Test func anUnknownKeyFallsBackToFn() throws {
		let config = try Config.decoded(data: Data(#"{"dictation": {"key": "capsLock", "isEnabled": false}}"#.utf8))
		#expect(config.dictation.key == .fn)
		#expect(config.dictation.isEnabled == false)
	}
}
