'use strict';
// DaySpindle for Windows: the main process. Owns the window, the menus, the workspace folders and
// the settings.
const { app, BrowserWindow, Menu, ipcMain, dialog, shell, nativeTheme, nativeImage, powerMonitor, screen } = require('electron');
const path = require('path');
const fs = require('fs');

app.setName('DaySpindle');
if (process.platform === 'win32') app.setAppUserModelId('org.dayspindle.DaySpindle');

// ---------------------------------------------------------------- Command line
// --data-dir=<folder>            keep the settings there (used by the self-check)
// --test-workspaces=<a>|<b>      open only these workspace folders as tabs and don't remember them
// --simulated-now=<yyyy-MM-ddTHH:mm:ss>   start the clock at that local time
// --simulated-time-zone=<zone>   pretend this computer is in another time zone
// --selfcheck=<script> --selfcheck-out=<folder>   run the self-check (development builds only)
function arg(name) {
  const prefix = `--${name}=`;
  const hit = process.argv.find((a) => a.startsWith(prefix));
  return hit ? hit.slice(prefix.length) : null;
}
const flag = (name) => process.argv.includes(`--${name}`);

const isWindows = process.platform === 'win32';
/** %APPDATA%\DaySpindle on Windows: settings (and, from version 2.0, the old data file). Elsewhere
 * (development only) a separate folder, so it never touches the Mac app's data. */
const dataDir = path.resolve(arg('data-dir') || path.join(app.getPath('appData'), isWindows ? 'DaySpindle' : 'DaySpindle-Electron'));
const settingsFile = path.join(dataDir, 'settings.json');
const legacyDataFile = path.join(dataDir, 'dayspindle-data.json');
const DATA_NAME = 'dayspindle-data.json';

app.setPath('userData', dataDir);
app.setPath('sessionData', isWindows && process.env.LOCALAPPDATA && !arg('data-dir')
  ? path.join(process.env.LOCALAPPDATA, 'DaySpindle')
  : path.join(dataDir, 'Browser Data'));

const selfcheckScript = !app.isPackaged ? arg('selfcheck') : null;
const testWorkspaces = arg('test-workspaces');

// ---------------------------------------------------------------- Single instance
if (!selfcheckScript && !app.requestSingleInstanceLock()) {
  app.quit();
  process.exit(0);
}
app.on('second-instance', () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
});

// ---------------------------------------------------------------- Settings
const defaultSettings = {
  appearance: 'system', todayColor: '#E5484D', firstWeekday: 0, sidebarWidth: 232, taskListWidth: 300,
  inspectorWidth: 340, inspectorVisible: true, timeZone: null, workspaces: [], activeWorkspace: null,
  bounds: null, maximized: false,
};
let settings = { ...defaultSettings };
function loadSettings() {
  try {
    const raw = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
    if (raw && typeof raw === 'object') settings = { ...defaultSettings, ...raw };
  } catch { /* first launch or unreadable: defaults */ }
  if (!['system', 'light', 'dark'].includes(settings.appearance)) settings.appearance = 'system';
  if (!Array.isArray(settings.workspaces)) settings.workspaces = [];
  settings.workspaces = settings.workspaces.filter((p) => typeof p === 'string' && p);
}
let settingsTimer = null;
function saveSettings(now = false) {
  clearTimeout(settingsTimer);
  const write = () => {
    try {
      fs.mkdirSync(dataDir, { recursive: true });
      fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\n');
    } catch (e) { log(`Could not save settings: ${e.message}`); }
  };
  if (now) write(); else settingsTimer = setTimeout(write, 400);
}

// ---------------------------------------------------------------- Log
const logLines = [];
function log(msg) {
  const line = `${new Date().toISOString()} ${msg}`;
  logLines.push(line);
  if (logLines.length > 2000) logLines.shift();
  if (!app.isPackaged) console.log(line);
}

