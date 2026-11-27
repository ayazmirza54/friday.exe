// The voice bar's pixel-spectrum wave (from the "Voice Input Animation" design). `level` 0…1+ drives its height:
// the real mic level while listening, a simulated voice while Friday thinks or speaks.

const SPECTRUM = ['#ff3b3b', '#ff7a1a', '#ffb21a', '#ff4fa3', '#b65cff', '#5b8cff', '#2fd6ff', '#2fffc5']
const ERROR = ['#ff2d55', '#ff5e3a', '#ff9500', '#ff2d55']

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16))
function sampleColor(stops, u) {
	u = Math.min(0.9999, Math.max(0, u))
	const f = u * (stops.length - 1), i = Math.floor(f), t = f - i
	const a = hex(stops[i]), b = hex(stops[i + 1])
	return a.map((v, k) => Math.round(v + (b[k] - v) * t))
}
function hash(x, y, z) {
	let h = x * 374761393 + y * 668265263 + z * 2147483647
	h = (h ^ (h >>> 13)) * 1274126177
	return ((h ^ (h >>> 16)) >>> 0) / 4294967295
}
function noise1(x) {
	const i = Math.floor(x), f = x - i, s = f * f * (3 - 2 * f)
	return hash(i, 7, 3) * (1 - s) + hash(i + 1, 7, 3) * s
}

/** A simulated voice level: syllable bursts with pauses, for when there's no real audio to measure. */
class Voice {
	constructor(rate = 1) {
		Object.assign(this, { v: 0, target: 0, next: 0, rate, pauseUntil: 0 })
	}
	step(t, isActive) {
		if (!isActive) this.target = 0
		else if (t > this.next) {
			if (t > this.pauseUntil && Math.random() < 0.07) {
				this.pauseUntil = t + 0.35 + Math.random() * 0.5
				this.target = 0.05
			} else if (t > this.pauseUntil) this.target = 0.35 + Math.random() * 0.65
			this.next = t + (0.07 + Math.random() * 0.13) / this.rate
		}
		this.v += (this.target - this.v) * (this.target > this.v ? 0.28 : 0.12)
		return this.v
	}
}

class Spectrum {
	constructor(canvas, o) {
		Object.assign(this, { cell: 3.6, gap: 1, rows: 13, center: 0.5, spread: 0.25, drift: 0.1, base: 0.9, heightPx: 110 }, o)
		this.c = canvas
		this.ctx = canvas.getContext('2d')
		this.sparks = []
		this.cur = this.center
		this.resize()
		addEventListener('resize', () => this.resize())
	}
	resize() {
		const dpr = Math.min(2, devicePixelRatio || 1), w = this.c.parentElement.clientWidth
		this.w = w
		this.h = this.heightPx
		this.c.width = w * dpr
		this.c.height = this.h * dpr
		this.c.style.height = this.h + 'px'
		this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
		this.cols = Math.floor(w / this.cell)
		this.smooth = new Float32Array(this.cols)
	}
	draw(t, level, stops) {
		const { ctx, cell, gap, w, h, cols } = this
		const s = cell - gap
		ctx.clearRect(0, 0, w, h)
		const auto = this.center + Math.sin(t * 0.6) * this.drift + (noise1(t * 0.8) - 0.5) * this.drift
		this.cur += (auto - this.cur) * 0.04
		const frame = Math.floor(t * 18)
		for (let c = 0; c < cols; c++) {
			const u = c / cols
			const d = (u - this.cur) / this.spread
			const env = Math.exp(-d * d * 1.6)
			const n = 0.35 + 0.65 * noise1(c * 0.18 + t * 4.2) * (0.6 + 0.4 * noise1(c * 0.05 - t * 1.3 + 50))
			this.smooth[c] += (level * env * n - this.smooth[c]) * 0.35
			const amp = this.smooth[c]
			const rows = amp * this.rows
			const col = sampleColor(stops, ((u + t * 0.015) % 1) * 0.999)
			const x = c * cell, tailEnv = Math.exp(-d * d * 0.35)
			if (hash(c, 0, frame >> 2) < 0.35 * this.base * tailEnv + 0.04) {
				const a = (0.18 + 0.5 * tailEnv) * (0.4 + 0.6 * Math.min(1, level * 2 + 0.3))
				ctx.fillStyle = `rgba(${col[0]},${col[1]},${col[2]},${a})`
				ctx.fillRect(x, h - cell, s, s)
			}
			for (let r = 1; r < rows + 1; r++) {
				const p = r / Math.max(1, rows)
				if (hash(c, r, frame) > 1.05 - p * 0.75) continue
				ctx.fillStyle = `rgba(${col[0]},${col[1]},${col[2]},${Math.max(0, (1 - p * 0.75) * (0.55 + 0.45 * env))})`
				ctx.fillRect(x, h - cell - r * cell, s, s)
			}
			if (amp > 0.45 && Math.random() < (0.004 * amp * 240) / cols) this.sparks.push({ x, y: h - cell - rows * cell, vy: -(12 + Math.random() * 28), life: 1, col })
		}
		this.sparks = this.sparks.filter((p) => p.life > 0 && p.y > 0)
		for (const p of this.sparks) {
			p.y += p.vy / 60
			p.vy *= 0.985
			p.life -= 0.9 / 60
			ctx.fillStyle = `rgba(${p.col[0]},${p.col[1]},${p.col[2]},${p.life * 0.9})`
			ctx.fillRect(Math.round(p.x / cell) * cell, Math.round(p.y / cell) * cell, s, s)
		}
	}
}

/**
 * Runs the wave on `canvas`. `source()` returns {state, micLevel, isSpeaking} each frame.
 * With reduced motion, the wave isn't drawn at all.
 */
window.startSpectrum = ({ canvas, source }) => {
	if (matchMedia('(prefers-reduced-motion: reduce)').matches) return (canvas.hidden = true)
	const spectrum = new Spectrum(canvas, { heightPx: 64, rows: 17, cell: 3.4 })
	const voice = new Voice(1)
	let mic = 0
	const loop = (ms) => {
		const t = ms / 1000
		const { state, micLevel, isSpeaking } = source()
		mic += (micLevel - mic) * 0.5
		const simulated = voice.step(t, isSpeaking || state === 'working')
		const level =
			state === 'listening' ? 0.15 + mic * 1.2
			: isSpeaking ? 0.25 + simulated * 0.9
			: state === 'working' ? 0.1 + simulated * 0.3
			: 0.05
		spectrum.draw(t, level, state === 'error' ? ERROR : SPECTRUM)
		requestAnimationFrame(loop)
	}
	requestAnimationFrame(loop)
}
