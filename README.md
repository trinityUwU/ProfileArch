# Dotfiles Backup — TrinityArch
> Arch Linux + Hyprland + HyDE + Quickshell (ii)
> Backup créé le 09/04/2026

---

## Environnement

| Composant        | Détail                          |
|------------------|---------------------------------|
| OS               | Arch Linux (rolling)            |
| Kernel           | zen (latence desktop/gaming)    |
| WM               | Hyprland v0.54+ (Wayland)       |
| Display Manager  | SDDM                            |
| Dotfile Manager  | HyDE (The HyDE Project)         |
| Thème actif      | Catppuccin Mocha                |
| Bar              | Quickshell (config `ii`)        |
| Terminal         | Kitty + Fish shell              |
| GTK Theme        | Catppuccin-Mocha                |
| Icon Theme       | Tela-circle-dracula             |

---

## Structure du backup

```
dotfiles-backup/
├── apps/
│   └── wpe-manager/       ← App Wallpaper Engine Manager (Electron + Python)
├── config/
│   ├── hypr/              ← Config Hyprland complète (modulaire)
│   ├── kitty/             ← Config terminal kitty
│   ├── quickshell/        ← Bar quickshell (config ii)
│   ├── rofi/              ← Launcher rofi
│   ├── waybar/            ← Config waybar (si utilisé)
│   ├── dunst/             ← Notifications
│   ├── gtk-3.0/           ← Thème GTK 3
│   ├── gtk-4.0/           ← Thème GTK 4
│   ├── Kvantum/           ← Thème Qt/Kvantum
│   ├── wlogout/           ← Menu de session
│   ├── gtkrc / gtkrc-2.0  ← GTK 2
│   ├── hyde-config.toml   ← Config principale HyDE
│   ├── hyde-wallbash/     ← Templates wallbash
│   └── hyde-themes/       ← Tous les thèmes HyDE (sans wallpapers)
├── local-state/
│   └── quickshell-generated/  ← Couleurs Material You générées
│       ├── colors.json         ← Palette topbar (violet profond)
│       └── material_colors.scss
└── local-share/
    └── hyde/              ← Données partagées HyDE
install-wpe-manager.sh     ← Installation complète WPE (Wallpaper Engine)
```

---

## WPE Manager (Wallpaper Engine)

Installe les paquets (Python, Electron, mpvpaper, GTK/WebKit pour les fonds HTML), copie `apps/wpe-manager` vers `~/wpe-manager`, crée `~/.config/wallpaperengine_screens.conf`, le lanceur menu et vérifie le dossier Steam workshop.

```bash
bash install-wpe-manager.sh
```

Options : `--deps-only`, `--skip-deps`. Intégré automatiquement à la fin de `install.sh` (sans reposer les paquets déjà gérés à l’étape 4). Documentation : `apps/wpe-manager/README.md`.

---

## Prérequis à installer (pacman / yay)

```bash
# WM et composants Wayland
yay -S hyprland xdg-desktop-portal-hyprland hyprlock hypridle

# Display Manager
yay -S sddm

# HyDE (gestionnaire de thème)
# Voir : https://github.com/HyDE-Project/HyDE
# Installation officielle :
bash <(curl -fsSL https://raw.githubusercontent.com/HyDE-Project/HyDE/main/install.sh)

# Bar
yay -S quickshell

# Terminal
yay -S kitty fish

# Thèmes et icônes
yay -S catppuccin-gtk-theme-mocha tela-icon-theme

# Outils
yay -S rofi-wayland dunst wlogout waybar

# Kvantum
yay -S kvantum kvantum-theme-catppuccin-git
```

---

## Installation des dotfiles

```bash
# 1. Copier les configs
cp -r config/hypr ~/.config/
cp -r config/kitty ~/.config/
cp -r config/quickshell ~/.config/
cp -r config/rofi ~/.config/
cp -r config/waybar ~/.config/
cp -r config/dunst ~/.config/
cp -r config/gtk-3.0 ~/.config/
cp -r config/gtk-4.0 ~/.config/
cp -r config/Kvantum ~/.config/
cp -r config/wlogout ~/.config/
cp config/gtkrc ~/.config/
cp config/gtkrc-2.0 ~/.config/

# 2. Config HyDE
mkdir -p ~/.config/hyde/themes
cp config/hyde-config.toml ~/.config/hyde/config.toml
cp -r config/hyde-wallbash ~/.config/hyde/wallbash
cp -r config/hyde-themes/* ~/.config/hyde/themes/

# 3. Données locales
mkdir -p ~/.local/state/quickshell/user/generated
cp local-state/quickshell-generated/* ~/.local/state/quickshell/user/generated/
cp -r local-share/hyde ~/.local/share/

# 4. Appliquer les couleurs quickshell
bash ~/.config/quickshell/ii/scripts/colors/applycolor.sh

# 5. Recharger Hyprland
hyprctl reload
```

---

## Personnalisations appliquées

Les modifications personnelles se trouvent dans `~/.config/hypr/custom/` :

- **`general.conf`** — fond violet profond (`#0d0b14`), bordures `#4f4a59` (2px),
  opacité active 0.80 / inactive 0.60, blur activé
- **`rules.conf`** — fenêtres tuilées (kitty, cursor, chrome, discord, spotify, steam, claude)
  à 95% actif / 90% inactif ; flottantes héritent des valeurs decoration

### Palette couleurs (Material You violet)
- Background : `#0d0b14`
- Primary : `#9d6ff5`
- Secondary : `#8f9bef`
- Surface : `#11101C`
- Texte : `#cdd6f4`

---

## Notes importantes

- Les **wallpapers** ne sont pas inclus dans ce backup (trop volumineux).
  Placer ses wallpapers dans `~/.config/hyde/themes/<ThemeName>/wallpapers/`
- Les **icônes** (`Tela-circle-dracula`) et **thèmes GTK** (`Catppuccin-Mocha`) 
  doivent être réinstallés via AUR
- Le fichier `colors.json` dans `local-state/quickshell-generated/` contient 
  la palette violet personnalisée — à copier pour garder l'ambiance
