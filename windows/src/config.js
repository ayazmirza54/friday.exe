// Friday's settings: ~/.friday/config.json, edited from the Friday window (or by hand).

const { existsSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs')
const { homedir } = require('node:os')
const { join } = require('node:path')

const HOME = join(homedir(), '.friday')
const CONFIG_FILE = join(HOME, 'config.json')

const DEFAULTS = {
	hotkey: 'Control+J',
	model: 'claude-opus-5-5',
	effort: 'medium',
	chrome: true,
	screen: 'auto',
	workingDirectory: null, // null: ~/.friday/workspace
	claudePath: null, // null: found automatically
	speechToText: 'claude',
	// A command that prints the transcript of {file} (a 16 kHz mono WAV). onnx-asr runs NVIDIA Parakeet on CPU.
	sttCommand: 'onnx-asr nemo-parakeet-tdt-0.6b-v2 "{file}"',
	sttServerUrl: 'http://localhost:8000/v1',
	sttServerModel: 'parakeet-tdt-0.6b-v2',
	sttServerKey: '',
	textToSpeech: 'windows',
	voice: null, // a Windows voice name; null: the system default
	voiceRate: 1,
	ttsServerUrl: 'http://localhost:8880/v1',
	ttsServerModel: 'kokoro',
	ttsServerVoice: 'af_heart',
	ttsServerKey: '',
	hasOnboarded: false,
}

const CHOICES = {
	model: ['claude-opus-5-5', 'claude-fable-5-2'],
	effort: ['medium', 'high', 'xhigh', 'max'],
	screen: ['auto', 'off'],
	speechToText: ['claude', 'command', 'server'],
	textToSpeech: ['windows', 'server', 'off'],
}

/** Settings the brain reads at startup: changing one restarts it. */
const BRAIN_KEYS = ['model', 'effort', 'chrome', 'screen', 'workingDirectory', 'claudePath']

/** Keeps only known keys with the right type (and an allowed value, for choices). Unknown or bad values are dropped. */
function sanitize(patch) {
	const clean = {}
	for (const [key, value] of Object.entries(patch ?? {})) {
		if (!(key in DEFAULTS)) continue
		const fallback = DEFAULTS[key]
		const isNullableString = fallback === null && (value === null || typeof value === 'string')
		if (!isNullableString && typeof value !== typeof fallback) continue
		if (CHOICES[key] != null && !CHOICES[key].includes(value)) continue
		if (key === 'voiceRate' && !(value >= 0.5 && value <= 2)) continue
		clean[key] = typeof value === 'string' ? value.trim() : value
		if (fallback === null && clean[key] === '') clean[key] = null
	}
	return clean
}

function loadConfig() {
	mkdirSync(HOME, { recursive: true })
	if (!existsSync(CONFIG_FILE)) return { ...DEFAULTS }
	try {
		return { ...DEFAULTS, ...sanitize(JSON.parse(readFileSync(CONFIG_FILE, 'utf8'))) }
	} catch {
		return { ...DEFAULTS } // a hand-edit broke the JSON: run on defaults rather than not at all
	}
}

function saveConfig(config) {
	mkdirSync(HOME, { recursive: true })
	writeFileSync(CONFIG_FILE, JSON.stringify(config, null, '\t'))
}

module.exports = { HOME, CONFIG_FILE, DEFAULTS, CHOICES, BRAIN_KEYS, sanitize, loadConfig, saveConfig }
