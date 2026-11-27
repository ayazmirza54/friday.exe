// Friday: the Windows app. A tray icon, a voice bar on Ctrl+J, the Friday window (setup checks and settings),
// and Bol's brain (src/typescript, compiled to friday-brain.exe) doing the work through Claude Code.
// The brain speaks JSON lines on stdio (see src/typescript/protocol.ts).

const electron = require('electron')
const { app, BrowserWindow, Menu, Tray, dialog, globalShortcut, ipcMain, nativeImage, nativeTheme, screen, shell } = electron
const { spawn } = require('node:child_process')
const { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } = require('node:fs')
const { join } = require('node:path')
const { createInterface } = require('node:readline')
const { BRAIN_KEYS, CHOICES, DEFAULTS, HOME, loadConfig, sanitize, saveConfig } = require('./config')
const { runChecks } = require('./claude')
const { makeControl } = require('./control')
const local = require('./local-speech')
const { accessToken, startSession } = require('./speech')

if (!app.requestSingleInstanceLock()) app.quit()

const LOG_DIR = join(HOME, 'logs')
const LOG_FILE = join(LOG_DIR, 'friday.log')
const ICON = join(__dirname, '..', 'assets', 'icon.png')

let config = loadConfig()
let hud = null
let win = null
let tray = null
let brain = null
let brainRestarts = 0
let sayCount = 0
let listening = null
/** What the Friday window shows about the assistant: starting | ready | error | stopped, and why. */
let brainStatus = { state: 'stopped', detail: '' }
let claudePath = null
let checks = []

const perform = makeControl({
	electron,
	// PowerShell can't read inside app.asar, so the build unpacks control.ps1 next to it.
	script: join(__dirname, 'control.ps1').replace('app.asar', 'app.asar.unpacked'),
})

// --- Log ---------------------------------------------------------------------------------------------------------

function log(msg) {
	try {
		mkdirSync(LOG_DIR, { recursive: true })
		if (existsSync(LOG_FILE) && statSync(LOG_FILE).size > 2_000_000) renameSync(LOG_FILE, `${LOG_FILE}.old`)
		appendFileSync(LOG_FILE, `${new Date().toISOString()} ${msg}\n`)
	} catch {}
}

const toHud = (channel, payload) => hud?.webContents.send(channel, payload)
const toWin = (channel, payload) => win?.webContents.send(channel, payload)

function setBrainStatus(state, detail = '') {
	brainStatus = { state, detail }
	toWin('brain-status', brainStatus)
	tray?.setToolTip(state === 'ready' ? 'Friday' : `Friday: ${detail || state}`)
}

// --- Brain -------------------------------------------------------------------------------------------------------

function brainCommand() {
	const exe = join(process.resourcesPath ?? '', 'brain', 'friday-brain.exe')
	if (app.isPackaged && existsSync(exe)) return { file: exe, args: [] }
	return { file: 'bun', args: ['run', join(__dirname, '..', '..', 'src', 'typescript', 'index.ts')] } // from source
}

async function refreshChecks() {
	const result = await runChecks({ configured: config.claudePath })
	claudePath = result.claudePath
	checks = result.checks
	toWin('checks', checks)
	return checks
}

async function startBrain() {
	stopBrain()
	setBrainStatus('starting', 'Starting…')
	await refreshChecks()
	if (claudePath == null) {
		setBrainStatus('error', 'Claude Code was not found. Install it, or set its path in Assistant settings.')
		return
	}
	const { file, args } = brainCommand()
	const env = {
		...process.env,
		BOL_NAME: 'Friday',
		BOL_HOME: HOME,
		BOL_CLAUDE_PATH: claudePath,
		BOL_MODEL: config.model,
		BOL_EFFORT: config.effort,
		BOL_CHROME: config.chrome ? '1' : '0',
		BOL_SCREEN: config.screen,
		...(config.workingDirectory ? { BOL_CWD: config.workingDirectory } : {}),
	}
	delete env.ANTHROPIC_API_KEY // the SDK must use the subscription login, not a stray API key
	log(`brain: starting ${file} with Claude Code at ${claudePath}`)
	const child = spawn(file, args, { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] })
	brain = child
	createInterface({ input: child.stdout }).on('line', (line) => {
		try {
			onBrainEvent(JSON.parse(line))
		} catch {}
	})
	let stderr = ''
	child.stderr.on('data', (d) => {
		stderr = (stderr + d).slice(-4000)
		log(`brain stderr: ${String(d).trim()}`)
	})
	child.on('error', (e) => {
		log(`brain: failed to start: ${e.message}`)
		setBrainStatus('error', `The assistant couldn't start: ${e.message}`)
	})
	child.on('exit', (code) => {
		if (brain !== child) return
		brain = null
		log(`brain: exited ${code}`)
		const reason = stderr.trim().split('\n').at(-1) ?? ''
		if (brainRestarts++ < 3) {
			setBrainStatus('starting', 'Restarting…')
			setTimeout(startBrain, 1500 * brainRestarts)
		} else setBrainStatus('error', `The assistant keeps stopping${reason ? `: ${reason}` : ''}. See the log for details.`)
	})
}

