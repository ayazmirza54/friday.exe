// Speech-to-text over the WebSocket Claude Code's /voice uses, signed in with the Claude subscription.
// On Windows, Claude Code keeps its login in ~/.claude/.credentials.json (the Mac app reads the Keychain).
// Like Bol, this endpoint isn't a public API: if it breaks, type into the voice bar instead.

const { execFile } = require('node:child_process')
const { readFileSync } = require('node:fs')
const { homedir } = require('node:os')
const { join } = require('node:path')
const WebSocket = require('ws')

const ENDPOINT = 'wss://api.anthropic.com/api/ws/speech_to_text/voice_stream'
const KEYTERMS = ['Friday', 'Claude', 'Claude Code']

function readToken() {
	try {
		const oauth = JSON.parse(readFileSync(join(homedir(), '.claude', '.credentials.json'), 'utf8')).claudeAiOauth
		return { token: oauth?.accessToken ?? null, expiresAt: Number(oauth?.expiresAt ?? 0) }
	} catch {
		return { token: null, expiresAt: 0 }
	}
}

// shell: true so a claude.cmd (npm install) runs too; the file is quoted for paths with spaces.
const run = (file, args) =>
	new Promise((resolve) => execFile(`"${file}"`, args, { timeout: 90_000, windowsHide: true, shell: true }, () => resolve()))

/** A token valid for two more minutes, asking Claude Code to refresh it when needed. Null when signed out. */
async function accessToken({ claude }) {
	const isFresh = ({ token, expiresAt }) => token != null && expiresAt - Date.now() > 120_000
	let creds = readToken()
	if (isFresh(creds)) return creds.token
	await run(claude, ['auth', 'status'])
	creds = readToken()
	if (isFresh(creds)) return creds.token
	await run(claude, ['-p', '"Reply with just: ok"', '--model', 'haiku']) // any real request refreshes the login
	creds = readToken()
	return creds.token != null && creds.expiresAt > Date.now() ? creds.token : null
}

/**
 * One listening session. Feed it 16 kHz mono PCM16 with `send`; `flush` asks for the final text and resolves
 * with the whole transcript. `onText` gets the transcript so far (finals plus the live interim).
 */
function startSession({ token, onText, onError }) {
	const params = new URLSearchParams({
		encoding: 'linear16', sample_rate: '16000', channels: '1',
		endpointing_ms: '300', utterance_end_ms: '1000', use_conversation_engine: 'true',
	})
	const ws = new WebSocket(`${ENDPOINT}?${params}`, {
		headers: {
			Authorization: `Bearer ${token}`,
			'x-app': 'cli',
			'User-Agent': 'claude-cli/friday (external, cli)',
			'x-config-keyterms': KEYTERMS.join(','),
		},
	})
	const finals = []
	let pending = ''
	let isOpen = false
	const queued = []
	let onClosed = null
	const text = () => [...finals, pending].filter((t) => t !== '').join(' ')
	const promote = () => {
		if (pending !== '') finals.push(pending)
		pending = ''
	}
	const keepAlive = setInterval(() => isOpen && ws.send('{"type":"KeepAlive"}'), 8000)

	ws.on('open', () => {
		isOpen = true
		ws.send('{"type":"KeepAlive"}')
		for (const chunk of queued.splice(0)) ws.send(chunk)
	})
	ws.on('message', (data) => {
		let msg
		try {
			msg = JSON.parse(String(data))
		} catch {
			return
		}
		if (msg.type === 'TranscriptText' || msg.type === 'TranscriptInterim') {
			if (msg.data) pending = msg.data
			onText(text())
		} else if (msg.type === 'TranscriptEndpoint') {
			promote()
			onText(text())
		} else if (msg.type === 'TranscriptError' || msg.type === 'error') {
			onError(msg.description ?? msg.message ?? msg.error_code ?? 'transcription error')
		}
	})
	ws.on('unexpected-response', (_req, res) => onError(`speech-to-text was refused (HTTP ${res.statusCode})`))
	ws.on('error', (e) => onError(`speech-to-text failed: ${e.message}`))
	ws.on('close', () => {
		isOpen = false
		clearInterval(keepAlive)
		promote()
		onClosed?.()
	})

	return {
		send(pcm) {
			if (isOpen) ws.send(pcm)
			else if (ws.readyState === WebSocket.CONNECTING) queued.push(pcm) // the first words, before it connects
		},
		flush() {
			return new Promise((resolve) => {
				let isDone = false
				const done = () => {
					if (isDone) return
					isDone = true
					clearTimeout(timer)
					promote()
					resolve(text())
					ws.terminate()
				}
				const timer = setTimeout(done, 2000)
				onClosed = done
				ws.on('message', (d) => String(d).includes('TranscriptEndpoint') && done())
				if (isOpen) ws.send('{"type":"CloseStream"}')
				else done()
			})
		},
		cancel() {
			clearInterval(keepAlive)
			ws.terminate()
		},
	}
}

module.exports = { accessToken, startSession }