// ---------------------------------------------------------------- Workspaces
// A workspace is a folder; everything in it is saved in that folder, in dayspindle-data.json.
// The tabs (open workspaces) are remembered in settings.json.
const tabs = { list: [], active: null, remember: true };
const norm = (p) => path.resolve(p);
const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const hasData = (dir) => fs.existsSync(path.join(dir, DATA_NAME));

function initTabs() {
  if (testWorkspaces) {
    tabs.remember = false;
    tabs.list = testWorkspaces.split('|').filter(Boolean).map((p) => { fs.mkdirSync(norm(p), { recursive: true }); return norm(p); });
    tabs.active = tabs.list[0] || null;
    return;
  }
  tabs.list = settings.workspaces.map(norm);
  tabs.active = tabs.list.includes(settings.activeWorkspace) ? settings.activeWorkspace : tabs.list[0] || null;
  // First start: a "Workspace" or "Example Workspace" folder next to DaySpindle (for example, the
  // DaySpindle folder copied from a Mac, or the one that comes with DaySpindle) opens by itself. Only
  // once: after you close its tab, it stays closed.
  if (!tabs.list.length && !settings.nearbyChecked) {
    const found = nearbyWorkspace();
    if (found) { tabs.list.push(found); tabs.active = found; tabs.found = found; log(`Opened the workspace next to DaySpindle: ${found}`); }
  }
  settings.nearbyChecked = true;
  saveTabs();
}

const NEARBY_NAMES = ['Workspace', 'Example Workspace'];
function nearbyWorkspace() {
  const exeDir = app.isPackaged ? path.dirname(process.execPath) : null;
  const starts = [arg('seed-dir'), exeDir].filter(Boolean);
  for (const start of starts) {
    let dir = norm(start);
    for (let k = 0; k < 4; k++) {
      for (const cand of [dir, ...NEARBY_NAMES.map((n) => path.join(dir, n))]) {
        if (NEARBY_NAMES.includes(path.basename(cand)) && isDir(cand) && hasData(cand)) return cand;
      }
      const up = path.dirname(dir);
      if (up === dir) break;
      dir = up;
    }
  }
  return null;
}

function saveTabs() {
  if (!tabs.remember) return;
  settings.workspaces = tabs.list.slice();
  settings.activeWorkspace = tabs.active;
  saveSettings(true);
}

function tabsState() {
  return { list: tabs.list.map((p) => ({ path: p, name: path.basename(p) || p, exists: isDir(p) })), active: tabs.active,
    legacy: fs.existsSync(legacyDataFile), found: tabs.found || null };
}

/** Adds a folder as a tab (or switches to it). */
function addTab(dir) {
  const p = norm(dir);
  if (!tabs.list.includes(p)) tabs.list.push(p);
  tabs.active = p;
  saveTabs();
  pushTabs();
}
function pushTabs() { mainWindow?.webContents.send('tabs-changed', tabsState()); buildMenu(); }

const firstLoads = new Set();
function workspaceLoad(dir, peek) {
  const file = path.join(dir, DATA_NAME);
  if (!isDir(dir)) return { status: 'missing-folder', path: file };
  if (!fs.existsSync(file)) return { status: 'missing', path: file };
  try {
    const text = fs.readFileSync(file, 'utf8');
    if (!peek && !firstLoads.has(dir)) {
      firstLoads.add(dir);
      try { fs.copyFileSync(file, path.join(dir, 'dayspindle-data.previous.json')); } catch { /* best effort */ }
    }
    return { status: 'loaded', path: file, text };
  } catch (e) {
    return { status: 'unreadable', path: file, error: e.message };
  }
}

function workspaceSave(dir, text) {
  // Never recreate a workspace folder that was moved or deleted while the app was open.
  if (!isDir(dir)) return "the workspace folder isn't there any more";
  try {
    const file = path.join(dir, DATA_NAME);
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, text);
    try { fs.renameSync(tmp, file); }
    catch { fs.writeFileSync(file, text); fs.rmSync(tmp, { force: true }); } // e.g. the file is briefly locked by a sync app
    return null;
  } catch (e) {
    log(`Save failed: ${e.message}`);
    return e.message;
  }
}

