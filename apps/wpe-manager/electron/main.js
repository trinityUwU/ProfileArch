const { app, BrowserWindow, Tray, Menu, nativeImage, shell } = require('electron')
const { spawn, execSync } = require('child_process')
const http = require('http')
const path = require('path')

// Nom de l'app (app_id Wayland + WM class)
app.setName('wpe-manager')
app.setDesktopName('wpe-manager.desktop')

const SERVER_PORT = 6969
const SERVER_URL  = `http://localhost:${SERVER_PORT}`
const ROOT        = path.join(__dirname, '..')
const ICON        = path.join(__dirname, 'icon.png')
const ICON_TRAY   = path.join(__dirname, 'icon_tray.png')

let mainWindow  = null
let tray        = null
let serverProc  = null
let quitting    = false

// ─── Serveur Python ───────────────────────────────────────────────────────────

function isServerUp(cb) {
  const req = http.get(SERVER_URL + '/api/screens', (res) => {
    cb(res.statusCode === 200)
  })
  req.on('error', () => cb(false))
  req.setTimeout(800, () => { req.destroy(); cb(false) })
}

function startServer() {
  isServerUp((up) => {
    if (up) {
      console.log('[WPE] Server already running.')
      return
    }
    console.log('[WPE] Starting server.py…')
    serverProc = spawn('python3', [path.join(ROOT, 'server.py')], {
      cwd: ROOT,
      detached: false,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    serverProc.stdout.on('data', d => process.stdout.write(`[server] ${d}`))
    serverProc.stderr.on('data', d => process.stderr.write(`[server] ${d}`))
    serverProc.on('exit', (code) => {
      if (!quitting) console.error(`[WPE] server.py exited with code ${code}`)
    })
  })
}

function stopServer() {
  if (serverProc) {
    serverProc.kill('SIGTERM')
    serverProc = null
  }
}

// ─── Fenêtre principale ───────────────────────────────────────────────────────

function waitForServer(retries, onReady) {
  if (retries <= 0) {
    console.error('[WPE] Server not responding after retries.')
    onReady()
    return
  }
  isServerUp((up) => {
    if (up) {
      onReady()
    } else {
      setTimeout(() => waitForServer(retries - 1, onReady), 600)
    }
  })
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 900,
    minHeight: 600,
    title: 'WPE Manager',
    icon: ICON,
    backgroundColor: '#0d0d1a',
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
    },
  })

  // Empêcher la page web de changer le titre de la fenêtre
  mainWindow.on('page-title-updated', (event) => {
    event.preventDefault()
  })

  // Masquer plutôt que fermer (comportement tray)
  mainWindow.on('close', (event) => {
    if (!quitting) {
      event.preventDefault()
      mainWindow.hide()
      tray.displayBalloon?.({
        title: 'WPE Manager',
        content: 'L\'app tourne en fond. Clic sur l\'icône pour rouvrir.',
        iconType: 'info',
      })
    }
  })

  waitForServer(15, () => {
    mainWindow.loadURL(SERVER_URL)
    mainWindow.once('ready-to-show', () => {
      mainWindow.show()
      mainWindow.focus()
    })
  })
}

// ─── Tray ─────────────────────────────────────────────────────────────────────

function buildTrayMenu() {
  return Menu.buildFromTemplate([
    {
      label: 'Ouvrir WPE Manager',
      icon: nativeImage.createFromPath(ICON_TRAY).resize({ width: 16, height: 16 }),
      click: () => showWindow(),
    },
    { type: 'separator' },
    {
      label: 'Appliquer les fonds',
      click: () => {
        http.get(`${SERVER_URL}/api/assignment`, (res) => {
          let body = ''
          res.on('data', d => body += d)
          res.on('end', () => {
            const asgn = JSON.parse(body)
            const reqBody = JSON.stringify({ assignment: asgn })
            const opts = {
              hostname: 'localhost',
              port: SERVER_PORT,
              path: '/api/apply',
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(reqBody) },
            }
            const req = http.request(opts)
            req.write(reqBody)
            req.end()
          })
        }).on('error', () => {})
      },
    },
    { type: 'separator' },
    {
      label: 'Quitter',
      click: () => {
        quitting = true
        app.quit()
      },
    },
  ])
}

function createTray() {
  tray = new Tray(ICON_TRAY)
  tray.setToolTip('WPE Manager')
  tray.setContextMenu(buildTrayMenu())

  // Clic gauche : bascule visibilité
  tray.on('click', () => {
    if (mainWindow.isVisible() && mainWindow.isFocused()) {
      mainWindow.hide()
    } else {
      showWindow()
    }
  })
}

function showWindow() {
  if (!mainWindow) return
  if (!mainWindow.isVisible()) mainWindow.show()
  if (mainWindow.isMinimized()) mainWindow.restore()
  mainWindow.focus()
}

// ─── App lifecycle ────────────────────────────────────────────────────────────

// Instance unique — si une autre instance tente de démarrer, on affiche celle-ci
const gotLock = app.requestSingleInstanceLock()
if (!gotLock) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) showWindow()
  })
}

app.on('ready', () => {
  startServer()
  createTray()
  createWindow()
})

// Ne pas quitter quand toutes les fenêtres sont fermées (tray mode)
app.on('window-all-closed', (e) => {
  if (!quitting) e && e.preventDefault?.()
})

app.on('before-quit', () => {
  quitting = true
  stopServer()
})

app.on('activate', () => {
  if (mainWindow) showWindow()
})
