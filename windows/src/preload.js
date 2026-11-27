const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('friday', {
	listen: () => ipcRenderer.invoke('listen'),
	pcm: (buffer) => ipcRenderer.send('pcm', buffer),
	finish: () => ipcRenderer.invoke('finish'),
	cancel: () => ipcRenderer.send('cancel'),
	say: (text) => ipcRenderer.send('say', text),
	interrupt: () => ipcRenderer.send('interrupt'),
	hide: () => ipcRenderer.send('hide'),
	on: (channel, fn) => ipcRenderer.on(channel, (_e, payload) => fn(payload)),
})
