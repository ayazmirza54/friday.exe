import AVFoundation
import Foundation
import Testing

@testable import Bol

@Suite struct PCMTests {
	private func pcm(samples: [Int16]) -> Data {
		samples.withUnsafeBufferPointer { Data(buffer: $0) }
	}

	@Test func int16LevelIsRMSTimesGain() {
		#expect(PCM.level(int16Data: Data(), gain: 12) == 0)
		#expect(PCM.level(int16Data: pcm(samples: Array(repeating: 0, count: 1280)), gain: 12) == 0)
		// A ±1/4 full-scale square wave has an RMS of 0.25.
		let quarter = pcm(samples: (0..<1280).map { $0.isMultiple(of: 2) ? 8192 : -8192 })
		#expect(abs(PCM.level(int16Data: quarter, gain: 1) - 0.25) < 0.0001)
		#expect(abs(PCM.level(int16Data: quarter, gain: 2) - 0.5) < 0.0001)
		#expect(PCM.level(int16Data: quarter, gain: 12) == 1)  // capped
	}

	@Test func int16LevelMatchesTheFloatLevel() throws {
		let samples: [Int16] = (0..<1600).map { Int16(sin(Double($0) / 7) * 3000) }
		let format = PCM.int16Format(sampleRate: 16000)
		let floatFormat = try #require(
			AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
		let int16Buffer = try #require(PCM.buffer(int16Data: pcm(samples: samples), format: format))
		let converter = try #require(AVAudioConverter(from: format, to: floatFormat))
		let floatBuffer = try #require(PCM.convert(buffer: int16Buffer, converter: converter))
		let floatLevel = try #require(PCM.level(buffer: floatBuffer, gain: 12))
		#expect(abs(PCM.level(int16Data: pcm(samples: samples), gain: 12) - floatLevel) < 0.001)
	}
}
