#!/usr/bin/env bash
# =============================================================================
# install.sh — Restauration complète TrinityArch
# Arch Linux (clean) + HyDE + end-4/dots-hyprland + Catppuccin Mocha violet
# =============================================================================
# USAGE  : bash install.sh
# CIBLE  : Arch Linux minimal fresh install, utilisateur non-root avec sudo
# ORDRE  : yay → HyDE → illogical-impulse → paquets extra → dotfiles → config
# =============================================================================

set -e

# ── Couleurs terminal ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR ]${NC}  $*"; }
section() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  $*$(printf '%*s' $((48 - ${#*})) '')║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
}

# ── Vérifications ─────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && { err "Ne pas lancer en root."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
STATE_SRC="$SCRIPT_DIR/local-state"
SHARE_SRC="$SCRIPT_DIR/local-share"
APPS_SRC="$SCRIPT_DIR/apps"

[[ ! -d "$CONFIG_SRC" ]] && { err "Dossier config/ introuvable. Lance depuis dotfiles-backup/"; exit 1; }

section "TrinityArch — Installation"
echo ""
info "Source backup : $SCRIPT_DIR"
info "Utilisateur   : $USER  ($HOME)"
echo ""
echo -e "${YELLOW}Ce script installe dans l'ordre :${NC}"
echo "  1. yay (AUR helper)"
echo "  2. HyDE — gestionnaire de thème (installe Hyprland, SDDM, GTK, fonts…)"
echo "  3. end-4/dots-hyprland — illogical-impulse (quickshell, cursor, audio…)"
echo "  4. Paquets extra (matugen, mpvpaper, nwg-displays, electron…)"
echo "  5. Dotfiles personnalisés (copie par-dessus HyDE)"
echo "  6. wpe-manager + configuration système"
echo ""
read -rp "$(echo -e "${BOLD}Continuer ? [o/N] ${NC}")" confirm
[[ "$confirm" =~ ^[oOyY]$ ]] || { info "Annulé."; exit 0; }

# =============================================================================
# ÉTAPE 1 — YAY
# =============================================================================
section "1/6 — yay (AUR helper)"

if command -v yay &>/dev/null; then
    ok "yay déjà présent ($(yay --version | head -1))"
else
    info "Installation de git + base-devel..."
    sudo pacman -S --needed --noconfirm git base-devel

    info "Clonage et compilation de yay..."
    _tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$_tmp/yay"
    (cd "$_tmp/yay" && makepkg -si --noconfirm)
    rm -rf "$_tmp"
    ok "yay installé"
fi

# =============================================================================
# ÉTAPE 2 — HyDE
# =============================================================================
# HyDE installe automatiquement :
#   hyprland, hyprlock, hypridle, sddm (thème Candy), waybar, rofi, dunst,
#   kitty, fish, GTK Catppuccin themes, polkit, xdg-portals, fonts, etc.
# =============================================================================
section "2/6 — HyDE (HyDE-Project/HyDE)"

HYDE_DIR="$HOME/HyDE"

if command -v hyde-shell &>/dev/null || [[ -f "$HOME/.local/bin/hyde-shell" ]]; then
    ok "HyDE déjà installé"
else
    info "Clonage de HyDE..."
    if [[ -d "$HYDE_DIR" ]]; then
        warn "Dossier ~/HyDE existant — mise à jour..."
        (cd "$HYDE_DIR" && git fetch --depth 1 origin master && git reset --hard origin/master)
    else
        git clone --depth 1 https://github.com/HyDE-Project/HyDE "$HYDE_DIR"
    fi

    info "Lancement de l'installateur HyDE..."
    echo ""
    warn "════════════════════════════════════════════════════"
    warn "  IMPORTANT — Questions de l'installateur HyDE :"
    warn "  • Si on te demande de remplacer des configs :"
    warn "    Réponds OUI — nos dotfiles écraseront après."
    warn "  • Si NVIDIA détecté : laisse HyDE installer les"
    warn "    drivers (nvidia-open-dkms)."
    warn "════════════════════════════════════════════════════"
    echo ""

    (cd "$HYDE_DIR/Scripts" && ./install.sh)
    ok "HyDE installé"
fi

# =============================================================================
# ÉTAPE 3 — end-4/dots-hyprland (illogical-impulse)
# =============================================================================
# Ces paquets AUR fournissent :
#   quickshell deps, Bibata cursor, fonts extra, audio (easyeffects…),
#   Material Symbols font, screencapture tools, Python ML deps, KDE utils
# =============================================================================
section "3/6 — end-4/dots-hyprland (illogical-impulse)"

_aur_install() {
    local pkg="$1"
    if pacman -Qq "$pkg" &>/dev/null; then
        info "  [présent] $pkg"
    else
        info "  Installation : $pkg"
        yay -S --needed --noconfirm "$pkg" 2>/dev/null \
            || warn "  Échec : $pkg (non bloquant)"
    fi
}

II_PKGS=(
    illogical-impulse-hyprland          # Hyprland + plugins end-4 spécifiques
    illogical-impulse-basic             # Outils de base
    illogical-impulse-fonts-themes      # GTK Catppuccin + Tela icons + fonts
    illogical-impulse-bibata-modern-classic-bin  # Curseur Bibata Modern Classic
    illogical-impulse-audio             # EasyEffects + audio
    illogical-impulse-portal            # XDG portals
    illogical-impulse-python            # Python deps (ML, numpy, etc.)
    illogical-impulse-screencapture     # grim, slurp, satty…
    illogical-impulse-toolkit           # Outils divers
    illogical-impulse-widgets           # Dépendances widgets
    illogical-impulse-kde               # Qt/KDE utilities
    illogical-impulse-microtex-git      # Rendu LaTeX dans quickshell
)

for pkg in "${II_PKGS[@]}"; do
    _aur_install "$pkg"
done

ok "Paquets illogical-impulse installés"

# =============================================================================
# ÉTAPE 4 — Paquets extra
# =============================================================================
section "4/6 — Paquets extra"

EXTRA_PKGS=(
    # Bar
    quickshell-git

    # Material You color generation
    matugen

    # Wallpaper vidéo
    mpvpaper

    # Gestion multi-moniteurs
    nwg-displays
    nwg-look

    # Fonts
    ttf-material-symbols-variable-git   # Icônes Material Symbols (quickshell)
    ttf-jetbrains-mono-nerd             # Font terminal

    # Electron (pour wpe-manager)
    electron

    # Outils divers
    wl-clip-persist                     # Persist clipboard après fermeture appli
    cliphist                            # Historique presse-papier
    jq                                  # JSON CLI (scripts quickshell)
    geoclue                             # Géolocalisation (météo bar)
    hyprshade                           # Filtres couleur Hyprland
    hyprsunset                          # Night light
)

for pkg in "${EXTRA_PKGS[@]}"; do
    _aur_install "$pkg"
done

ok "Paquets extra installés"

# =============================================================================
# ÉTAPE 5 — DOTFILES
# =============================================================================
section "5/6 — Copie des dotfiles personnalisés"

_backup() {
    local p="$1"
    [[ -e "$p" && ! -L "$p" ]] && mv "$p" "${p}.bak.$(date +%s)" \
        && warn "  Sauvegardé : $p → ${p}.bak.*"
}

# ── ~/.config ─────────────────────────────────────────────────────────────────
for d in hypr kitty quickshell rofi waybar dunst Kvantum wlogout; do
    [[ -d "$CONFIG_SRC/$d" ]] && {
        info "  ~/.config/$d"
        _backup "$HOME/.config/$d"
        cp -r "$CONFIG_SRC/$d" "$HOME/.config/"
    }
done

for d in gtk-3.0 gtk-4.0; do
    [[ -d "$CONFIG_SRC/$d" ]] && {
        info "  ~/.config/$d"
        cp -r "$CONFIG_SRC/$d" "$HOME/.config/"
    }
done

[[ -f "$CONFIG_SRC/gtkrc" ]]     && cp "$CONFIG_SRC/gtkrc"     "$HOME/.config/"
[[ -f "$CONFIG_SRC/gtkrc-2.0" ]] && cp "$CONFIG_SRC/gtkrc-2.0" "$HOME/.config/"

ok "Configs ~/.config copiées"

# ── HyDE ──────────────────────────────────────────────────────────────────────
info "  Config HyDE..."
mkdir -p "$HOME/.config/hyde/themes"

[[ -f "$CONFIG_SRC/hyde-config.toml" ]] \
    && cp "$CONFIG_SRC/hyde-config.toml" "$HOME/.config/hyde/config.toml"

[[ -d "$CONFIG_SRC/hyde-wallbash" ]] \
    && cp -r "$CONFIG_SRC/hyde-wallbash" "$HOME/.config/hyde/wallbash"

if [[ -d "$CONFIG_SRC/hyde-themes" ]]; then
    for td in "$CONFIG_SRC/hyde-themes/"/*/; do
        tname=$(basename "$td")
        dest="$HOME/.config/hyde/themes/$tname"
        mkdir -p "$dest"
        cp -r "${td}"* "$dest/" 2>/dev/null || true
        info "  Thème HyDE : $tname"
    done
fi

ok "Configs HyDE copiées"

# ── Local state (couleurs Material You violet) ────────────────────────────────
info "  Couleurs Material You..."
mkdir -p "$HOME/.local/state/quickshell/user/generated"
[[ -d "$STATE_SRC/quickshell-generated" ]] \
    && cp "$STATE_SRC/quickshell-generated/"* \
          "$HOME/.local/state/quickshell/user/generated/" 2>/dev/null || true

# ── Local share HyDE ──────────────────────────────────────────────────────────
[[ -d "$SHARE_SRC/hyde" ]] && {
    info "  ~/.local/share/hyde..."
    mkdir -p "$HOME/.local/share/hyde"
    cp -r "$SHARE_SRC/hyde/"* "$HOME/.local/share/hyde/" 2>/dev/null || true
}

ok "Données locales copiées"

# ── wpe-manager ───────────────────────────────────────────────────────────────
if [[ -d "$APPS_SRC/wpe-manager" ]]; then
    info "  wpe-manager → ~/wpe-manager"
    _backup "$HOME/wpe-manager"
    cp -r "$APPS_SRC/wpe-manager" "$HOME/wpe-manager"
    chmod +x "$HOME/wpe-manager/launch.sh" 2>/dev/null || true
    ok "wpe-manager installé"
fi

# =============================================================================
# ÉTAPE 6 — CONFIGURATION SYSTÈME
# =============================================================================
section "6/6 — Configuration système"

# ── SDDM ──────────────────────────────────────────────────────────────────────
info "SDDM — thème Candy..."
sudo mkdir -p /etc/sddm.conf.d/
sudo tee /etc/sddm.conf.d/10-trinity.conf > /dev/null << 'EOF'
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=Candy

[Users]
MaximumUid=60513
MinimumUid=1000
EOF

if [[ ! -d /usr/share/sddm/themes/Candy ]]; then
    warn "Thème SDDM Candy absent — HyDE aurait dû l'installer."
    warn "Lance : hyde-install ou réinstalle HyDE si SDDM ne démarre pas."
    sudo sed -i 's/^Current=Candy/Current=/' /etc/sddm.conf.d/10-trinity.conf
fi

sudo systemctl enable sddm 2>/dev/null || true
ok "SDDM configuré"

# ── Fish shell par défaut ─────────────────────────────────────────────────────
FISH_BIN="$(command -v fish 2>/dev/null || true)"
if [[ -n "$FISH_BIN" ]]; then
    grep -qF "$FISH_BIN" /etc/shells || echo "$FISH_BIN" | sudo tee -a /etc/shells
    chsh -s "$FISH_BIN" "$USER"
    ok "Fish défini comme shell par défaut"
else
    warn "fish non trouvé — shell par défaut non changé"
fi

# ── Quickshell service ────────────────────────────────────────────────────────
systemctl --user enable --now quickshell.service 2>/dev/null \
    && ok "Service quickshell activé" \
    || warn "Service quickshell non trouvé (sera lancé par Hyprland)"

# ── Permissions exécutables ───────────────────────────────────────────────────
find "$HOME/.config/hypr"      -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$HOME/.config/quickshell" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# ── Couleurs Material You → terminal ─────────────────────────────────────────
info "Application palette violet Material You..."
APPLYCOLOR="$HOME/.config/quickshell/ii/scripts/colors/applycolor.sh"
[[ -f "$APPLYCOLOR" ]] && bash "$APPLYCOLOR" 2>/dev/null && ok "Palette appliquée"

# ── GTK via gsettings ─────────────────────────────────────────────────────────
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
gsettings set org.gnome.desktop.interface gtk-theme    "Catppuccin-Mocha"     2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme   "Tela-circle-dracula"  2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic" 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"           2>/dev/null || true

# ── xdg-user-dirs ─────────────────────────────────────────────────────────────
xdg-user-dirs-update 2>/dev/null || true

# =============================================================================
# RÉSUMÉ
# =============================================================================
section "Installation terminée !"
echo ""
ok "yay installé"
ok "HyDE installé (Hyprland, SDDM Candy, GTK Catppuccin, fonts)"
ok "illogical-impulse installé (quickshell, Bibata, audio, fonts)"
ok "Dotfiles personnalisés appliqués"
ok "wpe-manager installé dans ~/wpe-manager"
ok "SDDM → thème Candy, service activé"
ok "Fish → shell par défaut"
ok "Palette violet Material You active"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║            ACTIONS MANUELLES REQUISES                ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║${NC} ${BOLD}1. Wallpapers vidéo (wpe-manager)${NC}                     ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    Installe Steam + abonne tes wallpapers WE.         ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    Modifie les chemins dans :                         ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    ~/.config/hypr/custom/scripts/                     ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    __restore_video_wallpaper.sh                       ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}                                                        ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC} ${BOLD}2. Wallpapers statiques HyDE${NC}                          ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    ~/.config/hyde/themes/<Thème>/wallpapers/          ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}                                                        ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC} ${BOLD}3. Kernel Zen (optionnel, recommandé gaming)${NC}           ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    sudo pacman -S linux-zen linux-zen-headers         ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    sudo grub-mkconfig -o /boot/grub/grub.cfg          ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}                                                        ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC} ${BOLD}4. NVIDIA (si carte NVIDIA)${NC}                           ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    HyDE détecte et installe nvidia-open-dkms          ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC}    automatiquement. Vérifie /etc/modprobe.d/          ${YELLOW}║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}${BOLD}  ⟹  REDÉMARRE maintenant : sudo reboot${NC}"
echo ""
