// The hero voice bar plays a few scripted requests in a loop, the way the app's HUD moves through
// listening → working → speaking. Everything else on the page is static.

const scenes = [
	{
		ask: "what's on my calendar tomorrow?",
		steps: [{ icon: 'terminal', text: 'Reading Calendar' }],
		reply: "You've got three things tomorrow: standup at 10, lunch with Priya at 1, and the design review at 4. Want me to block focus time in the morning?",
	},
	{
		ask: 'why is my build failing?',
		isLooking: true,
		steps: [
			{ icon: 'eye', text: 'Reading the error in Xcode' },
			{ icon: 'terminal', text: 'Ran swift build' },
		],
		reply: 'Settings.swift uses a type that was renamed this morning. I updated the two references and the build passes now.',
	},
	{
		ask: 'find the Stripe invoice I downloaded last week and reply to Sam with it',
		steps: [
			{ icon: 'terminal', text: 'Searched Downloads for “invoice”' },
			{ icon: 'terminal', text: 'Opened Mail' },
			{ icon: 'terminal', text: 'Attached invoice-0412.pdf' },
		],
		reply: 'The reply to Sam is in your drafts with the October invoice attached. Shall I send it?',
	},
	{
		ask: 'turn on do not disturb until 3',
		steps: [{ icon: 'terminal', text: 'Turning on Do Not Disturb' }],
		reply: 'Done. Do Not Disturb is on until 3.',
	},
]

const icons = {
	terminal:
		'<rect x="1.5" y="2.5" width="13" height="11" rx="2" fill="none" stroke="currentColor"/><path d="M4.5 6.5 6.5 8l-2 1.5M8 10h3" fill="none" stroke="currentColor"/>',
	eye: '<path d="M1.5 8s2.4-4.5 6.5-4.5S14.5 8 14.5 8 12.1 12.5 8 12.5 1.5 8 1.5 8Z" fill="none" stroke="currentColor"/><circle cx="8" cy="8" r="2" fill="none" stroke="currentColor"/>',
}

const $ = (id) => document.getElementById(id)
const hud = $('hud')
const els = {
	status: $('hud-status'),
	timer: $('hud-timer'),
	escLabel: $('hud-esc-label'),
	context: $('hud-context'),
	text: $('hud-text'),
	activity: $('hud-activity'),
	activityText: $('hud-activity-text'),
	steps: $('hud-steps'),
	hint: document.querySelector('.stage-hint'),
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

let timerHandle = null

// Bol perches on the right end of the bar; the CSS animates it per phase. Click it and it talks back.
const mascot = $('mascot')
const mascotSay = $('mascot-say')
const mascotLines = ['bol!', 'namaste!', 'press ⌘J', 'squawk', 'I heard that', 'on it']
let hopHandle = null
let sayHandle = null

function hopMascot() {
	mascot.classList.remove('is-hopping')
	void mascot.offsetWidth // restart the animation
	mascot.classList.add('is-hopping')
	clearTimeout(hopHandle)
	hopHandle = setTimeout(() => mascot.classList.remove('is-hopping'), 900) // two 0.45s hops
}

mascot.addEventListener('click', () => {
	hopMascot()
	mascotSay.textContent = mascotLines[Math.floor(Math.random() * mascotLines.length)]
	mascotSay.classList.add('is-shown')
	clearTimeout(sayHandle)
	sayHandle = setTimeout(() => mascotSay.classList.remove('is-shown'), 1600)
})

function startTimer() {
	const startedAt = Date.now()
	els.timer.textContent = '0s'
	timerHandle = setInterval(() => {
		els.timer.textContent = `${Math.floor((Date.now() - startedAt) / 1000)}s`
	}, 250)
}

function stopTimer() {
	clearInterval(timerHandle)
	els.timer.textContent = ''
}

function setActivity({ step, count }) {
	if (step == null) {
		els.activity.hidden = true
		return
	}
	els.activity.hidden = false
	els.activity.querySelector('svg').innerHTML = icons[step.icon]
	els.activityText.textContent = step.text
	els.steps.textContent = `· ${count} ${count === 1 ? 'step' : 'steps'}`
}

async function typeWords({ el, text, wordMs, isQuoted }) {
	const words = text.split(' ')
	for (let i = 1; i <= words.length; i++) {
		const shown = escapeHtml(words.slice(0, i).join(' '))
		el.innerHTML = isQuoted ? `“${shown}<span class="caret"></span>”` : `${shown}<span class="caret"></span>`
		await sleep(wordMs + Math.random() * wordMs * 0.6)
	}
	el.innerHTML = isQuoted ? `“${escapeHtml(text)}”` : escapeHtml(text)
}

async function play(scene) {
	// ⌘J
	els.hint.classList.add('is-pressed')
	await sleep(180)
	els.hint.classList.remove('is-pressed')

	hud.dataset.phase = 'listening'
	els.status.textContent = 'Listening'
	els.escLabel.textContent = 'cancel'
	els.context.textContent = ''
	els.text.innerHTML = '<span class="pending">Say something…</span>'
	setActivity({ step: null })
	hud.classList.remove('is-hidden')
	await sleep(900)
	await typeWords({ el: els.text, text: scene.ask, wordMs: 170, isQuoted: false })
	await sleep(700)

	hud.dataset.phase = scene.isLooking === true ? 'looking' : 'thinking'
	els.status.textContent = scene.isLooking === true ? 'Looking at your screen' : 'Working'
	els.escLabel.textContent = 'stop'
	els.text.textContent = `“${scene.ask}”`
	startTimer()
	for (let i = 0; i < scene.steps.length; i++) {
		setActivity({ step: scene.steps[i], count: i + 1 })
		await sleep(1300)
	}
	stopTimer()

	hud.dataset.phase = 'speaking'
	els.status.textContent = 'Bol'
	els.context.textContent = `“${scene.ask}”`
	setActivity({ step: null })
	hopMascot() // the answer is in
	await typeWords({ el: els.text, text: scene.reply, wordMs: 75, isQuoted: false })
	await sleep(3200)

	hud.classList.add('is-hidden')
	await sleep(700)
}

async function loop() {
	await sleep(2400)
	for (let i = 0; ; i = (i + 1) % scenes.length) {
		await play(scenes[i])
	}
}

// Dictation card: text appears as if spoken, then starts over.
const dictateEl = $('dictate-text')
const dictation = "Hey Sam, the invoice is attached. Let me know if anything looks off and I'll fix it before Friday."

async function dictateLoop() {
	for (;;) {
		dictateEl.textContent = ''
		await sleep(900)
		const words = dictation.split(' ')
		for (let i = 1; i <= words.length; i++) {
			dictateEl.textContent = words.slice(0, i).join(' ')
			await sleep(140 + Math.random() * 120)
		}
		await sleep(3500)
	}
}

const isReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
if (isReducedMotion) {
	dictateEl.textContent = dictation
} else {
	loop()
	dictateLoop()
}

// Copy buttons
for (const button of document.querySelectorAll('[data-copy]')) {
	button.addEventListener('click', async () => {
		const text = $(button.dataset.copy).textContent
		try {
			await navigator.clipboard.writeText(text)
			button.textContent = 'Copied'
		} catch {
			button.textContent = 'Press ⌘C'
		}
		setTimeout(() => {
			button.textContent = 'Copy'
		}, 1600)
	})
}
