# Friday (friday.exe)

**Talk to your Windows PC. Claude does the work.** Bol for Windows: press **Ctrl+J**, say what you need, and
Claude Code does it on your PC, then tells you out loud when it's done. Runs on your Claude subscription.

It reuses Bol's brain unchanged in spirit (`../src/typescript`: Claude Agent SDK, threads, tasks, memory, MCP,
Claude in Chrome, computer control), with Windows prompts and tools. This folder is the Windows shell that
replaces the Mac's Swift app: a tray icon, the voice bar, speech in and out, and computer control.

> [!WARNING]
> Like Bol, Friday runs Claude Code with **permission checks off**: it acts on your PC without asking first.
> Deletions go to the Recycle Bin.

## Install

1. Install [Claude Code](https://claude.com/claude-code) for Windows and sign in with Claude Pro or Max (`claude`, then `/login`).
2. Run `Friday-Setup-<version>.exe` (built below). Friday lives in the tray.
3. Press **Ctrl+J** anywhere and talk. **Enter** sends, **Esc** stops. You can also just type in the bar.

Windows 10/11 x64. Allow desktop apps to use the microphone (Settings → Privacy & security → Microphone).

## Use

- **Talk:** Ctrl+J, speak (or type), Enter. Replies are spoken with Windows voices.
- **Work:** every Claude Code tool, PowerShell, MCP servers (`~/.friday/mcp.json`), Claude in Chrome, and its
  own screenshot/click/type tools.
- **Tasks:** long jobs run in the background; Friday speaks up when they're done.
- **Tray menu:** new conversation, memory folder, instructions, settings, start with Windows.
- **Settings:** `~/.friday/config.json` (hotkey, model, effort, Chrome, screen access, working folder, voice),
  then *Reload settings* in the tray.

Listening uses the same Anthropic endpoint as Claude Code's `/voice` (not a public API). If it breaks, type.

## Develop

Needs Node 22+ and Bun.

```sh
npm install
npm start        # runs the brain from source with bun
npm test         # control-mapping tests
npm run dist     # compiles friday-brain.exe and builds dist/Friday-Setup-<version>.exe
```

```
src/main.js      tray, Ctrl+J, voice bar window, brain process (JSON lines, see ../src/typescript/protocol.ts)
src/hud.html     the voice bar: mic capture, live transcript, replies, Windows text-to-speech
src/speech.js    speech-to-text over Claude's voice WebSocket with Claude Code's login
src/control.js   screenshots, clicks, keys, typing, clipboard, opening apps (control.ps1 does SendInput)
```

Not ported from the Mac app yet: hold-to-dictate in any app, ducking other apps' audio, the Threads,
Settings and onboarding windows, OpenAI/Noiz voices, auto-update, multi-monitor screenshots.