function stopBrain() {
	const old = brain
	brain = null
	old?.stdin.end() // the brain closes its sessions at end of input
	setTimeout(() => old?.kill(), 3000)
}

function toBrain(cmd) {
	if (brain == null) {
		toHud('brain', { type: 'result', text: brainStatus.detail || 'The assistant is not running.', isError: true })
		return
	}
	brain.stdin.write(JSON.stringify(cmd) + '\n')
}

async function onBrainEvent(event) {
	switch (event.type) {
		case 'ready':
			brainRestarts = 0
			log('brain: ready')
			setBrainStatus('ready', 'Ready')
			break
		case 'log':
			log(`brain: ${event.msg}`)
			// Claude Code's own complaints (not signed in, no Git Bash…) are the useful part of a failure.
			if (/^claude: .*(error|not |invalid|failed|login|requires)/i.test(event.msg)) toWin('problem', event.msg.slice(8))
			break
		case 'control': {
			const result = await perform(event.action).catch((e) => ({ text: e.message, isError: true, images: [] }))
			toBrain({ type: 'controlResult', id: event.id, ...result })
			break
		}
		case 'result':
			if (event.isError) log(`reply (error): ${event.text}`)
			if (!hud.isVisible()) showHud({ isFocused: false }) // a task finished in the background
			toHud('brain', event)
			toWin('reply', event)
			break
		default:
			toHud('brain', event)
	}
}

// --- Voice ---------------------------------------------------------------------------------------------------------

/** A listening session for the chosen speech-to-text: {session, isStreaming} or {error}. */
async function startListening({ onText, onError }) {
	if (config.speechToText === 'command') {
		const command = config.sttCommand
		return { isStreaming: false, session: local.startLocalSession({ transcribe: (audio) => local.transcribeWithCommand({ command, audio }) }) }
	}
	if (config.speechToText === 'server') {
		const { sttServerUrl: url, sttServerModel: model, sttServerKey: key } = config
		return { isStreaming: false, session: local.startLocalSession({ transcribe: (audio) => local.transcribeWithServer({ url, model, key, audio }) }) }
	}
	const token = await accessToken({ claude: claudePath ?? 'claude' })
	if (token == null) return { error: 'Sign in to Claude Code first, or pick a local speech model in Friday → Voice. You can also type.' }
	return { isStreaming: true, session: startSession({ token, onText, onError }) }
}

ipcMain.handle('listen', async () => {
	listening?.cancel()
	listening = null
	const started = await startListening({
		onText: (text) => listening === started.session && toHud('transcript', text),
		onError: (message) => listening === started.session && toHud('problem', message),
	})
	if (started.error != null) return { error: started.error }
	listening = started.session
	return { error: null, isStreaming: started.isStreaming }
})
ipcMain.on('pcm', (_e, pcm) => listening?.send(Buffer.from(pcm)))
ipcMain.handle('finish', async () => {
	const session = listening
	listening = null
	if (session == null) return { text: '' }
	try {
		return { text: await session.flush() }
	} catch (e) {
		log(`speech-to-text: ${e.message}`)
		return { text: '', error: e.message }
	}
})
ipcMain.on('cancel', () => {
	listening?.cancel()
	listening = null
})

/** The Friday window's microphone test: the whole recording, through the chosen speech-to-text. */
ipcMain.handle('test-stt', async (_e, pcm) => {
	const started = await startListening({ onText: () => {}, onError: () => {} })
	if (started.error != null) return { error: started.error }
	try {
		const buffer = Buffer.from(pcm)
		for (let i = 0; i < buffer.length; i += 8192) started.session.send(buffer.subarray(i, i + 8192))
		return { text: await started.session.flush() }
	} catch (e) {
		return { error: e.message }
	}
})

