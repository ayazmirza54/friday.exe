// Friday: the Windows app. A tray icon, a voice bar on Ctrl+J, and Bol's brain (src/typescript, compiled to
// friday-brain.exe) doing the work through Claude Code. The brain speaks JSON lines on stdio (protocol.ts).

const { app, BrowserWindow, Menu, Tray, desktopCapturer, globalShortcut, ipcMain, nativeImage, screen, shell, clipboard } =
	require('electron')
const { spawn } = require('node:child_process')
const { existsSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs')
const { homedir } = require('node:os')
const { join } = require('node:path')
const { createInterface } = require('node:readline')
const { makeControl } = require('./control')
const { accessToken, startSession } = require('./speech')

const HOME = join(homedir(), '.friday')
const CONFIG_FILE = join(HOME, 'config.json')
const DEFAULT_CONFIG = {
	hotkey: 'Control+J',
	model: 'claude-opus-5-5', // or claude-fable-5-2
	effort: 'medium', // medium | high | xhigh | max
	chrome: true, // Claude in Chrome tools
	screen: 'auto', // auto | off: screenshots and computer control
	workingDirectory: null, // null: ~/.friday/workspace
	claudePath: null, // null: `claude` on PATH
	voice: null, // a Windows voice name, e.g. "Microsoft Aria Online (Natural) - English (United States)"
}

function loadConfig() {
	mkdirSync(HOME, { recursive: true })
	if (!existsSync(CONFIG_FILE)) writeFileSync(CONFIG_FILE, JSON.stringify(DEFAULT_CONFIG, null, '\t'))
	try {
		return { ...DEFAULT_CONFIG, ...JSON.parse(readFileSync(CONFIG_FILE, 'utf8')) }
	} catch {
		return DEFAULT_CONFIG // a hand-edit broke the JSON: run on defaults rather than not at all
	}
}

if (!app.requestSingleInstanceLock()) app.quit()

let config = loadConfig()
let hud = null
let tray = null
let brain = null
let brainRestarts = 0
let sayCount = 0
let listening = null
const perform = makeControl({ electron: { desktopCapturer, screen, clipboard }, script: join(__dirname, 'control.ps1') })

const toHud = (channel, payload) => hud?.webContents.send(channel, payload)

// --- Brain ---------------------------------------------------------------------------------------------------

function brainCommand() {
	const exe = join(process.resourcesPath ?? '', 'brain', 'friday-brain.exe')
	if (app.isPackaged && existsSync(exe)) return { file: exe, args: [] }
	return { file: 'bun', args: ['run', join(__dirname, '..', '..', 'src', 'typescript', 'index.ts')] } // from source
}

function startBrain() {
	const { file, args } = brainCommand()
	const env = {
		...process.env,
		BOL_NAME: 'Friday',
		BOL_HOME: HOME,
		BOL_MODEL: config.model,
		BOL_EFFORT: config.effort,
		BOL_CHROME: config.chrome ? '1' : '0',
		BOL_SCREEN: config.screen,
		...(config.workingDirectory ? { BOL_CWD: config.workingDirectory } : {}),
		...(config.claudePath ? { BOL_CLAUDE_PATH: config.claudePath } : {}),
	}
	delete env.ANTHROPIC_API_KEY // the SDK must use the subscription login, not a stray API key
	const child = spawn(file, args, { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] })
	brain = child
	createInterface({ input: child.stdout }).on('line', (line) => {
		try {
			onBrainEvent(JSON.parse(line))
		} catch {}
	})
	let stderr = ''
	child.stderr.on('data', (d) => (stderr = (stderr + d).slice(-2000)))
	child.on('error', (e) => toHud('brain', { type: 'result', text: `I couldn't start my brain: ${e.message}`, isError: true }))
	child.on('exit', (code) => {
		if (brain !== child) return
		brain = null
		console.error(`brain exited ${code}: ${stderr}`)
		if (/Claude Code is not installed/.test(stderr)) {
			toHud('brain', { type: 'result', text: 'Claude Code is not installed. Install it and sign in, then restart me.', isError: true })
			return
		}
		if (brainRestarts++ < 5) setTimeout(startBrain, 1000 * brainRestarts)
	})
}

function toBrain(cmd) {
	brain?.stdin.write(JSON.stringify(cmd) + '\n')
}

async function onBrainEvent(event) {
	switch (event.type) {
		case 'ready':
			brainRestarts = 0
			break
		case 'log':
			console.log(`brain: ${event.msg}`)
			break
		case 'control': {
			const result = await perform(event.action).catch((e) => ({ text: e.message, isError: true, images: [] }))
			toBrain({ type: 'controlResult', id: event.id, ...result })
			break
		}
		case 'result':
			if (!hud.isVisible()) showHud({ isFocused: false }) // a task finished in the background
			toHud('brain', event)
			break
		default:
			toHud('brain', event)
	}
}

