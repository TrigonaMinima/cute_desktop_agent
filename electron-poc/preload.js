const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('cuteAgent', {
  setIgnoreMouseEvents: (ignore) => ipcRenderer.send('set-ignore-mouse-events', ignore),
});
