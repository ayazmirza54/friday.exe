// Compiles Bol's brain (../src/typescript) into brain/friday-brain.exe. A Node script rather than a shell
// one-liner so it behaves the same in cmd, PowerShell and bash, and says which step failed.
const { spawnSync } = require('node:child_process')
const { mkdirSync } = require('node:fs')
const { join } = require('node:path')

const root = join(__dirname, '..')
mkdirSync(join(__dirname, 'brain'), { recursive: true }) // gitignored, so missing in a fresh clone

function bun(args) {
	console.log(`> bun ${args.join(' ')}`)
	// shell: true finds bun whether it's bun.exe or an npm-installed bun.cmd.
	const r = spawnSync('bun', args, { cwd: root, stdio: 'inherit', shell: true })
	if (r.error != null || r.status !== 0) {
		console.error(r.error?.code === 'ENOENT' || r.status === 9009 || r.status === 127
			? 'Bun is not installed or not on PATH. Install it from https://bun.sh, then open a new terminal.'
			: `bun ${args[0]} failed (exit ${r.status}).`)
		process.exit(1)
	}
}

bun(['install', '--frozen-lockfile'])
bun(['build', 'src/typescript/index.ts', '--compile', '--minify', '--target=bun-windows-x64',
	'--outfile', join(__dirname, 'brain', 'friday-brain.exe')])