ipcMain.handle('speak-server', async (_e, text) => {
	try {
		const { ttsServerUrl: url, ttsServerModel: model, ttsServerVoice: voice, ttsServerKey: key } = config
		return { audio: await local.speakWithServer({ url, model, voice, key, text }) }
	} catch (e) {
		log(`text-to-speech: ${e.message}`)
		return { error: e.message }
	}
})

// --- Voice bar -------------------------------------------------------------------------------------------------

function createHud() {
	hud = new BrowserWindow({
		width: 680,
		height: 172,
		frame: false,
		transparent: true,
		resizable: false,
		alwaysOnTop: true,
		skipTaskbar: true,
		show: false,
		webPreferences: { preload: join(__dirname, 'preload.js') },
	})
	hud.setAlwaysOnTop(true, 'screen-saver')
	hud.loadFile(join(__dirname, 'hud.html'))
	hud.webContents.on('did-finish-load', () => toHud('config', config))
}

function showHud({ isFocused }) {
	const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
	const [w, h] = hud.getSize()
	hud.setPosition(Math.round(area.x + (area.width - w) / 2), Math.round(area.y + area.height - h - 24))
	if (isFocused) hud.show()
	else hud.showInactive()
}

function talk() {
	if (hud.isVisible() && hud.isFocused()) {
		toHud('hotkey') // already open: the hotkey again sends, like Enter
		return
	}
	showHud({ isFocused: true })
	toHud('open')
}

ipcMain.on('say', (_e, text) => toBrain({ type: 'say', text, seq: ++sayCount }))
ipcMain.on('interrupt', () => toBrain({ type: 'interrupt' }))
ipcMain.on('hide', () => hud.hide())

// --- The Friday window ----------------------------------------------------------------------------------------

const titleBar = () =>
	nativeTheme.shouldUseDarkColors ? { color: '#1b1c22', symbolColor: '#e8e8ee', height: 40 } : { color: '#f4f4f7', symbolColor: '#1b1c22', height: 40 }

function openWindow(page) {
	if (win != null) {
		if (win.isMinimized()) win.restore()
		win.show()
		win.focus()
		if (page != null) toWin('navigate', page)
		return
	}
	win = new BrowserWindow({
		width: 980,
		height: 680,
		minWidth: 760,
		minHeight: 520,
		title: 'Friday',
		icon: ICON,
		show: false,
		titleBarStyle: 'hidden',
		titleBarOverlay: titleBar(),
		backgroundColor: nativeTheme.shouldUseDarkColors ? '#1b1c22' : '#f4f4f7',
		webPreferences: { preload: join(__dirname, 'preload.js') },
	})
	win.loadFile(join(__dirname, 'app.html'), page == null ? {} : { hash: page })
	win.once('ready-to-show', () => win.show())
	win.on('closed', () => (win = null))
}

nativeTheme.on('updated', () => win?.setTitleBarOverlay(titleBar()))

function instructionsFiles() {
	return { custom: join(HOME, 'system_prompt.md'), fallback: join(HOME, 'default_system_prompt.md') }
}

ipcMain.handle('state', () => ({
	config,
	defaults: DEFAULTS,
	choices: CHOICES,
	version: app.getVersion(),
	brainStatus,
	checks,
	openAtLogin: app.getLoginItemSettings().openAtLogin,
	home: HOME,
}))

ipcMain.handle('set-config', (_e, patch) => {
	const clean = sanitize(patch)
	if (clean.hotkey != null && clean.hotkey !== config.hotkey) {
		globalShortcut.unregisterAll()
		let isTaken = true
		try {
			isTaken = !globalShortcut.register(clean.hotkey, talk)
		} catch {} // an accelerator Electron can't parse
		if (isTaken) {
			registerHotkey()
			return { error: `${clean.hotkey} can't be used: another app has it, or it isn't a valid shortcut.`, config }
		}
	}
	const previous = config
	config = { ...config, ...clean }
	saveConfig(config)
	toHud('config', config)
	tray?.setContextMenu(trayMenu())
	if (BRAIN_KEYS.some((k) => k in clean && clean[k] !== previous[k])) {
		brainRestarts = 0
		void startBrain()
	}
	return { error: null, config }
})

