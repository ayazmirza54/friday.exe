import AudioToolbox
import CoreAudio
import Foundation

/// Microphone capture as 16 kHz mono PCM for speech-to-text. The mic is only open while Bol is listening to you.
///
/// It records with an input-only Audio Queue, not AVAudioEngine. On macOS, AVAudioEngine's input node runs through
/// a private aggregate of the default input and output devices, and after an audio device change that aggregate can
/// report no input channels while its microphone reports one. `AVAudioEngine.inputNode` then retries forever, and
/// Bol froze. The queue opens the input device itself and resamples to 16 kHz.
///
/// The device opens and closes on a private queue, never the main thread: Core Audio waits on coreaudiod, and if
/// opening stalls, listening fails with an error instead of freezing Bol.
final class AudioCapture {
	enum CaptureError: LocalizedError {
		case noInputDevice
		case notResponding
		case coreAudio(call: String, status: OSStatus)

		var errorDescription: String? {
			switch self {
			case .noInputDevice: return "No microphone connected"
			case .notResponding:
				return "The microphone didn't respond. Try again, or choose another input in System Settings → Sound."
			case .coreAudio(let call, let status): return "\(call) failed (error \(status))"
			}
		}
	}

	/// 16 kHz mono s16le audio, called on a private queue.
	var onPCM16k: ((Data) -> Void)?
	/// The mic failed after `start` returned (it didn't open, or the input went away), and capture stopped. Main
	/// queue.
	var onError: ((Error) -> Void)?
	/// Rolling input level 0..1.
	private(set) var level: Float = 0
	/// The mic is wanted: `start` was called, and neither `stop` nor a failure came after. Main thread.
	private(set) var isRunning = false

	/// Main thread: the device is open and recording.
	private var isOpen = false
	/// Main thread: bumped on every open and close, so answers about an earlier open are ignored.
	private var generation = 0
	private var defaultInputListener: AudioObjectPropertyListenerBlock?

	/// Opens and closes the device, in the order asked. Only it touches `queue`.
	private let control = DispatchQueue(label: "bol.mic")
	/// Recorded buffers arrive here.
	private let delivery = DispatchQueue(label: "bol.mic.buffers")
	private var queue: AudioQueueRef?
	/// The queue whose buffers may be read. It is cleared under `lock` before that queue is disposed, which frees them.
	private var liveQueue: AudioQueueRef?
	private let lock = NSLock()

	deinit {
		if let defaultInputListener {
			var address = Self.defaultInputAddress
			AudioObjectRemovePropertyListenerBlock(
				AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultInputListener)
		}
		// Blocks on `control` hold self, so none are left: the queue can be closed from here.
		if let queue { AudioQueueDispose(queue, true) }
	}

	func start() throws {
		guard !isRunning else { return }
		// Without an input device, say so now rather than when opening times out.
		guard Self.hasInputDevice else { throw CaptureError.noInputDevice }
		isRunning = true
		watchDefaultInput()
		open()
	}

	func stop() {
		guard isRunning else { return }
		isRunning = false
		close()
	}

	/// The Mac has a default input device with at least one input channel.
	static var hasInputDevice: Bool { (defaultInput()?.channelCount ?? 0) > 0 }

	// MARK: Opening and closing (main thread)

	private func open() {
		generation += 1
		let opening = generation
		control.async { self.openDevice(generation: opening) }
		DispatchQueue.main.asyncAfter(deadline: .now() + Constants.micOpenTimeoutSeconds) { [weak self] in
			guard let self, self.generation == opening, self.isRunning, !self.isOpen else { return }
			self.fail(error: CaptureError.notResponding)
		}
	}

	private func close() {
		generation += 1
		isOpen = false
		level = 0
		control.async { self.closeDevice() }
	}

	private func fail(error: Error) {
		isRunning = false
		close()
		onError?(error)
	}

	/// Follows the default input (headphones plugged in, AirPods connecting): the mic reopens on the new one.
	private func watchDefaultInput() {
		guard defaultInputListener == nil else { return }
		let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultInputChanged() }
		var address = Self.defaultInputAddress
		let status = AudioObjectAddPropertyListenerBlock(
			AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
		if status == noErr { defaultInputListener = listener }
	}

	private func defaultInputChanged() {
		guard isRunning else { return }
		Log.info(message: "audio: input device changed, reopening")
		close()
		let reopening = generation
		DispatchQueue.main.asyncAfter(deadline: .now() + Constants.micReopenDelaySeconds) { [weak self] in
			guard let self, self.isRunning, self.generation == reopening else { return }
			if Self.hasInputDevice { self.open() } else { self.fail(error: CaptureError.noInputDevice) }
		}
	}

	// MARK: The device (on `control`)

	private func openDevice(generation opening: Int) {
		closeDevice()  // never two queues at once
		let result: Result<String, Error>
		do {
			queue = try makeQueue()
			let device = Self.defaultInput().flatMap { Self.string(property: kAudioObjectPropertyName, of: $0.id) }
			result = .success(device ?? "the default input")
		} catch {
			result = .failure(error)
		}
		DispatchQueue.main.async {
			// Closed meanwhile: that close is next on `control`.
			guard self.generation == opening else { return }
			switch result {
			case .success(let device):
				self.isOpen = true
				Log.info(message: "audio: capturing from \(device)")
			case .failure(let error):
				self.fail(error: error)
			}
		}
	}