function stamp() { return new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-'); }

/** Asks for a folder to use itself as a workspace (no folder is made inside it). */
async function chooseFolder(title, buttonLabel, message) {
  const r = selfcheckScript && arg('selfcheck-new-workspace')
    ? { canceled: false, filePaths: [arg('selfcheck-new-workspace')] }
    : await dialog.showOpenDialog(mainWindow, { title, buttonLabel, message, properties: ['openDirectory', 'createDirectory', 'promptToCreate'] });
  return r.canceled || !r.filePaths[0] ? null : r.filePaths[0];
}

/** File › New Workspace…: the chosen folder itself becomes the workspace, and its tab is named after it. */
async function newWorkspace() {
  const dir = await chooseFolder('New Workspace', 'Use as Workspace',
    'Choose the folder to use as the workspace (New folder makes one). Everything in the workspace is saved in this folder, and its tab takes the folder\'s name.');
  if (!dir) return;
  try {
    if (fs.existsSync(dir) && !isDir(dir)) throw new Error(`“${path.basename(dir)}” is a file, not a folder.`);
    fs.mkdirSync(dir, { recursive: true });
    addTab(dir);
  } catch (e) { dialog.showMessageBox(mainWindow, { type: 'warning', message: "Couldn't use the folder", detail: e.message }); }
}

async function openWorkspace() {
  const r = selfcheckScript && arg('selfcheck-open-workspace')
    ? { canceled: false, filePaths: [arg('selfcheck-open-workspace')] }
    : await dialog.showOpenDialog(mainWindow, {
      title: 'Open Workspace', buttonLabel: 'Open',
      message: 'Choose a workspace folder (it holds dayspindle-data.json).',
      properties: ['openDirectory', 'createDirectory', 'promptToCreate'],
    });
  if (r.canceled || !r.filePaths[0]) return;
  const dir = r.filePaths[0];
  if (!hasData(dir) && !selfcheckScript) {
    const a = await dialog.showMessageBox(mainWindow, {
      type: 'question', buttons: ['Start Workspace', 'Cancel'], defaultId: 0, cancelId: 1,
      message: `“${path.basename(dir)}” isn't a DaySpindle workspace yet`, detail: 'Start a new, empty workspace in this folder?',
    });
    if (a.response !== 0) return;
  }
  fs.mkdirSync(dir, { recursive: true });
  addTab(dir);
}

/** Copies the tasks of DaySpindle 2.0 for Windows (%APPDATA%\DaySpindle\dayspindle-data.json) into the
 * chosen folder, which becomes the workspace. The old file stays where it was. */
async function importLegacy() {
  if (!fs.existsSync(legacyDataFile)) {
    dialog.showMessageBox(mainWindow, { type: 'info', message: 'Nothing to import', detail: 'There are no tasks from DaySpindle 2.0 on this computer.' });
    return;
  }
  const dir = await chooseFolder('Import Tasks from DaySpindle 2.0', 'Import Here',
    'Choose the folder to use as the workspace for your tasks (New folder makes one). Its tab takes the folder\'s name.');
  if (!dir) return;
  try {
    if (hasData(dir)) throw new Error('That folder is already a workspace. Choose another folder for the imported tasks.');
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(legacyDataFile, path.join(dir, DATA_NAME));
    addTab(dir);
  } catch (e) { dialog.showMessageBox(mainWindow, { type: 'warning', message: "Couldn't import", detail: e.message }); }
}

async function locateWorkspace(oldPath) {
  const r = await dialog.showOpenDialog(mainWindow, {
    title: 'Locate Workspace', message: `Where is the folder “${path.basename(oldPath)}” now?`, properties: ['openDirectory'],
  });
  if (r.canceled || !r.filePaths[0]) return;
  const p = norm(r.filePaths[0]);
  const i = tabs.list.indexOf(oldPath);
  if (i >= 0) { if (tabs.list.includes(p)) tabs.list.splice(i, 1); else tabs.list[i] = p; }
  tabs.active = p;
  saveTabs();
  pushTabs();
}

function closeTab(p) {
  const i = tabs.list.indexOf(p);
  if (i < 0) return;
  tabs.list.splice(i, 1);
  if (tabs.active === p) tabs.active = tabs.list.length ? tabs.list[Math.min(i, tabs.list.length - 1)] : null;
  saveTabs();
  pushTabs();
}

function revealWorkspace(p) {
  const file = path.join(p, DATA_NAME);
  if (fs.existsSync(file)) shell.showItemInFolder(file);
  else shell.openPath(p);
}

// ---------------------------------------------------------------- Window
let mainWindow = null;
const iconPath = (dark) => path.join(__dirname, 'icons', dark ? 'icon-dark.png' : 'icon-light.png');

function applyAppearance() {
  nativeTheme.themeSource = settings.appearance;
  if (!mainWindow) return;
  mainWindow.setBackgroundColor(nativeTheme.shouldUseDarkColors ? '#1E1E20' : '#FFFFFF');
  if (process.platform !== 'darwin') {
    const img = nativeImage.createFromPath(iconPath(nativeTheme.shouldUseDarkColors));
    if (!img.isEmpty()) mainWindow.setIcon(img);
  }
}
nativeTheme.on('updated', () => {
  applyAppearance();
  mainWindow?.webContents.send('theme-changed', nativeTheme.shouldUseDarkColors);
});

function validBounds(b) {
  if (!b || !Number.isFinite(b.x) || !Number.isFinite(b.y) || b.width < 400 || b.height < 300) return null;
  const visible = screen.getAllDisplays().some((d) => {
    const a = d.workArea;
    return b.x < a.x + a.width - 80 && b.x + b.width > a.x + 80 && b.y < a.y + a.height - 40 && b.y + 10 > a.y - 10;
  });
  return visible ? b : null;
}

function createWindow() {
  const b = validBounds(settings.bounds);
  mainWindow = new BrowserWindow({
    width: b?.width || 1360, height: b?.height || 820, x: b?.x, y: b?.y,
    minWidth: 960, minHeight: 560,
    title: 'DaySpindle',
    show: false,
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#1E1E20' : '#FFFFFF',
    icon: process.platform !== 'darwin' ? iconPath(nativeTheme.shouldUseDarkColors) : undefined,
    autoHideMenuBar: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
      backgroundThrottling: !selfcheckScript,
    },
  });
  if (settings.maximized && !selfcheckScript) mainWindow.maximize();
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.once('ready-to-show', () => { if (!selfcheckScript || flag('selfcheck-visible')) mainWindow.show(); else mainWindow.showInactive(); });

  const remember = () => {
    if (!mainWindow || mainWindow.isMinimized() || mainWindow.isFullScreen()) return;
    settings.maximized = mainWindow.isMaximized();
    if (!settings.maximized) settings.bounds = mainWindow.getBounds();
    saveSettings();
  };
  mainWindow.on('resize', remember);
  mainWindow.on('move', remember);
  mainWindow.on('close', () => { remember(); saveSettings(true); });
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.on('focus', () => mainWindow?.webContents.send('app-focus'));

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (e) => e.preventDefault());
  applyAppearance();
}

