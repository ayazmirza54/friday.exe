This is Bol's brain: a Bun program compiled to one executable (`bun build --compile`, see `build.sh`) that the
Swift app runs as a child process and talks to over JSON lines on stdin/stdout (`protocol.ts`).

- Use Bun, not Node tooling: `bun install`, `bun check src/typescript/index.ts` (type check), `bun fmt` (format),
  `bun test`. Prefer `Bun.file` / `Bun.write` and `Bun.$` over `node:fs` and execa.
- Claude runs through `@anthropic-ai/claude-agent-sdk`, driving the user's installed Claude Code (`BOL_CLAUDE_PATH`)
  with their subscription login. Never bundle Claude Code or use an API key.
- Dependencies are pinned to exact versions and must be at least 7 days old (`bunfig.toml`).
- Style: tabs, no semicolons, single quotes, width 120; functions take one object argument; booleans are
  `is…`/`has…`; compare to null with `== null`.