	private func closeDevice() {
		guard let closing = queue else { return }
		queue = nil
		lock.withLock {
			liveQueue = nil
			level = 0
		}
		AudioQueueDispose(closing, true)
	}

	/// An input queue on the default input, recording 16 kHz mono s16le.
	private func makeQueue() throws -> AudioQueueRef {
		var format = AudioStreamBasicDescription(
			mSampleRate: Constants.micSampleRate, mFormatID: kAudioFormatLinearPCM,
			mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2,
			mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
		var created: AudioQueueRef?
		let status = AudioQueueNewInputWithDispatchQueue(&created, &format, 0, delivery) {
			[weak self] source, buffer, _, _, _ in
			self?.deliver(buffer: buffer, from: source)
		}
		try Self.check(call: "AudioQueueNewInput", status: status)
		guard let created else { throw CaptureError.coreAudio(call: "AudioQueueNewInput", status: status) }
		do {
			recordFirstChannel(queue: created)
			let bytes = UInt32(Double(Constants.micBytesPerSecond) * Constants.micChunkSeconds) & ~1
			for _ in 0..<Constants.micChunkCount {
				var buffer: AudioQueueBufferRef?
				try Self.check(
					call: "AudioQueueAllocateBuffer", status: AudioQueueAllocateBuffer(created, bytes, &buffer))
				guard let buffer else { continue }
				try Self.check(
					call: "AudioQueueEnqueueBuffer", status: AudioQueueEnqueueBuffer(created, buffer, 0, nil))
			}
			lock.withLock { liveQueue = created }
			try Self.check(call: "AudioQueueStart", status: AudioQueueStart(created, nil))
		} catch {
			lock.withLock { liveQueue = nil }
			AudioQueueDispose(created, true)
			throw error
		}
		return created
	}

	/// Multi-channel interfaces: record their first input, not a mix of every input.
	private func recordFirstChannel(queue: AudioQueueRef) {
		guard let input = Self.defaultInput(), input.channelCount > 1,
			let uid = Self.string(property: kAudioDevicePropertyDeviceUID, of: input.id)
		else { return }
		let deviceUID = uid as CFString
		withExtendedLifetime(deviceUID) {
			var assignment = AudioQueueChannelAssignment(
				mDeviceUID: Unmanaged.passUnretained(deviceUID), mChannelNumber: 1)
			let status = AudioQueueSetProperty(
				queue, kAudioQueueProperty_ChannelAssignments, &assignment,
				UInt32(MemoryLayout<AudioQueueChannelAssignment>.size))
			// Not fatal: a mix of the inputs still carries the voice.
			if status != noErr {
				Log.info(message: "audio: couldn't pick input 1 of \(input.channelCount) (\(status))")
			}
		}
	}

	// MARK: Recorded audio (on `delivery`)

	/// Hands one recorded buffer on and gives it back to the queue.
	private func deliver(buffer: AudioQueueBufferRef, from source: AudioQueueRef) {
		let pcm: Data? = lock.withLock {
			guard source == liveQueue else { return nil }  // being disposed: its buffers are about to be freed
			let data = Data(bytes: buffer.pointee.mAudioData, count: Int(buffer.pointee.mAudioDataByteSize))
			AudioQueueEnqueueBuffer(source, buffer, 0, nil)
			level = PCM.level(int16Data: data, gain: 12)
			return data
		}
		if let pcm, !pcm.isEmpty { onPCM16k?(pcm) }
	}

	// MARK: Core Audio helpers

	private struct InputDevice {
		let id: AudioObjectID
		let channelCount: Int
	}

	private static var defaultInputAddress: AudioObjectPropertyAddress {
		AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain)
	}

	private static func defaultInput() -> InputDevice? {
		var device = AudioObjectID(kAudioObjectUnknown)
		var size = UInt32(MemoryLayout<AudioObjectID>.size)
		var address = defaultInputAddress
		guard
			AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
				== noErr, device != kAudioObjectUnknown
		else { return nil }
		address.mSelector = kAudioDevicePropertyStreamConfiguration
		address.mScope = kAudioDevicePropertyScopeInput
		guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
			return InputDevice(id: device, channelCount: 0)
		}
		let list = UnsafeMutableRawPointer.allocate(
			byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
		defer { list.deallocate() }
		guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else {
			return InputDevice(id: device, channelCount: 0)
		}
		let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
		return InputDevice(id: device, channelCount: buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
	}

	private static func string(property: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
		var address = AudioObjectPropertyAddress(
			mSelector: property, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
		var value: Unmanaged<CFString>?
		var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
		guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
			return nil
		}
		return value.takeRetainedValue() as String
	}

	private static func check(call: String, status: OSStatus) throws {
		guard status == noErr else { throw CaptureError.coreAudio(call: call, status: status) }
	}
}
