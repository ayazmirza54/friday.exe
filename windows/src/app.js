// The Friday window: setup checks, assistant status and settings. Every change saves at once.
const $ = (id) => document.getElementById(id)
const f = window.friday
let config = {}
let toastTimer = null

const MODEL_NAMES = { 'claude-opus-5-5': 'Opus 5.5', 'claude-fable-5-2': 'Fable 5.2' }
const EFFORT_NAMES = { medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' }
const STATE_NAMES = { ready: 'Ready', starting: 'Starting', error: 'Needs attention', stopped: 'Stopped' }
const FIXES = {
	'install-claude': ['Get Claude Code', () => f.open('install-claude')],
	'sign-in': ['Sign in', () => f.signIn()],
	'install-git': ['Get Git', () => f.open('install-git')],
}

function toast(text) {
	$('toast').textContent = text
	$('toast').classList.add('shown')
	clearTimeout(toastTimer)
	toastTimer = setTimeout(() => $('toast').classList.remove('shown'), 1600)
}

const keyLabel = (accelerator) => accelerator.replace('Control', 'Ctrl').replace('Super', 'Win').split('+').join(' + ')

async function save(patch) {
	const r = await f.setConfig(patch)
	config = r.config
	if (r.error != null) {
		toast(r.error)
		return false
	}
	toast('Saved')
	return true
}

// --- Navigation -----------------------------------------------------------------------------------------------

function navigate(page) {
	const id = document.getElementById(page) != null ? page : 'home'
	document.querySelectorAll('section').forEach((s) => s.classList.toggle('shown', s.id === id))
	setTimeout(() => (document.querySelector('main').scrollTop = 0)) // after the browser's jump to the anchor
	document.querySelectorAll('nav a').forEach((a) => (a.getAttribute('href') === `#${id}` ? a.setAttribute('aria-current', 'page') : a.removeAttribute('aria-current')))
}
window.addEventListener('hashchange', () => navigate(location.hash.slice(1)))
f.on('navigate', (page) => (location.hash = page))

// --- Home -----------------------------------------------------------------------------------------------------

function renderChecks(checks) {
	const box = $('checks')
	box.replaceChildren()
	for (const c of checks) {
		const row = document.createElement('div')
		row.className = 'row'
		const mark = document.createElement('span')
		mark.className = `check ${c.ok ? 'ok' : 'bad'}`
		mark.textContent = c.ok ? '✓' : '!'
		mark.setAttribute('aria-label', c.ok ? 'OK' : 'Needs attention')
		const text = document.createElement('div')
		text.className = 'text'
		text.innerHTML = '<div class="title"></div><div class="detail"></div>'
		text.children[0].textContent = c.title
		text.children[1].textContent = c.detail
		row.append(mark, text)
		if (!c.ok && FIXES[c.fix] != null) {
			const b = document.createElement('button')
			b.className = 'primary'
			b.textContent = FIXES[c.fix][0]
			b.onclick = FIXES[c.fix][1]
			row.append(b)
		}
		box.append(row)
	}
	if (checks.length === 0) box.innerHTML = '<div class="row"><span class="check wait">…</span><div class="text detail">Checking…</div></div>'
	$('checkedAt').textContent = checks.length === 0 ? '' : `Checked ${new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`
	renderHero()
}

let checks = []
let brainStatus = { state: 'stopped', detail: '' }

function renderHero() {
	const missing = checks.filter((c) => !c.ok).length
	const isReady = brainStatus.state === 'ready' && missing === 0
	$('heroTitle').textContent = isReady ? 'Friday is ready' : missing > 0 ? `Friday needs ${missing === 1 ? 'one thing' : `${missing} things`}` : 'Getting Friday ready…'
	$('heroSub').textContent = isReady ? `Press ${keyLabel(config.hotkey ?? 'Control+J')} anywhere and say what you need.` : missing > 0 ? 'Fix the items below, then check again.' : brainStatus.detail
}

function renderBrain(status) {
	brainStatus = status
	for (const id of ['brainDot', 'navDot']) $(id).className = `dot ${status.state}`
	$('brainState').textContent = STATE_NAMES[status.state] ?? status.state
	$('brainDetail').textContent = status.state === 'ready' ? `${MODEL_NAMES[config.model] ?? config.model}, ${EFFORT_NAMES[config.effort] ?? config.effort} effort` : status.detail
	$('navStatus').textContent = STATE_NAMES[status.state] ?? status.state
	renderHero()
}

function showProblem(text) {
	$('problem').hidden = false
	$('problem').textContent = text
}

$('talk').onclick = () => f.talk()
$('newConversation').onclick = () => {
	f.newConversation()
	toast('New conversation started')
}
$('recheck').onclick = async () => {
	$('recheck').disabled = true
	renderChecks([])
	checks = await f.checks()
	renderChecks(checks)
	$('recheck').disabled = false
	if (brainStatus.state === 'error' && checks.every((c) => c.ok)) f.restartAssistant()
}
$('restart').onclick = () => {
	$('problem').hidden = true
	f.restartAssistant()
}
$('openLog').onclick = () => f.open('logs')
document.querySelectorAll('[data-open]').forEach((b) =>
	b.addEventListener('click', (e) => {
		e.preventDefault()
		f.open(b.dataset.open)
	}),
)

f.on('checks', (c) => renderChecks((checks = c)))
f.on('brain-status', renderBrain)
f.on('problem', showProblem)
f.on('reply', (event) => {
	$('lastReply').textContent = event.text
	if (event.isError) showProblem(`${event.text} The log has the details.`)
})

// --- General --------------------------------------------------------------------------------------------------

let isRecording = false
$('shortcut').onclick = () => {
	isRecording = true
	$('shortcut').classList.add('recording')
	$('shortcut').textContent = 'Press keys…'
}
$('shortcut').addEventListener('blur', () => {
	isRecording = false
	$('shortcut').classList.remove('recording')
	$('shortcut').textContent = keyLabel(config.hotkey)
})
$('shortcut').addEventListener('keydown', async (e) => {
	if (!isRecording) return
	e.preventDefault()
	if (e.key === 'Escape') return $('shortcut').blur()
	if (['Control', 'Shift', 'Alt', 'Meta'].includes(e.key)) return
	const mods = [e.ctrlKey && 'Control', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Super'].filter(Boolean)
	if (mods.length === 0 && !/^F\d+$/.test(e.key)) return toast('Add Ctrl, Alt or Shift')
	const key = e.code.startsWith('Key') ? e.code.slice(3) : e.code.startsWith('Digit') ? e.code.slice(5) : e.key === ' ' ? 'Space' : e.key
	const isSaved = await save({ hotkey: [...mods, key].join('+') })
	$('shortcutError').hidden = isSaved
	if (!isSaved) $('shortcutError').textContent = 'That shortcut is taken or not allowed. Try another.'
	$('shortcut').blur()
	renderHero()
})
$('openAtLogin').onchange = async (e) => {
	e.target.checked = await f.setOpenAtLogin(e.target.checked)
	toast(e.target.checked ? 'Friday will start with Windows' : 'Friday won’t start with Windows')
}

// --- Assistant ------------------------------------------------------------------------------------------------

function renderAssistant(state) {
	const model = $('model')
	model.replaceChildren()
	for (const id of state.choices.model) {
		const b = document.createElement('button')
		b.textContent = MODEL_NAMES[id] ?? id
		b.setAttribute('aria-pressed', String(config.model === id))
		b.onclick = async () => {
			if (await save({ model: id })) renderAssistant(state)
		}
		model.append(b)
	}
	$('effort').replaceChildren(...state.choices.effort.map((id) => new Option(EFFORT_NAMES[id] ?? id, id, false, config.effort === id)))
	$('chrome').checked = config.chrome
	$('screen').checked = config.screen === 'auto'
	$('workingDirectory').textContent = config.workingDirectory ?? `${state.home}\\workspace (default)`
	const found = state.checks.find((c) => c.id === 'claude')
	$('claudePath').textContent = config.claudePath ?? (found?.ok ? `Found automatically` : 'Not found')
}
$('effort').onchange = (e) => save({ effort: e.target.value })
$('chrome').onchange = (e) => save({ chrome: e.target.checked })
$('screen').onchange = (e) => save({ screen: e.target.checked ? 'auto' : 'off' })
$('pickFolder').onclick = async () => {
	const folder = await f.pickFolder()
	if (folder != null && (await save({ workingDirectory: folder }))) $('workingDirectory').textContent = folder
}
$('resetFolder').onclick = async () => {
	if (await save({ workingDirectory: null })) load()
}
$('pickClaude').onclick = async () => {
	const file = await f.pickFile()
	if (file != null && (await save({ claudePath: file }))) $('claudePath').textContent = file
}
$('autoClaude').onclick = async () => {
	if (await save({ claudePath: null })) load()
}

async function loadInstructions() {
	const r = await f.instructions()
	$('instructions').value = r.text
	$('instructionsState').textContent = r.isCustom ? 'Your instructions' : 'Built-in instructions'
}
$('saveInstructions').onclick = async () => {
	const r = await f.setInstructions($('instructions').value)
	$('instructionsState').textContent = r.isCustom ? 'Your instructions' : 'Built-in instructions'
	toast('Instructions saved')
}
$('restoreInstructions').onclick = async () => {
	await f.setInstructions('')
	await loadInstructions()
	toast('Restored the built-in instructions')
}

// --- Voice ------------------------------------------------------------------------------------------------------

const TEXT_SETTINGS = ['sttCommand', 'sttServerUrl', 'sttServerModel', 'sttServerKey', 'ttsServerUrl', 'ttsServerModel', 'ttsServerVoice', 'ttsServerKey']

function renderVoice() {
	for (const name of ['speechToText', 'textToSpeech'])
		document.querySelectorAll(`input[name=${name}]`).forEach((r) => (r.checked = r.value === config[name]))
	for (const id of TEXT_SETTINGS) $(id).value = config[id] ?? ''
	$('voiceRate').value = config.voiceRate
	$('voiceRateLabel').textContent = `${Number(config.voiceRate).toFixed(2)}×`
	renderVoices()
}

function renderVoices() {
	const voices = speechSynthesis.getVoices()
	$('voiceName').replaceChildren(new Option('System default', ''), ...voices.map((v) => new Option(v.name.replace(/^Microsoft /, ''), v.name, false, v.name === config.voice)))
}
speechSynthesis.onvoiceschanged = renderVoices

for (const name of ['speechToText', 'textToSpeech'])
	document.querySelectorAll(`input[name=${name}]`).forEach((r) => (r.onchange = () => save({ [name]: r.value })))
for (const id of TEXT_SETTINGS) $(id).addEventListener('change', (e) => save({ [id]: e.target.value }))
$('voiceName').onchange = (e) => save({ voice: e.target.value || null })
$('voiceRate').oninput = (e) => ($('voiceRateLabel').textContent = `${Number(e.target.value).toFixed(2)}×`)
$('voiceRate').onchange = (e) => save({ voiceRate: Number(e.target.value) })

$('testStt').onclick = async () => {
	const button = $('testStt')
	button.disabled = true
	const chunks = []
	let mic
	try {
		mic = await window.openMic({ onPcm: (pcm) => chunks.push(new Int16Array(pcm)), onLevel: (l) => ($('sttMeter').style.width = `${Math.round(l * 100)}%`) })
	} catch {
		$('sttResult').textContent = 'No microphone. Allow desktop apps to use it in Windows privacy settings.'
		button.disabled = false
		return
	}
	for (let s = 4; s > 0; s--) {
		$('sttResult').textContent = `Listening… say something (${s})`
		await new Promise((r) => setTimeout(r, 1000))
	}
	mic.close()
	$('sttMeter').style.width = '0'
	$('sttResult').textContent = 'Transcribing…'
	const all = new Int16Array(chunks.reduce((n, c) => n + c.length, 0))
	chunks.reduce((at, c) => (all.set(c, at), at + c.length), 0)
	const r = await f.testStt(all.buffer)
	$('sttResult').replaceChildren()
	const b = document.createElement('strong')
	b.textContent = r.error != null ? 'Failed: ' : 'Heard: '
	$('sttResult').append(b, r.error ?? (r.text || '(nothing — try speaking louder)'))
	button.disabled = false
}

$('testTts').onclick = async () => {
	const sample = 'Hi, I’m Friday. Ask me anything, and I’ll take care of it.'
	if (config.textToSpeech === 'off') return ($('ttsResult').textContent = 'Spoken replies are off.')
	if (config.textToSpeech === 'server') {
		$('ttsResult').textContent = 'Asking the voice server…'
		const r = await f.speakServer(sample)
		if (r.error != null) return ($('ttsResult').textContent = `Failed: ${r.error}`)
		new Audio(URL.createObjectURL(new Blob([r.audio], { type: 'audio/mpeg' }))).play()
		$('ttsResult').textContent = 'Playing.'
		return
	}
	speechSynthesis.cancel()
	const u = new SpeechSynthesisUtterance(sample)
	const voice = speechSynthesis.getVoices().find((v) => v.name === config.voice)
	if (voice != null) u.voice = voice
	u.rate = config.voiceRate
	speechSynthesis.speak(u)
	$('ttsResult').textContent = 'Playing.'
}

// --- Start ------------------------------------------------------------------------------------------------------

async function load() {
	const state = await f.state()
	config = state.config
	checks = state.checks
	$('shortcut').textContent = keyLabel(config.hotkey)
	$('heroKey').textContent = keyLabel(config.hotkey)
	$('openAtLogin').checked = state.openAtLogin
	$('homePath').textContent = state.home
	$('version').textContent = state.version
	renderChecks(checks)
	renderBrain(state.brainStatus)
	renderAssistant(state)
	renderVoice()
}

navigate(location.hash.slice(1))
load()
loadInstructions()
