'use strict';
// The only bridge between the window's page and the main process.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('bridge', {
  config: () => ipcRenderer.invoke('config'),
  workspaceLoad: (dir, peek) => ipcRenderer.invoke('workspace-load', dir, peek),
  workspaceSave: (dir, text) => ipcRenderer.invoke('workspace-save', dir, text),
  workspaceQuarantine: (dir) => ipcRenderer.invoke('workspace-quarantine', dir),
  workspaceKeepCopy: (dir, name) => ipcRenderer.send('workspace-keep-copy', dir, name),
  tabs: () => ipcRenderer.invoke('tabs'),
  selectTab: (p) => ipcRenderer.send('tab-select', p),
  closeTab: (p) => ipcRenderer.send('tab-close', p),
  moveTab: (p, offset) => ipcRenderer.send('tab-move', p, offset),
  revealTab: (p) => ipcRenderer.send('tab-reveal', p),
  locateTab: (p) => ipcRenderer.send('tab-locate', p),
  newWorkspace: () => ipcRenderer.send('workspace-new'),
  openWorkspace: () => ipcRenderer.send('workspace-open'),
  importLegacy: () => ipcRenderer.send('workspace-import-legacy'),
  log: (msg) => ipcRenderer.send('log', msg),
  setPref: (key, value) => ipcRenderer.send('set-pref', key, value),
  menuState: (state) => ipcRenderer.send('menu-state', state),
  popup: (items, pos) => ipcRenderer.invoke('popup', items, pos),
  about: () => ipcRenderer.send('about'),
  chooseImport: () => ipcRenderer.invoke('choose-import'),
  backupBeforeImport: (dir) => ipcRenderer.invoke('backup-before-import', dir),
  exportData: (text) => ipcRenderer.invoke('export', text),
  onCommand: (fn) => ipcRenderer.on('command', (_e, command, value) => fn(command, value)),
  onTabsChanged: (fn) => ipcRenderer.on('tabs-changed', (_e, state) => fn(state)),
  onRefreshToday: (fn) => ipcRenderer.on('refresh-today', () => fn()),
  onAppFocus: (fn) => ipcRenderer.on('app-focus', () => fn()),
  onThemeChanged: (fn) => ipcRenderer.on('theme-changed', (_e, dark) => fn(dark)),
  onAppearanceChanged: (fn) => ipcRenderer.on('appearance-changed', (_e, mode, dark) => fn(mode, dark)),
});
