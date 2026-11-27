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

- **Talk:** Ctrl+J, speak (or type), Enter. Esc stops. Replies are spoken.
- **The Friday window** (tray icon): setup checks with one-click fixes (Claude Code, sign-in, Git for Windows),
  the assistant's status and log, and settings: shortcut, start with Windows, model, effort, Claude in Chrome,
  screen control, working folder, Claude Code's path, and Friday's instructions.
- **Local voice:** speech-to-text can run on your PC instead of Claude's service:
  - *Local model:* any command that prints a transcript for a WAV file. For NVIDIA Parakeet:
    `pip install onnx-asr[cpu,hub]`, then the command `onnx-asr nemo-parakeet-tdt-0.6b-v2 "{file}"`.
  - *Local server:* anything with an OpenAI-style `/audio/transcriptions` endpoint.
  - Spoken replies: Windows voices, a local OpenAI-style `/audio/speech` server (e.g. Kokoro), or off.
  - *Voice → Test microphone* records 4 seconds and shows what was heard.
- **Work:** every Claude Code tool, PowerShell, MCP servers (`~/.friday/mcp.json`), Claude in Chrome, and its
  own screenshot/click/type tools. Long jobs run as background tasks.
- **Data:** settings, memory, conversations and the log live in `~/.friday`.

If Friday can't reach Claude, open the Friday window: Home shows which check fails and the log has Claude Code's
own error.

## Develop

Needs Node 22+ and Bun.

```sh
npm install
npm start        # runs the brain from source with bun
npm test         # control-mapping tests
npm run dist     # compiles friday-brain.exe and builds dist/Friday-Setup-<version>.exe
```

```
src/main.js          tray, hotkey, windows, brain process (JSON lines, see ../src/typescript/protocol.ts), log
src/app.*            the Friday window: setup checks, status, settings
src/hud.html         the voice bar: level meter, live transcript, replies, spoken answers
src/config.js        settings (~/.friday/config.json) and their validation
src/claude.js        finding Claude Code (unwrapping npm's claude.cmd), setup checks
src/speech.js        speech-to-text over Claude's voice WebSocket with Claude Code's login
src/local-speech.js  local speech-to-text (command or server) and voice server
src/control.js       screenshots, clicks, keys, typing, clipboard, opening apps (control.ps1 does SendInput)
```

Not ported from the Mac app yet: hold-to-dictate in any app, ducking other apps' audio, the Threads window,
auto-update, multi-monitor screenshots.
