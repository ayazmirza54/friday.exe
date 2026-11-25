import AVFoundation
import CoreAudio

/// Microphone capture, converted to 16 kHz mono PCM for speech-to-text. The mic is only open
/// while Bol is listening to you.
final class AudioCapture {
	private(set) var engine = AVAudioEngine()

	private var converter: AVAudioConverter?
	private let target = AVAudioFormat(
		commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
	private var configObserver: NSObjectProtocol?

	var onPCM16k: ((Data) -> Void)?
	/// Rolling input level 0..1.
	private(set) var level: Float = 0
	private(set) var isRunning = false

	func start() throws {
		// AVAudioEngine raises an uncatchable Objective-C exception when tapping a Mac with no
		// input device (a Mac mini with nothing plugged in), so check with Core Audio first.
		guard Self.hasInputDevice else {
			throw NSError(
				domain: "Bol", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone connected"])
		}
		engine = AVAudioEngine()  // fresh engine each time the mic is opened
		let input = engine.inputNode

		let fmt = input.outputFormat(forBus: 0)
		let hardware = input.inputFormat(forBus: 0)
		guard fmt.sampleRate > 0, fmt.channelCount > 0, hardware.sampleRate > 0, hardware.channelCount > 0 else {
			throw NSError(
				domain: "Bol", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
		}
		converter = AVAudioConverter(from: fmt, to: target)
		if fmt.channelCount > 1 { converter?.channelMap = [0] }  // multi-channel interfaces: the first input
		input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
			self?.handle(buffer: buf)
		}
		engine.prepare()
		try engine.start()
		isRunning = true
		Log.info(
			message:
				"audio: capturing \(fmt.sampleRate) Hz x\(fmt.channelCount)"
		)

		if configObserver == nil {
			configObserver = NotificationCenter.default.addObserver(
				forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
			) { [weak self] note in
				guard let self, (note.object as? AVAudioEngine) === self.engine else { return }
				Log.info(message: "audio: device configuration changed, restarting")
				self.restart()
			}
		}
	}

	/// The Mac has a default input device with at least one input channel.
	static var hasInputDevice: Bool {
		var device = AudioObjectID(kAudioObjectUnknown)
		var size = UInt32(MemoryLayout<AudioObjectID>.size)
		var address = AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain)
		guard
			AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
				== noErr, device != kAudioObjectUnknown
		else { return false }
		address.mSelector = kAudioDevicePropertyStreamConfiguration
		address.mScope = kAudioDevicePropertyScopeInput
		guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
		let list = UnsafeMutableRawPointer.allocate(
			byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
		defer { list.deallocate() }
		guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return false }
		let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
		return buffers.contains { $0.mNumberChannels > 0 }
	}

	func stop() {
		guard isRunning else { return }
		isRunning = false
		level = 0
		engine.inputNode.removeTap(onBus: 0)
		engine.stop()
	}

	private func restart() {
		guard isRunning else { return }
		stop()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			do { try self.start() } catch { Log.info(message: "audio: restart failed: \(error)") }
		}
	}

	private func handle(buffer buf: AVAudioPCMBuffer) {
		if let ch = buf.floatChannelData?[0] {
			var sum: Float = 0
			let n = Int(buf.frameLength)
			for i in 0..<n { sum += ch[i] * ch[i] }
			let rms = n > 0 ? sqrt(sum / Float(n)) : 0
			level = min(1, rms * 12)
		}

		guard let converter else { return }
		let ratio = target.sampleRate / buf.format.sampleRate
		let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 32
		guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
		var isFed = false
		var err: NSError?
		converter.convert(to: out, error: &err) { _, status in
			if isFed {
				status.pointee = .noDataNow
				return nil
			}
			isFed = true
			status.pointee = .haveData
			return buf
		}
		guard err == nil, out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
		onPCM16k?(Data(bytes: p, count: Int(out.frameLength) * 2))
	}
}
