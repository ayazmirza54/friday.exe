// Performs the brain's computer-control actions (see src/typescript/control.ts) on Windows:
// screenshots with Electron, pointer and keyboard through control.ps1 (SendInput), clipboard with Electron.

const { execFile, spawn } = require('node:child_process')
const { writeFileSync } = require('node:fs')
const { tmpdir } = require('node:os')
const { join } = require('node:path')

/** Long side of screenshots sent to Claude: readable, but cheap. */
const MAX_SHOT = 1456

const VK = {
	backspace: 0x08, tab: 0x09, return: 0x0d, enter: 0x0d, shift: 0x10, ctrl: 0x11, control: 0x11,
	alt: 0x12, option: 0x12, pause: 0x13, capslock: 0x14, escape: 0x1b, esc: 0x1b, space: 0x20,
	pageup: 0x21, page_up: 0x21, pagedown: 0x22, page_down: 0x22, end: 0x23, home: 0x24,
	left: 0x25, up: 0x26, right: 0x27, down: 0x28, printscreen: 0x2c, insert: 0x2d, delete: 0x2e,
	win: 0x5b, windows: 0x5b, super: 0x5b, meta: 0x5b,
	// Mac habits: cmd shortcuts (cmd+c, cmd+s…) are ctrl on Windows.
	cmd: 0x11, command: 0x11,
	';': 0xba, semicolon: 0xba, '=': 0xbb, equal: 0xbb, plus: 0xbb, ',': 0xbc, comma: 0xbc,
	'-': 0xbd, minus: 0xbd, '.': 0xbe, period: 0xbe, '/': 0xbf, slash: 0xbf, '`': 0xc0, backquote: 0xc0,
	'[': 0xdb, bracketleft: 0xdb, '\\': 0xdc, backslash: 0xdc, ']': 0xdd, bracketright: 0xdd, "'": 0xde, quote: 0xde,
}

function vkOf(name) {
	const key = name.trim().toLowerCase()
	if (VK[key] != null) return VK[key]
	if (/^[a-z0-9]$/.test(key)) return key.toUpperCase().charCodeAt(0)
	const f = /^f([1-9]|1[0-9]|2[0-4])$/.exec(key)
	if (f != null) return 0x6f + Number(f[1])
	throw new Error(`Unknown key "${name}"`)
}

/** "ctrl+shift+tab" → press ctrl, shift, tab, release in reverse. */
function keyOps({ text, holdMs = 0 }) {
	const vks = text.split('+').filter((k) => k !== '').map(vkOf)
	const sleep = holdMs > 0 ? [{ t: 'sleep', ms: holdMs }] : []
	return [...vks.map((k) => ({ t: 'vk', k, down: true })), ...sleep, ...vks.reverse().map((k) => ({ t: 'vk', k, down: false }))]
}

function typeOps({ text }) {
	const ops = []
	for (const ch of text.replace(/\r\n/g, '\n')) {
		if (ch === '\n') ops.push(...keyOps({ text: 'return' }))
		else for (let i = 0; i < ch.length; i++) ops.push({ t: 'char', c: ch.charCodeAt(i) })
	}
	return ops
}

function clickOps({ point, button = 'left', count = 1, modifiers }) {
	const mods = modifiers == null || modifiers === '' ? [] : modifiers.split('+').map(vkOf)
	const ops = [{ t: 'move', ...point }, ...mods.map((k) => ({ t: 'vk', k, down: true }))]
	for (let i = 0; i < count; i++) ops.push({ t: 'btn', b: button, down: true }, { t: 'btn', b: button, down: false })
	return [...ops, ...mods.reverse().map((k) => ({ t: 'vk', k, down: false }))]
}

/**
 * The input ops for one pointer/keyboard action, or null when it isn't one. `toScreen` maps
 * [x, y] in screenshot pixels to physical screen pixels.
 */