// --- Voice bar -------------------------------------------------------------------------------------------------

function createHud() {
	hud = new BrowserWindow({
		width: 680,
		height: 168,
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
	hud.webContents.on('did-finish-load', () => toHud('config', { voice: config.voice, hotkey: config.hotkey }))
}

function showHud({ isFocused }) {
	const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
	const [w, h] = hud.getSize()
	hud.setPosition(Math.round(area.x + (area.width - w) / 2), Math.round(area.y + area.height - h - 24))
	if (isFocused) hud.show()
	else hud.showInactive()
}

function onHotkey() {
	if (hud.isVisible() && hud.isFocused()) {
		toHud('hotkey') // already open: Ctrl+J again sends, like Enter
		return
	}
	showHud({ isFocused: true })
	toHud('open')
}

ipcMain.handle('listen', async () => {
	listening?.cancel()
	listening = null
	const token = await accessToken({ claude: config.claudePath ?? 'claude' })
	if (token == null) return { error: 'Sign in to Claude Code first (run `claude` and log in), or type instead.' }
	const session = startSession({
		token,
		onText: (text) => listening === session && toHud('transcript', text),
		onError: (message) => listening === session && toHud('problem', message),
	})
	listening = session
	return { error: null }
})
ipcMain.on('pcm', (_e, pcm) => listening?.send(Buffer.from(pcm)))
ipcMain.handle('finish', async () => {
	const session = listening
	listening = null
	return session == null ? '' : session.flush()
})
ipcMain.on('cancel', () => {
	listening?.cancel()
	listening = null
})
ipcMain.on('say', (_e, text) => toBrain({ type: 'say', text, seq: ++sayCount }))
ipcMain.on('interrupt', () => toBrain({ type: 'interrupt' }))
ipcMain.on('hide', () => hud.hide())

// --- Tray --------------------------------------------------------------------------------------------------------

function trayMenu() {
	return Menu.buildFromTemplate([
		{ label: `Talk to Friday (${config.hotkey})`, click: onHotkey },
		{ label: 'New conversation', click: () => toBrain({ type: 'reset' }) },
		{ type: 'separator' },
		{ label: 'Open memory folder', click: () => shell.openPath(join(HOME, 'memory')) },
		{ label: 'Edit instructions', click: () => openInstructions() },
		{ label: 'Edit settings', click: () => shell.openPath(CONFIG_FILE) },
		{ label: 'Reload settings', click: reloadSettings },
		{
			label: 'Start with Windows',
			type: 'checkbox',
			checked: app.getLoginItemSettings().openAtLogin,
			click: (item) => app.setLoginItemSettings({ openAtLogin: item.checked }),
		},
		{ type: 'separator' },
		{ label: 'Quit Friday', click: () => app.quit() },
	])
}

/** The user's own instructions replace the built-in ones; start them from the default the brain wrote. */
function openInstructions() {
	const file = join(HOME, 'system_prompt.md')
	const fallback = join(HOME, 'default_system_prompt.md')
	if (!existsSync(file)) writeFileSync(file, existsSync(fallback) ? readFileSync(fallback) : '')
	shell.openPath(file)
}

function registerHotkey() {
	globalShortcut.unregisterAll()
	if (!globalShortcut.register(config.hotkey, onHotkey))
		tray?.displayBalloon({ title: 'Friday', content: `${config.hotkey} is taken by another app. Change "hotkey" in settings.` })
}

function reloadSettings() {
	config = loadConfig()
	registerHotkey()
	tray.setContextMenu(trayMenu())
	toHud('config', { voice: config.voice, hotkey: config.hotkey })
	const old = brain
	brain = null
	old?.kill()
	brainRestarts = 0
	startBrain()
}

app.whenReady().then(() => {
	createHud()
	tray = new Tray(nativeImage.createFromPath(join(__dirname, '..', 'assets', 'icon.png')).resize({ width: 16, height: 16 }))
	tray.setToolTip('Friday')
	tray.setContextMenu(trayMenu())
	tray.on('click', onHotkey)
	registerHotkey()
	startBrain()
})
app.on('second-instance', onHotkey)
app.on('window-all-closed', (e) => e.preventDefault()) // lives in the tray
app.on('will-quit', () => {
	globalShortcut.unregisterAll()
	brain?.stdin.end() // the brain closes its sessions at end of input
})
