// Local speech: transcription by a command on this PC (e.g. NVIDIA Parakeet through onnx-asr) or by any
// OpenAI-compatible server (speaches, faster-whisper-server, a Parakeet server…), and spoken replies from an
// OpenAI-compatible speech server (e.g. Kokoro-FastAPI). Nothing here leaves the PC unless a server URL says so.

const { exec } = require('node:child_process')
const { unlink, writeFile } = require('node:fs/promises')
const { tmpdir } = require('node:os')
const { join } = require('node:path')

const SAMPLE_RATE = 16000

/** 16 kHz mono 16-bit PCM chunks → a WAV file's bytes. */
function wav(chunks) {
	const data = Buffer.concat(chunks)
	const header = Buffer.alloc(44)
	header.write('RIFF', 0)
	header.writeUInt32LE(36 + data.length, 4)
	header.write('WAVE', 8)
	header.write('fmt ', 12)
	header.writeUInt32LE(16, 16) // fmt chunk size
	header.writeUInt16LE(1, 20) // PCM
	header.writeUInt16LE(1, 22) // mono
	header.writeUInt32LE(SAMPLE_RATE, 24)
	header.writeUInt32LE(SAMPLE_RATE * 2, 28) // byte rate
	header.writeUInt16LE(2, 32) // block align
	header.writeUInt16LE(16, 34) // bits per sample
	header.write('data', 36)
	header.writeUInt32LE(data.length, 40)
	return Buffer.concat([header, data])
}

/** The command line with the WAV's path in place of {file} (or appended, quoted, when there's no {file}). */
function commandFor({ command, file }) {
	return command.includes('{file}') ? command.replaceAll('{file}', file) : `${command} "${file}"`
}

/** The transcript in a command's output: its last non-empty line, since tools often print progress first. */
function transcriptFrom(stdout) {
	return stdout.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).at(-1) ?? ''
}

async function transcribeWithCommand({ command, audio }) {
	const file = join(tmpdir(), `friday-${Date.now()}.wav`)
	await writeFile(file, audio)
	try {
		return await new Promise((resolve, reject) =>
			exec(commandFor({ command, file }), { windowsHide: true, timeout: 120_000, maxBuffer: 4 << 20 }, (e, out, err) =>
				e == null
					? resolve(transcriptFrom(String(out)))
					: reject(new Error(`The transcription command failed: ${String(err).trim().split('\n').at(-1) || e.message}`)),
			),
		)
	} finally {
		await unlink(file).catch(() => {})
	}
}

const base = (url) => url.trim().replace(/\/+$/, '')
const auth = (key) => (key ? { Authorization: `Bearer ${key}` } : {})

async function failure({ res, what }) {
	const body = await res.text().catch(() => '')
	return new Error(`${what} answered HTTP ${res.status}${body ? `: ${body.slice(0, 200)}` : ''}`)
}

async function transcribeWithServer({ url, model, key, audio }) {
	const form = new FormData()
	form.append('file', new Blob([audio], { type: 'audio/wav' }), 'speech.wav')
	form.append('model', model)
	form.append('response_format', 'json')
	const res = await fetch(`${base(url)}/audio/transcriptions`, { method: 'POST', headers: auth(key), body: form })
	if (!res.ok) throw await failure({ res, what: 'The speech-to-text server' })
	return String((await res.json()).text ?? '').trim()
}

/** Speech for `text` as MP3 bytes. */
async function speakWithServer({ url, model, voice, key, text }) {
	const res = await fetch(`${base(url)}/audio/speech`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', ...auth(key) },
		body: JSON.stringify({ model, voice, input: text, response_format: 'mp3' }),
	})
	if (!res.ok) throw await failure({ res, what: 'The voice server' })
	return Buffer.from(await res.arrayBuffer())
}

/** Collects the microphone's audio, then transcribes it all at once when listening ends. */
function startLocalSession({ transcribe }) {
	const chunks = []
	return {
		send: (pcm) => chunks.push(pcm),
		flush: () => (chunks.length === 0 ? Promise.resolve('') : transcribe(wav(chunks))),
		cancel: () => (chunks.length = 0),
	}
}

module.exports = { wav, commandFor, transcriptFrom, transcribeWithCommand, transcribeWithServer, speakWithServer, startLocalSession }
