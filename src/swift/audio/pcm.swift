import AVFoundation

/// Helpers for raw signed 16-bit PCM and WAV.
enum PCM {
	enum WAVError: LocalizedError {
		case notWAV
		case unsupported(bitsPerSample: Int)

		var errorDescription: String? {
			switch self {
			case .notWAV: return "Response is not WAV audio"
			case .unsupported(let bits): return "Unsupported WAV (\(bits)-bit)"
			}
		}
	}

	static func int16Format(sampleRate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
		AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
	}

	/// Interleaved s16le bytes as a buffer (nil if there isn't a whole frame).
	static func buffer(int16Data data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
		let frameBytes = Int(format.channelCount) * 2
		let frames = AVAudioFrameCount(data.count / frameBytes)
		guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
			let destination = buffer.int16ChannelData?[0]
		else { return nil }
		buffer.frameLength = frames
		data.withUnsafeBytes { raw in
			if let source = raw.baseAddress { memcpy(destination, source, Int(frames) * frameBytes) }
		}
		return buffer
	}

	/// Converts one whole buffer with `converter` (whose input format must match the buffer's).
	static func convert(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> AVAudioPCMBuffer? {
		let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
		let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
		guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
			return nil
		}
		var isFed = false
		var error: NSError?
		converter.convert(to: output, error: &error) { _, status in
			if isFed {
				status.pointee = .noDataNow
				return nil
			}
			isFed = true
			status.pointee = .haveData
			return buffer
		}
		return error == nil && output.frameLength > 0 ? output : nil
	}

	/// Wraps 16 kHz mono s16le PCM in a WAV header.
	static func wavFile(pcm16kMono pcm: Data) -> Data {
		var data = Data()
		func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
		func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
		data.append(Data("RIFF".utf8))
		u32(UInt32(36 + pcm.count))
		data.append(Data("WAVEfmt ".utf8))
		u32(16)
		u16(1)  // PCM
		u16(1)  // mono
		u32(16000)
		u32(32000)
		u16(2)
		u16(16)
		data.append(Data("data".utf8))
		u32(UInt32(pcm.count))
		data.append(pcm)
		return data
	}

	/// Minimal RIFF/WAV parser (handles streaming headers with 0xFFFFFFFF sizes): format + s16le PCM.
	static func parseWAV(data d: Data) throws -> (format: AVAudioFormat, pcm: Data) {
		guard d.count > 12, String(decoding: d.prefix(4), as: UTF8.self) == "RIFF" else { throw WAVError.notWAV }
		var position = 12
		var sampleRate: Double = 22050
		var channels: AVAudioChannelCount = 1
		var bits = 16
		while position + 8 <= d.count {
			let chunkID = String(decoding: d[d.startIndex + position..<d.startIndex + position + 4], as: UTF8.self)
			let size = Int(d.readLE32(at: position + 4))
			if chunkID == "fmt " {
				channels = AVAudioChannelCount(d.readLE16(at: position + 10))
				sampleRate = Double(d.readLE32(at: position + 12))
				bits = Int(d.readLE16(at: position + 22))
			} else if chunkID == "data" {
				guard bits == 16 else { throw WAVError.unsupported(bitsPerSample: bits) }
				let start = position + 8
				let end = size == 0xFFFF_FFFF ? d.count : min(d.count, start + size)
				let pcm = d.subdata(in: d.startIndex + start..<d.startIndex + end)
				return (int16Format(sampleRate: sampleRate, channels: channels), pcm)
			}
			position += 8 + size + (size & 1)
		}
		throw WAVError.unsupported(bitsPerSample: bits)
	}

	/// Loudness 0...1 of a float buffer's first channel (RMS × `gain`).
	static func level(buffer: AVAudioPCMBuffer, gain: Float) -> Float? {
		guard let channel = buffer.floatChannelData?[0] else { return nil }
		let count = Int(buffer.frameLength)
		guard count > 0 else { return 0 }
		var sum: Float = 0
		for i in 0..<count { sum += channel[i] * channel[i] }
		return min(1, sqrt(sum / Float(count)) * gain)
	}
}

extension Data {
	fileprivate func readLE16(at i: Int) -> UInt16 {
		UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8
	}
	fileprivate func readLE32(at i: Int) -> UInt32 {
		(0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + i + $1]) << (8 * UInt32($1)) }
	}
}
