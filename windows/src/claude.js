// Finding the user's Claude Code on Windows and checking it can run.
//
// An npm install puts a `claude.cmd` wrapper on PATH. Windows won't start a .cmd without a shell, and the
// Agent SDK starts Claude Code directly, so the wrapper is unwrapped to the program it calls.

const { execFile } = require('node:child_process')
const { existsSync, readFileSync } = require('node:fs')
const { homedir } = require('node:os')
const { dirname, join, resolve } = require('node:path')

/** The program an npm .cmd wrapper runs (its last "%dp0%\…" target that isn't node.exe), or null. */
function unwrapCmd({ path, text }) {
	const targets = [...text.matchAll(/"%dp0%\\([^"]+)"/g)].map((m) => m[1]).filter((t) => !/(^|\\)node\.exe$/i.test(t))
	return targets.length === 0 ? null : resolve(dirname(path), targets.at(-1))
}

function usable(path) {
	if (path == null || !existsSync(path)) return null
	if (!/\.(cmd|bat)$/i.test(path)) return path
	try {
		const target = unwrapCmd({ path, text: readFileSync(path, 'utf8') })
		return target != null && existsSync(target) ? target : null
	} catch {
		return null
	}
}

function where(name) {
	return new Promise((done) =>
		execFile('where.exe', [name], { windowsHide: true }, (_e, out) => done(String(out ?? '').split(/\r?\n/).filter(Boolean))),
	)
}

/** Claude Code's program, or null: the configured path, then PATH, then where the installers put it. */
async function findClaude({ configured }) {
	if (configured != null) return usable(configured)
	const found = await where('claude')
	const candidates = [
		...found.filter((p) => /\.exe$/i.test(p)),
		...found,
		join(homedir(), '.local', 'bin', 'claude.exe'), // the native installer
		join(process.env.APPDATA ?? '', 'npm', 'claude.cmd'), // npm install -g
	]
	for (const candidate of candidates) {
		const path = usable(candidate)
		if (path != null) return path
	}
	return null
}

function run(file, args) {
	const isJs = /\.[cm]?js$/.test(file)
	return new Promise((done) =>
		execFile(isJs ? 'node' : file, isJs ? [file, ...args] : args, { windowsHide: true, timeout: 30_000 }, (e, out, err) =>
			done({ ok: e == null, out: String(out ?? '').trim(), err: String(err ?? e?.message ?? '').trim() }),
		),
	)
}

/** Claude Code on Windows runs its shell commands in Git Bash. */
async function findGitBash() {
	const configured = process.env.CLAUDE_CODE_GIT_BASH_PATH
	if (configured != null && existsSync(configured)) return configured
	for (const git of await where('git')) {
		const bash = join(dirname(git), '..', 'bin', 'bash.exe') // …\Git\cmd\git.exe → …\Git\bin\bash.exe
		if (existsSync(bash)) return resolve(bash)
	}
	const standard = join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Git', 'bin', 'bash.exe')
	return existsSync(standard) ? standard : null
}

/** The subscription login Claude Code keeps on Windows, without its secrets. */
function readLogin() {
	try {
		const oauth = JSON.parse(readFileSync(join(homedir(), '.claude', '.credentials.json'), 'utf8')).claudeAiOauth
		if (oauth?.accessToken == null && oauth?.refreshToken == null) return null
		return { plan: oauth.subscriptionType ?? null }
	} catch {
		return null
	}
}

/** Each check: {id, title, ok, detail, fix?}. `fix` names something the window can offer. */
async function runChecks({ configured }) {
	const claude = await findClaude({ configured })
	const version = claude == null ? null : await run(claude, ['--version'])
	const login = readLogin()
	const bash = await findGitBash()
	return {
		claudePath: claude,
		checks: [
			claude == null
				? { id: 'claude', title: 'Claude Code', ok: false, detail: 'Not found. Install it, then press Check again.', fix: 'install-claude' }
				: version.ok
					? { id: 'claude', title: 'Claude Code', ok: true, detail: `${version.out.split('\n')[0]} · ${claude}` }
					: { id: 'claude', title: 'Claude Code', ok: false, detail: `Found at ${claude} but it won't start: ${version.err.slice(0, 300)}` },
			login == null
				? { id: 'login', title: 'Signed in to Claude', ok: false, detail: 'Run `claude` in a terminal and sign in with Claude Pro or Max.', fix: 'sign-in' }
				: { id: 'login', title: 'Signed in to Claude', ok: true, detail: login.plan == null ? 'Signed in' : `Claude ${login.plan[0].toUpperCase()}${login.plan.slice(1)}` },
			bash == null
				? { id: 'bash', title: 'Git for Windows', ok: false, detail: 'Claude Code needs Git Bash to run commands. Install Git for Windows.', fix: 'install-git' }
				: { id: 'bash', title: 'Git for Windows', ok: true, detail: bash },
		],
	}
}

module.exports = { unwrapCmd, findClaude, runChecks, readLogin }
