const test = require('node:test')
const assert = require('node:assert')
const http = require('node:http')
const { sanitize } = require('./config')
const { unwrapCmd } = require('./claude')
const local = require('./local-speech')

test('settings keep only known keys, right types and allowed choices', () => {
	assert.deepStrictEqual(sanitize({ model: 'claude-fable-5-2', effort: 'low', chrome: 'yes', bogus: 1, voiceRate: 9 }), { model: 'claude-fable-5-2' })
	assert.deepStrictEqual(sanitize({ workingDirectory: '  ', claudePath: 'C:\\x\\claude.exe', speechToText: 'command' }), {
		workingDirectory: null,
		claudePath: 'C:\\x\\claude.exe',
		speechToText: 'command',
	})
})

test('npm .cmd wrappers unwrap to the program they run', () => {
	const native = '@ECHO off\r\nGOTO start\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe"   %*\r\n'
	assert.strictEqual(unwrapCmd({ path: '/npm/claude.cmd', text: native }), '/npm/node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe')
	const js = 'IF EXIST "%dp0%\\node.exe" (\r\n  SET "_prog=%dp0%\\node.exe"\r\n) ELSE (SET "_prog=node")\r\n"%_prog%"  "%dp0%\\node_modules\\pkg\\cli.js" %*\r\n'
	assert.match(unwrapCmd({ path: '/npm/claude.cmd', text: js }), /cli\.js$/)
	assert.strictEqual(unwrapCmd({ path: '/x.cmd', text: '@echo hi' }), null)
})

test('WAV header describes 16 kHz mono 16-bit PCM', () => {
	const audio = local.wav([Buffer.alloc(320), Buffer.alloc(320)])
	assert.strictEqual(audio.length, 44 + 640)
	assert.strictEqual(audio.toString('ascii', 0, 4), 'RIFF')
	assert.strictEqual(audio.readUInt32LE(24), 16000)
	assert.strictEqual(audio.readUInt16LE(22), 1)
	assert.strictEqual(audio.readUInt32LE(40), 640)
})

test('commands get the file and their transcript is the last printed line', () => {
	assert.strictEqual(local.commandFor({ command: 'asr "{file}"', file: 'a.wav' }), 'asr "a.wav"')
	assert.strictEqual(local.commandFor({ command: 'asr', file: 'a.wav' }), 'asr "a.wav"')
	assert.strictEqual(local.transcriptFrom('loading model...\n\nopen notepad\n'), 'open notepad')
})

test('a local command transcribes the recording', async () => {
	// Stands in for Parakeet: prints progress, then the WAV's sample rate as the "transcript".
	const command = `node -e "const b=require('fs').readFileSync(process.argv[1]);console.log('loading');console.log('rate '+b.readUInt32LE(24))" "{file}"`
	const session = local.startLocalSession({ transcribe: (audio) => local.transcribeWithCommand({ command, audio }) })
	session.send(Buffer.alloc(3200))
	assert.strictEqual(await session.flush(), 'rate 16000')
	await assert.rejects(local.transcribeWithCommand({ command: 'node -e "process.exit(3)"', audio: local.wav([]) }), /command failed/)
})

test('a local server transcribes and speaks', async () => {
	const server = http.createServer((req, res) => {
		let body = ''
		req.on('data', (d) => (body += d.toString('latin1')))
		req.on('end', () => {
			if (req.url === '/v1/audio/transcriptions') {
				const isOk = body.includes('name="model"') && body.includes('parakeet') && body.includes('RIFF')
				res.writeHead(isOk ? 200 : 400, { 'Content-Type': 'application/json' }).end(JSON.stringify({ text: ' hello there ' }))
			} else if (req.url === '/v1/audio/speech') {
				const { input, voice } = JSON.parse(body)
				res.writeHead(200, { 'Content-Type': 'audio/mpeg' }).end(`mp3:${voice}:${input}`)
			} else res.writeHead(404).end('nope')
		})
	})
	await new Promise((r) => server.listen(0, r))
	const url = `http://127.0.0.1:${server.address().port}/v1/`
	try {
		assert.strictEqual(await local.transcribeWithServer({ url, model: 'parakeet', key: '', audio: local.wav([Buffer.alloc(32)]) }), 'hello there')
		const mp3 = await local.speakWithServer({ url, model: 'kokoro', voice: 'af', key: 'k', text: 'hi' })
		assert.strictEqual(mp3.toString(), 'mp3:af:hi')
		await assert.rejects(local.speakWithServer({ url: url + 'x', model: 'm', voice: 'v', key: '', text: 'hi' }), /HTTP 404/)
	} finally {
		server.close()
	}
})