// ---------------------------------------------------------------- Menus
// The window's page handles every shortcut itself; the menu bar only shows them.
let menuState = {};
const send = (command, ...args) => mainWindow?.webContents.send('command', command, ...args);

function item(label, command, accelerator, extra = {}) {
  const o = { label, click: () => send(command, extra.arg), ...extra };
  delete o.arg;
  if (accelerator && process.platform !== 'darwin') { o.accelerator = accelerator; o.registerAccelerator = false; }
  return o;
}
const action = (label, fn, accelerator, extra = {}) => {
  const o = { label, click: fn, ...extra };
  if (accelerator && process.platform !== 'darwin') { o.accelerator = accelerator; o.registerAccelerator = false; }
  return o;
};

const PRESET_TITLES = ['1 Week', '2 Weeks', '3 Weeks', '1 Month', '2 Months', '3 Months', '6 Months', '1 Year'];

function buildMenu() {
  const s = menuState;
  const busy = !!s.sheetOpen;
  const ws = !!s.hasWorkspace;
  const sel = !busy && ws && !!s.hasSelection;
  const template = [
    {
      label: '&File',
      submenu: [
        item('New Task', 'newTask', 'Ctrl+N', { enabled: !busy && ws }),
        item('New Subtask', 'newSubtask', 'Ctrl+Alt+N', { enabled: sel && s.selectionKind !== 'milestone' }),
        item('New Milestone', 'newMilestone', 'Ctrl+Shift+M', { enabled: !busy && ws }),
        item('New Group', 'newGroup', 'Ctrl+Shift+G', { enabled: !busy && ws }),
        item('New Category', 'newCategory', 'Ctrl+Shift+N', { enabled: !busy && ws }),
        { type: 'separator' },
        item('Show Details', 'editTask', 'Ctrl+E', { enabled: sel }),
        item(s.selectionCompleted ? (s.selectionIsMark ? 'Mark as Not Completed' : 'Return from Archive') : 'Mark as Completed', 'toggleCompleted', 'Ctrl+Shift+C', { enabled: sel }),
        item('Delete…', 'deleteTask', 'Delete', { enabled: sel }),
        item('Move Up', 'moveUp', 'Alt+Up', { enabled: sel && !!s.canMoveUp }),
        item('Move Down', 'moveDown', 'Alt+Down', { enabled: sel && !!s.canMoveDown }),
        { type: 'separator' },
        action('New Workspace…', () => newWorkspace(), 'Ctrl+Alt+Shift+N', { enabled: !busy }),
        action('Open Workspace…', () => openWorkspace(), 'Ctrl+O', { enabled: !busy }),
        action('Import Tasks from DaySpindle 2.0…', () => importLegacy(), null, { enabled: !busy && fs.existsSync(legacyDataFile) }),
        action('Show Workspace in Finder', () => tabs.active && revealWorkspace(tabs.active), null,
          { enabled: !!tabs.active, label: isWindows ? 'Show Workspace in File Explorer' : 'Show Workspace in Finder' }),
        action('Close Workspace Tab', () => tabs.active && closeTab(tabs.active), 'Ctrl+W', { enabled: !busy && !!tabs.active }),
        { type: 'separator' },
        item('Import Data…', 'importData', null, { enabled: !busy && ws }),
        item('Export Data…', 'exportData', null, { enabled: !busy && ws }),
        { type: 'separator' },
        item('Settings…', 'settings', 'Ctrl+,', { enabled: !busy }),
        { type: 'separator' },
        { label: 'E&xit', role: 'quit' },
      ],
    },
    {
      label: '&Edit',
      submenu: [
        item(s.canUndo ? `Undo ${s.undoName}` : 'Undo', 'undo', 'Ctrl+Z', { enabled: busy || !!s.canUndo }),
        item(s.canRedo ? `Redo ${s.redoName}` : 'Redo', 'redo', 'Ctrl+Y', { enabled: busy || !!s.canRedo }),
        { type: 'separator' },
        { label: 'Cut', role: 'cut' },
        { label: 'Copy', role: 'copy' },
        { label: 'Paste', role: 'paste' },
        { label: 'Select All', role: 'selectAll' },
      ],
    },
    {
      label: '&View',
      submenu: [
        item(s.inspectorVisible ? 'Hide Details' : 'Show Details', 'toggleInspector', 'Ctrl+I', { enabled: !busy && ws }),
        { type: 'separator' },
        item('All Items', 'allTasks', 'Ctrl+1', { enabled: !busy && ws }),
        item('Clear Filters', 'clearFilters', 'Ctrl+K', { enabled: !busy && !!s.filtersActive }),
        { type: 'separator' },
        item('Expand All Groups', 'expandAll', null, { enabled: !busy && !!s.hasGroups }),
        item('Collapse All Groups', 'collapseAll', null, { enabled: !busy && !!s.hasGroups }),
        { type: 'separator' },
        item('Today', 'today', 'Ctrl+T', { enabled: !busy && ws }),
        item('Previous Period', 'previous', 'Alt+Left', { enabled: !busy && ws }),
        item('Next Period', 'next', 'Alt+Right', { enabled: !busy && ws }),
        {
          label: 'Time Scale',
          enabled: !busy && ws,
          submenu: PRESET_TITLES.map((t, i) => ({ label: t, type: 'radio', checked: s.preset === t, click: () => send('preset', i) })),
        },
        { type: 'separator' },
        {
          label: 'First Day of Week',
          enabled: !busy,
          submenu: [[0, 'Sunday'], [1, 'Monday'], [6, 'Saturday']].map(([d, t]) => ({
            label: t, type: 'radio', checked: (s.firstWeekday ?? 0) === d, click: () => send('firstWeekday', d),
          })),
        },
        item('Today Color…', 'todayColor', null, { enabled: !busy && ws }),
        item('Time Zone…', 'settings', null, { enabled: !busy }),
        {
          label: 'Appearance',
          submenu: [['system', 'System'], ['light', 'Light'], ['dark', 'Dark']].map(([m, t]) => ({
            label: t, type: 'radio', checked: settings.appearance === m, click: () => setAppearance(m),
          })),
        },
        { type: 'separator' },
        item('Next Workspace', 'nextTab', 'Ctrl+Tab', { enabled: tabs.list.length > 1 }),
        item('Previous Workspace', 'previousTab', 'Ctrl+Shift+Tab', { enabled: tabs.list.length > 1 }),
        { type: 'separator' },
        { label: 'Actual Size', role: 'resetZoom' },
        { label: 'Zoom In', role: 'zoomIn', accelerator: 'CommandOrControl+=' },
        { label: 'Zoom Out', role: 'zoomOut' },
        { type: 'separator' },
        { label: 'Full Screen', role: 'togglefullscreen' },
      ],
    },
    {
      label: '&Help',
      submenu: [
        item('Add Example Tasks', 'addExamples', null, { enabled: !busy && ws }),
        { type: 'separator' },
        { label: 'About DaySpindle', click: () => about() },
        ...(app.isPackaged ? [] : [{ type: 'separator' }, { label: 'Developer Tools', role: 'toggleDevTools' }]),
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function setAppearance(mode) {
  if (!['system', 'light', 'dark'].includes(mode)) return;
  settings.appearance = mode;
  saveSettings(true);
  applyAppearance();
  buildMenu();
  mainWindow?.webContents.send('appearance-changed', mode, nativeTheme.shouldUseDarkColors);
}

function about() {
  dialog.showMessageBox(mainWindow, {
    type: 'none',
    icon: nativeImage.createFromPath(iconPath(nativeTheme.shouldUseDarkColors)),
    title: 'About DaySpindle',
    message: `DaySpindle ${app.getVersion()}`,
    detail: `A local Gantt chart of groups, tasks and milestones.\n\nCopyright © 2026 Ruichen Li. MIT License.${tabs.active ? `\n\nWorkspace:\n${tabs.active}` : ''}`,
    buttons: ['OK'],
  });
}

// ---------------------------------------------------------------- Popup menus
function swatch(hex) {
  const n = 32, r = 11, buf = Buffer.alloc(n * n * 4);
  const v = parseInt(String(hex).replace('#', ''), 16);
  const R = (v >> 16) & 255, G = (v >> 8) & 255, B = v & 255;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const d = Math.hypot(x + 0.5 - n / 2, y + 0.5 - n / 2);
      const a = Math.max(0, Math.min(1, r - d + 0.5));
      const i = (y * n + x) * 4;
      buf[i] = Math.round(B * a); buf[i + 1] = Math.round(G * a); buf[i + 2] = Math.round(R * a); buf[i + 3] = Math.round(255 * a);
    }
  }
  return nativeImage.createFromBitmap(buf, { width: n, height: n, scaleFactor: 2 });
}

let popupQueue = []; // self-check: labels to pick in the next popup menus
let lastPopup = null;

function popupMenu(sender, items, pos) {
  return new Promise((resolve) => {
    let chosen = null;
    const build = (list) => list.map((it) => {
      if (it.type === 'separator') return { type: 'separator' };
      const o = { label: it.label, enabled: it.enabled !== false };
      if (it.checked != null) { o.type = it.radio ? 'radio' : 'checkbox'; o.checked = !!it.checked; }
      if (it.swatch) o.icon = swatch(it.swatch);
      if (it.submenu) o.submenu = build(it.submenu);
      else o.click = () => { chosen = it.id; };
      return o;
    });
    lastPopup = items;
    if (selfcheckScript) {
      const want = popupQueue.shift();
      const find = (list) => {
        for (const it of list) {
          if (it.submenu) { const f = find(it.submenu); if (f) return f; }
          else if (it.label === want && it.enabled !== false) return it.id;
        }
        return null;
      };
      resolve(want ? find(items) : null);
      return;
    }
    const menu = Menu.buildFromTemplate(build(items));
    const win = BrowserWindow.fromWebContents(sender);
    menu.popup({ window: win, x: pos ? Math.round(pos.x) : undefined, y: pos ? Math.round(pos.y) : undefined,
      callback: () => setImmediate(() => resolve(chosen)) });
  });
}

// ---------------------------------------------------------------- IPC
ipcMain.handle('config', () => ({
  prefs: { firstWeekday: settings.firstWeekday, todayColor: settings.todayColor, sidebarWidth: settings.sidebarWidth,
    taskListWidth: settings.taskListWidth, appearance: settings.appearance, inspectorWidth: settings.inspectorWidth,
    inspectorVisible: settings.inspectorVisible !== false, timeZone: settings.timeZone || null },
  dark: nativeTheme.shouldUseDarkColors,
  simulatedNow: arg('simulated-now'),
  simulatedTimeZone: arg('simulated-time-zone'),
  platform: process.platform,
  version: app.getVersion(),
  selfcheck: !!selfcheckScript,
  tabs: tabsState(),
}));
ipcMain.handle('workspace-load', (_e, dir, peek) => workspaceLoad(norm(dir), !!peek));
ipcMain.handle('workspace-save', (_e, dir, text) => workspaceSave(norm(dir), String(text)));
ipcMain.handle('workspace-quarantine', (_e, dir) => {
  try { fs.renameSync(path.join(dir, DATA_NAME), path.join(dir, `dayspindle-data.unreadable-${stamp()}.json`)); } catch { /* ignore */ }
});
ipcMain.on('workspace-keep-copy', (_e, dir, name) => {
  const dest = path.join(dir, path.basename(String(name)));
  try { if (!fs.existsSync(dest)) fs.copyFileSync(path.join(dir, DATA_NAME), dest); } catch { /* best effort */ }
});
ipcMain.handle('tabs', () => tabsState());
ipcMain.on('tab-select', (_e, p) => { if (tabs.list.includes(p)) { tabs.active = p; saveTabs(); buildMenu(); } });
ipcMain.on('tab-close', (_e, p) => closeTab(p));
ipcMain.on('tab-move', (_e, p, offset) => {
  const i = tabs.list.indexOf(p), j = i + offset;
  if (i < 0 || j < 0 || j >= tabs.list.length) return;
  [tabs.list[i], tabs.list[j]] = [tabs.list[j], tabs.list[i]];
  saveTabs();
  pushTabs();
});
ipcMain.on('tab-reveal', (_e, p) => revealWorkspace(p));
ipcMain.on('tab-locate', (_e, p) => locateWorkspace(p));
ipcMain.on('workspace-new', () => newWorkspace());
ipcMain.on('workspace-open', () => openWorkspace());
ipcMain.on('workspace-import-legacy', () => importLegacy());
ipcMain.on('log', (_e, msg) => log(String(msg)));
ipcMain.on('set-pref', (_e, key, value) => {
  if (!(key in defaultSettings) || ['bounds', 'maximized', 'workspaces', 'activeWorkspace'].includes(key)) return;
  if (key === 'appearance') { setAppearance(value); return; }
  settings[key] = value;
  saveSettings(true);
  if (key === 'firstWeekday') buildMenu();
});
ipcMain.on('menu-state', (_e, state) => {
  const next = JSON.stringify(state);
  if (next === JSON.stringify(menuState)) return;
  menuState = state;
  buildMenu();
});
ipcMain.handle('popup', (e, items, pos) => popupMenu(e.sender, items, pos));
ipcMain.on('about', () => about());

ipcMain.handle('choose-import', async () => {
  const r = selfcheckScript && arg('selfcheck-import')
    ? { canceled: false, filePaths: [arg('selfcheck-import')] }
    : await dialog.showOpenDialog(mainWindow, {
      title: 'Import DaySpindle Data', buttonLabel: 'Import',
      filters: [{ name: 'DaySpindle data', extensions: ['json'] }], properties: ['openFile'],
    });
  if (r.canceled || !r.filePaths[0]) return null;
  try { return { path: r.filePaths[0], text: fs.readFileSync(r.filePaths[0], 'utf8') }; }
  catch (e) { return { path: r.filePaths[0], error: e.message }; }
});
ipcMain.handle('backup-before-import', (_e, dir) => {
  try {
    const file = path.join(dir, DATA_NAME);
    if (fs.existsSync(file)) fs.copyFileSync(file, path.join(dir, `dayspindle-data.before-import-${stamp()}.json`));
    return null;
  } catch (e) { return e.message; }
});
ipcMain.handle('export', async (_e, text) => {
  const r = selfcheckScript && arg('selfcheck-export')
    ? { canceled: false, filePath: arg('selfcheck-export') }
    : await dialog.showSaveDialog(mainWindow, {
      title: 'Export DaySpindle Data', buttonLabel: 'Export', defaultPath: path.join(app.getPath('documents'), DATA_NAME),
      filters: [{ name: 'DaySpindle data', extensions: ['json'] }],
    });
  if (r.canceled || !r.filePath) return { canceled: true };
  try { fs.writeFileSync(r.filePath, String(text)); return { path: r.filePath }; }
  catch (e) { return { error: e.message }; }
});

// ---------------------------------------------------------------- Start
app.whenReady().then(() => {
  loadSettings();
  initTabs();
  nativeTheme.themeSource = settings.appearance;
  buildMenu();
  createWindow();
  powerMonitor.on('resume', () => mainWindow?.webContents.send('refresh-today'));
  powerMonitor.on('unlock-screen', () => mainWindow?.webContents.send('refresh-today'));
  if (selfcheckScript) {
    mainWindow.webContents.once('did-finish-load', () => {
      require(path.resolve(selfcheckScript))({
        app, win: mainWindow, dataDir, settingsFile, arg, log, logLines,
        queuePopup: (...labels) => { popupQueue = labels; },
        lastPopup: () => lastPopup,
        setAppearance, getSettings: () => settings, tabs, addTab, closeTab,
      });
    });
  }
});

app.on('window-all-closed', () => app.quit());
