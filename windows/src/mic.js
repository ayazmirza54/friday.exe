// The microphone, as 16 kHz mono 16-bit PCM chunks plus a 0…1 level for meters. Used by the voice bar and the
// Friday window's tests.
window.openMic = async ({ onPcm, onLevel }) => {
	const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } })
	const ctx = new AudioContext({ sampleRate: 16000 })
	const source = ctx.createMediaStreamSource(stream)
	// shortcut: ScriptProcessor is deprecated but needs no worklet file; move to an AudioWorklet if Chromium drops it.
	const node = ctx.createScriptProcessor(2048, 1, 1)
	node.onaudioprocess = (e) => {
		const f = e.inputBuffer.getChannelData(0)
		const pcm = new Int16Array(f.length)
		let sum = 0
		for (let i = 0; i < f.length; i++) {
			pcm[i] = Math.max(-1, Math.min(1, f[i])) * 0x7fff
			sum += f[i] * f[i]
		}
		onPcm(pcm.buffer)
		onLevel?.(Math.min(1, Math.sqrt(sum / f.length) * 6))
	}
	source.connect(node)
	node.connect(ctx.destination)
	return {
		close() {
			node.disconnect()
			source.disconnect()
			stream.getTracks().forEach((t) => t.stop())
			ctx.close()
		},
	}
}
