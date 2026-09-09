const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('stocks', {
  getState: () => ipcRenderer.invoke('get-state'),
  refresh: () => ipcRenderer.invoke('refresh'),
  saveSettings: settings => ipcRenderer.invoke('save-settings', settings),
  open: () => ipcRenderer.send('open-panel'),
  quit: () => ipcRenderer.send('quit'),
  subscribe: callback => { const listener = (_event, state) => callback(state); ipcRenderer.on('state', listener); return () => ipcRenderer.removeListener('state', listener); }
});