function actionToOps({ action, toScreen }) {
	const at = () => {
		if (action.coordinate == null) throw new Error('coordinate is required')
		return toScreen(action.coordinate)
	}
	switch (action.name) {
		case 'left_click': return clickOps({ point: at(), modifiers: action.text })
		case 'right_click': return clickOps({ point: at(), button: 'right', modifiers: action.text })
		case 'middle_click': return clickOps({ point: at(), button: 'middle', modifiers: action.text })
		case 'double_click': return clickOps({ point: at(), count: 2, modifiers: action.text })
		case 'triple_click': return clickOps({ point: at(), count: 3, modifiers: action.text })
		case 'mouse_move': return [{ t: 'move', ...at() }]
		case 'left_mouse_down': return [{ t: 'btn', b: 'left', down: true }]
		case 'left_mouse_up': return [{ t: 'btn', b: 'left', down: false }]
		case 'left_click_drag': {
			const start = action.startCoordinate == null ? [] : [{ t: 'move', ...toScreen(action.startCoordinate) }]
			return [...start, { t: 'btn', b: 'left', down: true }, { t: 'sleep', ms: 80 }, { t: 'move', ...at() },
				{ t: 'sleep', ms: 80 }, { t: 'btn', b: 'left', down: false }]
		}
		case 'scroll': {
			const dir = action.scrollDirection ?? 'down'
			const notches = Math.max(1, Math.min(50, action.scrollAmount ?? 3))
			const isHorizontal = dir === 'left' || dir === 'right'
			const sign = dir === 'up' || dir === 'right' ? 1 : -1
			return [{ t: 'move', ...at() }, { t: 'wheel', d: sign * 120 * notches, h: isHorizontal }]
		}
		case 'type': return typeOps({ text: action.text ?? '' })
		case 'key': {
			const ops = keyOps({ text: action.text ?? '' })
			return Array.from({ length: Math.max(1, Math.min(100, action.repeat ?? 1)) }, () => ops).flat()
		}
		case 'hold_key': return keyOps({ text: action.text ?? '', holdMs: Math.min(30, action.duration ?? 1) * 1000 })
		case 'cursor_position': return [{ t: 'pos' }]
		default: return null
	}
}

function runPowerShell({ script, stdin }) {
	return new Promise((resolve, reject) => {
		const p = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script], {
			windowsHide: true,
		})
		let out = ''
		let err = ''
		p.stdout.on('data', (d) => (out += d))
		p.stderr.on('data', (d) => (err += d))
		p.on('error', reject)
		p.on('close', (code) => (code === 0 ? resolve(out.trim()) : reject(new Error(err.trim() || `exit ${code}`))))
		p.stdin.end(stdin)
	})
}

/** Opens an app by name: anything Start-Process knows (notepad, chrome, a path), else a Start menu match. */
function openApplication({ app }) {
	const script = `$a = [Console]::In.ReadToEnd().Trim()
try { Start-Process $a -ErrorAction Stop; exit 0 } catch {}
$m = Get-StartApps | Where-Object { $_.Name -like "*$a*" } | Select-Object -First 1
if ($m -eq $null) { Write-Error "No app named $a"; exit 1 }
Start-Process "shell:AppsFolder\\$($m.AppID)"`
	return new Promise((resolve, reject) => {
		const p = execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true },
			(e, _out, stderr) => (e == null ? resolve() : reject(new Error(String(stderr).trim() || e.message))))
		p.stdin.end(app)
	})
}

