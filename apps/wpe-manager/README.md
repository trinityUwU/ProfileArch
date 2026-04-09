# WPE Manager v3

Interface web + systray (Electron) pour appliquer des fonds **Wallpaper Engine** (Steam workshop) sur Hyprland : **vidéo** via `mpvpaper`, **HTML** via `wpe_web_wallpaper.py` (GTK/WebKit), **scenes** optionnellement via `linux-wallpaperengine`.

## Prérequis

1. **Steam** + Wallpaper Engine + abonnements workshop (dossier `~/.local/share/Steam/steamapps/workshop/content/431960/`).
2. Paquets système : voir `install-wpe-manager.sh` (Python 3, Electron, mpvpaper, gtk3, webkit2gtk, python-gobject, etc.).

## Installation

Depuis la racine du repo ProfileArch :

```bash
bash install-wpe-manager.sh
```

Options :

- `--deps-only` — installe uniquement les paquets (pacman / yay).
- `--skip-deps` — copie les fichiers sans toucher aux paquets.

## Utilisation

- **UI** : lance `electron ~/wpe-manager/electron/main.js --no-sandbox` (ou via le `.desktop` après install).
- **API** : `http://localhost:6969` — le serveur Python démarre avec l’app Electron.
- **Écrans** : détectés via `hyprctl monitors` au démarrage du serveur. Sinon variable `WPE_SCREENS=DP-1,HDMI-A-1`.
- **Scenes LWE** : `WPE_USE_LWE=1` avant de lancer le serveur pour tenter `linux-wallpaperengine` sur les scènes sans vidéo/HTML.

## Fichiers

| Chemin | Rôle |
|--------|------|
| `~/.config/wallpaperengine_screens.conf` | `ECRAN=workshop_id` |
| `~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh` | Régénéré à chaque « Appliquer » |
| `~/wpe-manager/` | Copie depuis `apps/wpe-manager/` |

## Hyprland

`exec-once` recommandé (déjà dans `config/hypr/custom/execs.conf` du backup) :

```ini
exec-once = sleep 4 && /usr/bin/electron $HOME/wpe-manager/electron/main.js --no-sandbox
```

Remplace `/usr/bin/electron` par `$(command -v electron)` si besoin.
