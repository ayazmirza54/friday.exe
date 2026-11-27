const { contextBridge, ipcRenderer } = require('electron')

const invoke = (channel) => (arg) => ipcRenderer.invoke(channel, arg)
const send = (channel) => (arg) => ipcRenderer.send(channel, arg)

contextBridge.exposeInMainWorld('friday', {
	// Voice bar
	listen: invoke('listen'),
	pcm: send('pcm'),
	finish: invoke('finish'),
	cancel: send('cancel'),
	say: send('say'),
	interrupt: send('interrupt'),
	hide: send('hide'),
	speakServer: invoke('speak-server'),
	// The Friday window
	state: invoke('state'),
	setConfig: invoke('set-config'),
	checks: invoke('checks'),
	restartAssistant: invoke('restart-assistant'),
	setOpenAtLogin: invoke('set-open-at-login'),
	pickFolder: invoke('pick-folder'),
	pickFile: invoke('pick-file'),
	instructions: invoke('instructions'),
	setInstructions: invoke('set-instructions'),
	testStt: invoke('test-stt'),
	newConversation: send('new-conversation'),
	talk: send('talk'),
	openWindow: send('open-window'),
	open: send('open'),
	signIn: send('sign-in'),
	on: (channel, fn) => ipcRenderer.on(channel, (_e, payload) => fn(payload)),
})