ipcMain.handle('checks', () => refreshChecks())
ipcMain.handle('restart-assistant', () => {
	brainRestarts = 0
	return startBrain()
})
ipcMain.handle('set-open-at-login', (_e, isOn) => {
	app.setLoginItemSettings({ openAtLogin: Boolean(isOn) })
	return app.getLoginItemSettings().openAtLogin
})
ipcMain.handle('pick-folder', async () => {
	const r = await dialog.showOpenDialog(win, { properties: ['openDirectory'] })
	return r.canceled ? null : r.filePaths[0]
})
ipcMain.handle('pick-file', async () => {
	const r = await dialog.showOpenDialog(win, { properties: ['openFile'], filters: [{ name: 'Programs', extensions: ['exe', 'cmd', 'js'] }] })
	return r.canceled ? null : r.filePaths[0]
})
ipcMain.handle('instructions', () => {
	const { custom, fallback } = instructionsFiles()
	const read = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : '')
	return { text: read(custom).trim() || read(fallback).trim(), isCustom: read(custom).trim() !== '' }
})
ipcMain.handle('set-instructions', (_e, text) => {
	const { custom, fallback } = instructionsFiles()
	const isDefault = existsSync(fallback) && readFileSync(fallback, 'utf8').trim() === String(text).trim()
	writeFileSync(custom, isDefault ? '' : String(text)) // empty: the built-in instructions
	return { isCustom: !isDefault && String(text).trim() !== '' }
})
ipcMain.on('new-conversation', () => toBrain({ type: 'reset' }))
ipcMain.on('talk', talk)
ipcMain.on('open-window', (_e, page) => openWindow(page))
ipcMain.on('open', (_e, what) => {
	const targets = {
		logs: LOG_FILE,
		memory: join(HOME, 'memory'),
		home: HOME,
		'install-claude': 'https://claude.com/claude-code',
		'install-git': 'https://git-scm.com/download/win',
		'mic-privacy': 'ms-settings:privacy-microphone',
		parakeet: 'https://github.com/istupakov/onnx-asr',
	}
	const target = targets[what]
	if (target == null) return
	if (/^(https|ms-settings):/.test(target)) shell.openExternal(target)
	else {
		if (target === LOG_FILE && !existsSync(LOG_FILE)) log('log opened')
		shell.openPath(target)
	}
})
/** Opens a console running Claude Code so the user can sign in. */
ipcMain.on('sign-in', () => {
	const path = claudePath ?? 'claude'
	const isJs = /\.[cm]?js$/.test(path)
	spawn('powershell.exe', ['-NoProfile', '-Command', isJs ? 'Start-Process node -ArgumentList $env:FRIDAY_CLAUDE' : 'Start-Process -FilePath $env:FRIDAY_CLAUDE'], {
		env: { ...process.env, FRIDAY_CLAUDE: isJs ? `"${path}"` : path },
		windowsHide: true,
		detached: true,
	})
})

// --- Tray --------------------------------------------------------------------------------------------------------

function trayMenu() {
	return Menu.buildFromTemplate([
		{ label: `Talk to Friday\t${config.hotkey.replace('Control', 'Ctrl')}`, click: talk },
		{ label: 'Open Friday', click: () => openWindow() },
		{ label: 'New conversation', click: () => toBrain({ type: 'reset' }) },
		{ type: 'separator' },
		{ label: 'Settings', click: () => openWindow('general') },
		{ label: 'Quit Friday', click: () => app.quit() },
	])
}

function registerHotkey() {
	globalShortcut.unregisterAll()
	let isOk = false
	try {
		isOk = globalShortcut.register(config.hotkey, talk)
	} catch {}
	if (!isOk) {
		log(`hotkey ${config.hotkey} unavailable`)
		toWin('problem', `${config.hotkey} is taken by another app. Pick another shortcut in General.`)
	}
	return isOk
}

app.whenReady().then(async () => {
	app.setAppUserModelId('com.friday.exe')
	createHud()
	tray = new Tray(nativeImage.createFromPath(ICON).resize({ width: 16, height: 16 }))
	tray.setToolTip('Friday')
	tray.setContextMenu(trayMenu())
	tray.on('click', () => openWindow())
	const isHotkeyOk = registerHotkey()
	log(`Friday ${app.getVersion()} starting`)
	await startBrain()
	// First run, or something needs fixing: show the window with the setup checks.
	if (!config.hasOnboarded || checks.some((c) => !c.ok) || !isHotkeyOk) {
		openWindow('home')
		if (!config.hasOnboarded) {
			config = { ...config, hasOnboarded: true }
			saveConfig(config)
		}
	}
})
app.on('second-instance', () => openWindow())
app.on('window-all-closed', (e) => e.preventDefault()) // lives in the tray
app.on('will-quit', () => {
	globalShortcut.unregisterAll()
	brain?.stdin.end()
})