/** Screenshots, the mapping back to screen pixels, and the action dispatcher. Electron modules are passed in. */
function makeControl({ electron, script }) {
	const { desktopCapturer, screen, clipboard } = electron
	/** The latest full-resolution capture and its screenshot → screen scale, for clicks and zoom. */
	let last = null

	const toScreen = ([x, y]) => {
		const scale = last?.scale ?? screen.getPrimaryDisplay().scaleFactor
		const origin = last?.origin ?? { x: 0, y: 0 }
		return { x: Math.round(origin.x + x * scale), y: Math.round(origin.y + y * scale) }
	}

	const saveJpeg = (image) => {
		const file = join(tmpdir(), `friday-shot-${Date.now()}-${Math.random().toString(36).slice(2)}.jpg`)
		writeFileSync(file, image.toJPEG(80))
		return file
	}

	// shortcut: primary display only; capture the display under the foreground window when multi-monitor matters.
	async function screenshot() {
		const display = screen.getPrimaryDisplay()
		const physical = { width: Math.round(display.size.width * display.scaleFactor), height: Math.round(display.size.height * display.scaleFactor) }
		const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: physical })
		const source = sources.find((s) => s.display_id === String(display.id)) ?? sources[0]
		if (source == null || source.thumbnail.isEmpty()) throw new Error('Could not capture the screen.')
		const full = source.thumbnail
		const size = full.getSize()
		const ratio = Math.min(1, MAX_SHOT / Math.max(size.width, size.height))
		const shot = ratio < 1 ? full.resize({ width: Math.round(size.width * ratio), quality: 'good' }) : full
		const origin = { x: Math.round(display.bounds.x * display.scaleFactor), y: Math.round(display.bounds.y * display.scaleFactor) }
		last = { full, scale: 1 / ratio, origin }
		const s = shot.getSize()
		return { text: `Screenshot of the primary display, ${s.width}x${s.height}.`, images: [saveJpeg(shot)] }
	}

	function zoom({ region }) {
		if (last == null) throw new Error('Take a screenshot first.')
		const [x0, y0, x1, y1] = region.map((v) => Math.round(v * last.scale))
		const crop = last.full.crop({ x: x0, y: y0, width: Math.max(1, x1 - x0), height: Math.max(1, y1 - y0) })
		const c = crop.getSize()
		const ratio = Math.min(1, MAX_SHOT / Math.max(c.width, c.height))
		const image = ratio < 1 ? crop.resize({ width: Math.round(c.width * ratio) }) : crop
		return { text: 'Zoomed region.', images: [saveJpeg(image)] }
	}

	async function one(action) {
		switch (action.name) {
			case 'screenshot': return screenshot()
			case 'zoom': return zoom({ region: action.region })
			case 'read_clipboard': return { text: clipboard.readText(), images: [] }
			case 'write_clipboard': clipboard.writeText(action.text ?? ''); return { text: 'Copied.', images: [] }
			case 'open_application': await openApplication({ app: action.app ?? '' }); return { text: `Opened ${action.app}.`, images: [] }
			case 'wait': await new Promise((r) => setTimeout(r, Math.min(30, action.duration ?? 1) * 1000)); return { text: 'Waited.', images: [] }
			case 'switch_display': return { text: 'Friday captures the primary display only.', images: [] }
		}
		const ops = actionToOps({ action, toScreen })
		if (ops == null) throw new Error(`Unknown action ${action.name}`)
		const out = await runPowerShell({ script, stdin: JSON.stringify(ops) })
		if (action.name === 'cursor_position') {
			const [px, py] = out.split(',').map(Number)
			const scale = last?.scale ?? 1
			return { text: `[${Math.round(px / scale)}, ${Math.round(py / scale)}]`, images: [] }
		}
		return { text: 'Done.', images: [] }
	}

	/** Runs one action (or a computer_batch, stopping at the first failure) → {text, isError, images}. */
	return async function perform(action) {
		const steps = action.name === 'computer_batch' ? action.actions ?? [] : [action]
		const texts = []
		const images = []
		for (const [i, step] of steps.entries()) {
			try {
				const r = await one(step)
				texts.push(r.text)
				images.push(...r.images)
			} catch (e) {
				texts.push(`${steps.length > 1 ? `Step ${i + 1} (${step.name}) failed: ` : ''}${e.message}`)
				return { text: texts.join('\n'), isError: true, images }
			}
		}
		return { text: texts.join('\n'), isError: false, images }
	}
}

module.exports = { actionToOps, keyOps, typeOps, vkOf, makeControl }
