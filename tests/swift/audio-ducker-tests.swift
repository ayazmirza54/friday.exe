import Foundation
import Testing

@testable import Bol

@Suite struct AudioDuckerTests {
	/// Runs the ramp for `seconds` at 48 kHz and returns the last gain.
	private func run(ramp: AudioDucker.Ramp, seconds: Double) -> Float {
		let frames = Int(seconds * 48_000)
		let gains = UnsafeMutablePointer<Float>.allocate(capacity: frames)
		defer { gains.deallocate() }
		ramp.advance(frames: frames, sampleRate: 48_000, gains: gains)
		return gains[frames - 1]
	}

	@Test func fadesDownQuicklyAndUpSlowly() {
		let ramp = AudioDucker.Ramp()
		ramp.target = 0.2
		#expect(run(ramp: ramp, seconds: 0.06) > 0.2)  // halfway down, not there yet
		#expect(abs(run(ramp: ramp, seconds: 0.07) - 0.2) < 0.001)  // down within 120 ms
		ramp.target = 1
		#expect(run(ramp: ramp, seconds: 0.5) < 0.9)  // still rising after half a second
		#expect(abs(run(ramp: ramp, seconds: 0.51) - 1) < 0.001)  // back up within a second
		#expect(ramp.gain >= 0.999)
	}

	@Test func aNewTargetMidFadeStartsFromWhereTheGainIs() {
		let ramp = AudioDucker.Ramp()
		ramp.target = 0
		let halfway = run(ramp: ramp, seconds: 0.06)
		ramp.target = 1
		let next = run(ramp: ramp, seconds: 0.001)
		#expect(abs(next - halfway) < 0.01)  // no jump when the direction changes
	}
}
