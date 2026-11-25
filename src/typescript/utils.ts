/** Compile-time proof that every case of a union is handled. */
export function exhaustiveGuard(arg: never): never {
	throw new Error(`Unhandled case: ${JSON.stringify(arg)}`)
}

/** Run a command and return its trimmed stdout. */
export async function sh({ cmd }: { cmd: string[] }): Promise<string> {
	const p = Bun.spawn(cmd, { stdout: 'pipe', stderr: 'ignore' })
	const out = await new Response(p.stdout).text()
	await p.exited
	return out.trim()
}
