const { app, BrowserWindow, Tray, Menu, screen, ipcMain, nativeImage } = require('electron');
const path = require('path');

let win;
let tray;

function createWindow() {
  const primaryDisplay = screen.getPrimaryDisplay();
  const { x, y, width, height } = primaryDisplay.bounds;

  win = new BrowserWindow({
    x,
    y,
    width,
    height,
    transparent: true,
    frame: false,
    hasShadow: false,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    fullscreenable: false,
    focusable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // Relay renderer console output to the terminal — there's no devtools window
  // to check it in otherwise (frameless, no chrome).
  win.webContents.on('console-message', (_event, _level, message) => {
    console.log(`[renderer] ${message}`);
  });
}

function createTray() {
  // Empty image + emoji title avoids shipping a placeholder icon asset for the POC.
  tray = new Tray(nativeImage.createEmpty());
  tray.setTitle('🟢');
  tray.setToolTip('Jiggy');
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Quit', click: () => app.quit() },
    ])
  );
}

ipcMain.on('set-ignore-mouse-events', (_event, ignore) => {
  win.setIgnoreMouseEvents(ignore, { forward: true });
});

app.whenReady().then(() => {
  app.dock?.hide();
  createWindow();
  createTray();
});

app.on('window-all-closed', () => {
  app.quit();
});
