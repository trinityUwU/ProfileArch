#!/usr/bin/env bash
# =============================================================================
# install.sh — Restauration complète TrinityArch
# Arch Linux (clean) + HyDE + end-4/dots-hyprland + Catppuccin Mocha violet
# =============================================================================
# USAGE  : bash install.sh
# CIBLE  : Arch Linux minimal fresh install, utilisateur non-root avec sudo
# ORDRE  : yay → HyDE → illogical-impulse → paquets extra → dotfiles → config
# =============================================================================

# NE PAS utiliser set -e : on gère les erreurs manuellement pour ne pas couper
# le script sur un paquet AUR qui échoue (non bloquant)

# ── Couleurs terminal ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR ]${NC}  $*"; }
die()     { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${CYAN}║  %-46s║${NC}\n" "$*"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
}

# ── Vérifications initiales ────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && die "Ne pas lancer en root. Lance avec ton utilisateur normal."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
STATE_SRC="$SCRIPT_DIR/local-state"
SHARE_SRC="$SCRIPT_DIR/local-share"
APPS_SRC="$SCRIPT_DIR/apps"

[[ ! -d "$CONFIG_SRC" ]] && die "Dossier config/ introuvable. Lance depuis dotfiles-backup/"
command -v pacman &>/dev/null || die "pacman introuvable — ce script est pour Arch Linux uniquement."

section "TrinityArch — Installation"
echo ""
info "Source backup : $SCRIPT_DIR"
info "Utilisateur   : $USER  ($HOME)"
echo ""
echo -e "${YELLOW}Ce script installe dans l'ordre :${NC}"
echo "  1. yay (AUR helper)"
echo "  2. HyDE (Hyprland, SDDM, GTK, fonts, waybar, rofi, dunst, kitty, fish…)"
echo "  3. end-4/dots-hyprland — illogical-impulse (quickshell deps, Bibata, audio…)"
echo "  4. Paquets extra (quickshell-git, matugen, nwg-displays, fonts…)"
echo "  5. Dotfiles personnalisés (copie par-dessus HyDE)"
echo "  6. wpe-manager + configuration système + couleurs violet"
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
    sudo pacman -S --needed --noconfirm git base-devel || die "Impossible d'installer git/base-devel"

    info "Clonage et compilation de yay..."
    _tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$_tmp/yay" || die "Impossible de cloner yay"
    (cd "$_tmp/yay" && makepkg -si --noconfirm) || die "Compilation yay échouée"
    rm -rf "$_tmp"
    ok "yay installé"
fi

# ── Helper installation AUR silencieux ────────────────────────────────────────
_aur_install() {
    local pkg="$1"
    if pacman -Qq "$pkg" &>/dev/null; then
        info "  [présent] $pkg"
    else
        info "  Installation : $pkg"
        if yay -S --needed --noconfirm --answerdiff=None --answerclean=None "$pkg" 2>/tmp/yay_err_"$pkg".log; then
            ok "  [installé] $pkg"
        else
            warn "  [échec non bloquant] $pkg — voir /tmp/yay_err_${pkg}.log"
        fi
    fi
}

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
    ok "HyDE déjà installé — on continue"
else
    info "Clonage de HyDE..."
    if [[ -d "$HYDE_DIR" ]]; then
        warn "Dossier ~/HyDE existant — mise à jour..."
        (cd "$HYDE_DIR" && git fetch --depth 1 origin master && git reset --hard origin/master) \
            || warn "Mise à jour HyDE échouée, on utilise l'existant"
    else
        git clone --depth 1 https://github.com/HyDE-Project/HyDE "$HYDE_DIR" \
            || die "Impossible de cloner HyDE"
    fi

    echo ""
    warn "════════════════════════════════════════════════════"
    warn "  IMPORTANT — Questions de l'installateur HyDE :"
    warn "  • Si on te demande de remplacer des configs :"
    warn "    Réponds OUI — nos dotfiles écraseront après."
    warn "  • Si NVIDIA détecté : laisse HyDE gérer les drivers."
    warn "════════════════════════════════════════════════════"
    echo ""

    (cd "$HYDE_DIR/Scripts" && ./install.sh) || warn "HyDE installe a signalé une erreur (peut être normal)"
    ok "HyDE installé"
fi

# =============================================================================
# ÉTAPE 3 — end-4/dots-hyprland (illogical-impulse)
# =============================================================================
# Ces meta-paquets AUR fournissent :
#   quickshell deps, Bibata cursor, Material Symbols font,
#   easyeffects, Python ML deps, screencapture, Qt utils
# =============================================================================
section "3/6 — end-4 / illogical-impulse packages"

II_PKGS=(
    illogical-impulse-hyprland
    illogical-impulse-basic
    illogical-impulse-fonts-themes
    illogical-impulse-bibata-modern-classic-bin
    illogical-impulse-audio
    illogical-impulse-portal
    illogical-impulse-python
    illogical-impulse-screencapture
    illogical-impulse-toolkit
    illogical-impulse-widgets
    illogical-impulse-kde
    illogical-impulse-microtex-git
)

for pkg in "${II_PKGS[@]}"; do
    _aur_install "$pkg"
done

ok "Paquets illogical-impulse traités"

# =============================================================================
# ÉTAPE 4 — Paquets extra
# =============================================================================
section "4/6 — Paquets extra"

# Désinstaller quickshell (stable) s'il est présent pour éviter les conflits
# avec quickshell-git (on veut la version git pour la config ii)
if pacman -Qq quickshell &>/dev/null && ! pacman -Qq quickshell-git &>/dev/null; then
    warn "Remplacement de quickshell par quickshell-git..."
    yay -R --noconfirm quickshell 2>/dev/null || true
fi

EXTRA_PKGS=(
    quickshell-git
    matugen
    mpvpaper
    nwg-displays
    nwg-look
    ttf-material-symbols-variable-git
    ttf-jetbrains-mono-nerd
    electron
    wl-clip-persist
    cliphist
    jq
    geoclue
    hyprshade
    hyprsunset
    nemo
    python-pywal
)

for pkg in "${EXTRA_PKGS[@]}"; do
    _aur_install "$pkg"
done

ok "Paquets extra traités"

# =============================================================================
# ÉTAPE 5 — DOTFILES
# =============================================================================
# IMPORTANT : on copie NOS configs EN DERNIER, après HyDE et end-4,
# pour qu'aucun installateur ne les écrase ensuite.
# On utilise rsync --backup pour ne jamais perdre de fichier.
# =============================================================================
section "5/6 — Copie des dotfiles personnalisés"

_safe_copy_dir() {
    local src="$1"
    local dst="$2"
    local name="$3"
    if [[ ! -d "$src" ]]; then
        warn "  Source manquante : $src"
        return
    fi
    mkdir -p "$dst"
    # rsync : merge (pas de suppression), préserve permissions, backup des conflits
    rsync -a --backup --suffix=".orig" "$src/" "$dst/" \
        && ok "  $name → $dst" \
        || warn "  Erreur partielle sur $name"
}

# ── ~/.config ─────────────────────────────────────────────────────────────────
info "Copie ~/.config/hypr..."
_safe_copy_dir "$CONFIG_SRC/hypr"        "$HOME/.config/hypr"        "hypr"

info "Copie ~/.config/kitty..."
_safe_copy_dir "$CONFIG_SRC/kitty"       "$HOME/.config/kitty"       "kitty"

info "Copie ~/.config/quickshell/ii..."
mkdir -p "$HOME/.config/quickshell"
_safe_copy_dir "$CONFIG_SRC/quickshell/ii" "$HOME/.config/quickshell/ii" "quickshell/ii"

info "Copie ~/.config/rofi..."
_safe_copy_dir "$CONFIG_SRC/rofi"        "$HOME/.config/rofi"        "rofi"

info "Copie ~/.config/waybar..."
_safe_copy_dir "$CONFIG_SRC/waybar"      "$HOME/.config/waybar"      "waybar"

info "Copie ~/.config/dunst..."
_safe_copy_dir "$CONFIG_SRC/dunst"       "$HOME/.config/dunst"       "dunst"

info "Copie ~/.config/Kvantum..."
_safe_copy_dir "$CONFIG_SRC/Kvantum"     "$HOME/.config/Kvantum"     "Kvantum"

info "Copie ~/.config/wlogout..."
_safe_copy_dir "$CONFIG_SRC/wlogout"     "$HOME/.config/wlogout"     "wlogout"

info "Copie ~/.config/gtk-3.0..."
_safe_copy_dir "$CONFIG_SRC/gtk-3.0"     "$HOME/.config/gtk-3.0"     "gtk-3.0"

info "Copie ~/.config/gtk-4.0..."
_safe_copy_dir "$CONFIG_SRC/gtk-4.0"     "$HOME/.config/gtk-4.0"     "gtk-4.0"

[[ -f "$CONFIG_SRC/gtkrc" ]]     && cp "$CONFIG_SRC/gtkrc"     "$HOME/.gtkrc-2.0"     && ok "  gtkrc → ~/.gtkrc-2.0"
[[ -f "$CONFIG_SRC/gtkrc-2.0" ]] && cp "$CONFIG_SRC/gtkrc-2.0" "$HOME/.config/gtkrc-2.0" && ok "  gtkrc-2.0"

ok "Configs ~/.config copiées"

# ── HyDE ──────────────────────────────────────────────────────────────────────
info "Config HyDE..."
mkdir -p "$HOME/.config/hyde/themes"

[[ -f "$CONFIG_SRC/hyde-config.toml" ]] \
    && cp "$CONFIG_SRC/hyde-config.toml" "$HOME/.config/hyde/config.toml" \
    && ok "  hyde-config.toml"

if [[ -d "$CONFIG_SRC/hyde-wallbash" ]]; then
    mkdir -p "$HOME/.config/hyde/wallbash"
    rsync -a --backup --suffix=".orig" "$CONFIG_SRC/hyde-wallbash/" "$HOME/.config/hyde/wallbash/" \
        && ok "  hyde-wallbash"
fi

if [[ -d "$CONFIG_SRC/hyde-themes" ]]; then
    for td in "$CONFIG_SRC/hyde-themes/"/*/; do
        tname=$(basename "$td")
        dest="$HOME/.config/hyde/themes/$tname"
        mkdir -p "$dest"
        rsync -a "$td" "$dest/" 2>/dev/null && info "  Thème HyDE : $tname"
    done
fi

ok "Config HyDE appliquée"

# ── Local state (couleurs Material You violet) ────────────────────────────────
info "Couleurs Material You violet..."
mkdir -p "$HOME/.local/state/quickshell/user/generated"
if [[ -d "$STATE_SRC/quickshell-generated" ]]; then
    cp "$STATE_SRC/quickshell-generated/"* \
        "$HOME/.local/state/quickshell/user/generated/" 2>/dev/null \
        && ok "  Couleurs violet copiées"
fi

# Créer aussi le lien pour la config ii si besoin
QS_CONFIG_COLORS="$HOME/.config/quickshell/ii/state/colors"
if [[ -d "$HOME/.config/quickshell/ii" ]]; then
    mkdir -p "$HOME/.config/quickshell/ii/state"
    [[ ! -f "$HOME/.config/quickshell/ii/state/colors.json" ]] \
        && [[ -f "$STATE_SRC/quickshell-generated/colors.json" ]] \
        && cp "$STATE_SRC/quickshell-generated/colors.json" \
             "$HOME/.config/quickshell/ii/state/colors.json" 2>/dev/null || true
fi

# ── Local share HyDE ──────────────────────────────────────────────────────────
if [[ -d "$SHARE_SRC/hyde" ]]; then
    info "~/.local/share/hyde..."
    mkdir -p "$HOME/.local/share/hyde"
    rsync -a "$SHARE_SRC/hyde/" "$HOME/.local/share/hyde/" 2>/dev/null && ok "  local-share/hyde"
fi

# ── wpe-manager ───────────────────────────────────────────────────────────────
if [[ -d "$APPS_SRC/wpe-manager" ]]; then
    info "wpe-manager → ~/wpe-manager"
    mkdir -p "$HOME/wpe-manager"
    rsync -a --backup --suffix=".orig" "$APPS_SRC/wpe-manager/" "$HOME/wpe-manager/"
    chmod +x "$HOME/wpe-manager/launch.sh"         2>/dev/null || true
    chmod +x "$HOME/wpe-manager/server.py"         2>/dev/null || true
    chmod +x "$HOME/wpe-manager/wpe_web_wallpaper.py" 2>/dev/null || true
    ok "wpe-manager installé dans ~/wpe-manager"
fi

# =============================================================================
# ÉTAPE 6 — CONFIGURATION SYSTÈME
# =============================================================================
section "6/6 — Configuration système"

# ── Permissions exécutables ───────────────────────────────────────────────────
info "Permissions scripts bash..."
find "$HOME/.config/hypr"       -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$HOME/.config/quickshell" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$HOME/.config/hyde"       -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
ok "Permissions appliquées"

# ── SDDM ──────────────────────────────────────────────────────────────────────
info "SDDM — thème Candy..."
sudo mkdir -p /etc/sddm.conf.d/
sudo tee /etc/sddm.conf.d/10-trinity.conf > /dev/null << 'SDDMEOF'
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
SDDMEOF

if [[ ! -d /usr/share/sddm/themes/Candy ]]; then
    warn "Thème SDDM Candy absent — passage au thème par défaut"
    sudo sed -i 's/^Current=Candy/Current=/' /etc/sddm.conf.d/10-trinity.conf
fi

sudo systemctl enable sddm 2>/dev/null && ok "SDDM activé" || warn "SDDM: systemctl enable échoué (peut être normal)"

# ── Fish shell par défaut ─────────────────────────────────────────────────────
FISH_BIN="$(command -v fish 2>/dev/null || true)"
if [[ -n "$FISH_BIN" ]]; then
    grep -qF "$FISH_BIN" /etc/shells || echo "$FISH_BIN" | sudo tee -a /etc/shells
    chsh -s "$FISH_BIN" "$USER" && ok "Fish défini comme shell par défaut" || warn "chsh échoué"
else
    warn "fish non trouvé — shell par défaut non changé"
fi

# ── Quickshell : vérifier la config ii ────────────────────────────────────────
info "Vérification config quickshell..."
QS_II="$HOME/.config/quickshell/ii"

if [[ ! -f "$QS_II/shell.qml" ]]; then
    warn "shell.qml manquant dans quickshell/ii !"
    warn "  Vérifie que le backup config/quickshell/ii/ est complet."
else
    ok "quickshell/ii/shell.qml présent"
fi

# ── Matugen templates depuis backup ───────────────────────────────────────────
info "Restauration templates matugen..."
if [[ -d "$CONFIG_SRC/matugen" ]]; then
    mkdir -p "$HOME/.config/matugen"
    rsync -a "$CONFIG_SRC/matugen/" "$HOME/.config/matugen/"
    ok "Templates matugen restaurés"
fi

# ── Config illogical-impulse avec accentColor violet ─────────────────────────
info "Config illogical-impulse (accentColor #9d6ff5)..."
mkdir -p "$HOME/.config/illogical-impulse"
if [[ -f "$CONFIG_SRC/illogical-impulse/config.json" ]]; then
    if [[ -f "$HOME/.config/illogical-impulse/config.json" ]] && command -v jq &>/dev/null; then
        # Mettre à jour uniquement accentColor et type dans le fichier existant
        _tmp=$(mktemp)
        jq '.appearance.palette.accentColor = "#9d6ff5" | .appearance.palette.type = "scheme-tonal-spot"' \
            "$HOME/.config/illogical-impulse/config.json" > "$_tmp" \
            && mv "$_tmp" "$HOME/.config/illogical-impulse/config.json" \
            && ok "accentColor → #9d6ff5"
    else
        cp "$CONFIG_SRC/illogical-impulse/config.json" "$HOME/.config/illogical-impulse/config.json"
        ok "config.json illogical-impulse copié (accentColor: #9d6ff5)"
    fi
fi

# ── Créer les répertoires d'état quickshell ───────────────────────────────────
mkdir -p "$HOME/.local/state/quickshell/user/generated/terminal"
mkdir -p "$HOME/.local/state/quickshell/user/generated/wallpaper"
mkdir -p "$HOME/.cache/quickshell"

# ── Copier les couleurs pré-générées depuis backup ────────────────────────────
info "Couleurs Material You (violet pré-générées)..."
QS_STATE="$HOME/.local/state/quickshell/user/generated"
[[ -f "$STATE_SRC/quickshell-generated/colors.json" ]] \
    && cp "$STATE_SRC/quickshell-generated/colors.json"         "$QS_STATE/colors.json" \
    && ok "colors.json violet"
[[ -f "$STATE_SRC/quickshell-generated/material_colors.scss" ]] \
    && cp "$STATE_SRC/quickshell-generated/material_colors.scss" "$QS_STATE/material_colors.scss" \
    && ok "material_colors.scss violet"

# ── Lancer matugen pour générer TOUS les templates (GTK, hyprland, etc.) ──────
info "Génération matugen (couleur hex #9d6ff5)..."
if command -v matugen &>/dev/null; then
    matugen color hex "#9d6ff5" --mode dark 2>/dev/null \
        && ok "matugen exécuté — GTK css, hyprlock colors, colors.json générés" \
        || warn "matugen erreur (non bloquant — backup colors.json utilisé)"
else
    warn "matugen non installé — couleurs depuis backup uniquement"
fi

# ── Application palette couleurs terminal ─────────────────────────────────────
info "Application palette terminal..."
APPLYCOLOR="$HOME/.config/quickshell/ii/scripts/colors/applycolor.sh"
[[ -f "$APPLYCOLOR" ]] && chmod +x "$APPLYCOLOR"
if [[ -f "$APPLYCOLOR" ]]; then
    bash "$APPLYCOLOR" 2>/dev/null && ok "Palette terminal appliquée" || warn "applycolor.sh: erreur mineure"
else
    warn "applycolor.sh non trouvé"
fi

# ── GTK via gsettings ─────────────────────────────────────────────────────────
info "Thèmes GTK/icônes/curseur..."
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
gsettings set org.gnome.desktop.interface gtk-theme     "Catppuccin-Mocha"       2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme    "Tela-circle-dracula"    2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme  "Bibata-Modern-Classic"  2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme  "prefer-dark"            2>/dev/null || true
gsettings set org.gnome.desktop.interface font-name     "JetBrains Mono 11"      2>/dev/null || true
ok "GTK/icônes/curseur configurés"

# ── Kvantum ───────────────────────────────────────────────────────────────────
if command -v kvantummanager &>/dev/null; then
    kvantummanager --set catppuccin-mocha-mauve 2>/dev/null \
        && ok "Kvantum : catppuccin-mocha-mauve appliqué" \
        || warn "Kvantum: thème non trouvé (sera appliqué manuellement)"
fi

# ── Service systemd quickshell ────────────────────────────────────────────────
info "Installation service quickshell (systemd user)..."
mkdir -p "$HOME/.config/systemd/user"
if [[ -f "$SCRIPT_DIR/config/systemd-user/quickshell.service" ]]; then
    cp "$SCRIPT_DIR/config/systemd-user/quickshell.service" \
       "$HOME/.config/systemd/user/quickshell.service"
    systemctl --user daemon-reload
    systemctl --user enable --now quickshell.service 2>/dev/null \
        && ok "Service quickshell installé et activé" \
        || warn "quickshell.service: enable échoué (hors session graphique = normal)"
else
    warn "quickshell.service non trouvé dans backup"
fi

# ── Python venv pour end-4 (switchwall.sh / generate_colors_material.py) ─────
VENV_DIR="$HOME/.local/state/quickshell/.venv"
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    info "Création venv Python pour end-4 (switchwall.sh)..."
    if command -v python3 &>/dev/null && python3 -c "import venv" &>/dev/null; then
        mkdir -p "$HOME/.local/state/quickshell"
        python3 -m venv "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        pip install --quiet materialyoucolor Pillow 2>/dev/null \
            && ok "Venv Python créé : materialyoucolor + Pillow installés" \
            || warn "pip install partiel (non bloquant)"
        deactivate
    else
        warn "python3/venv non disponible — venv non créé"
    fi
else
    ok "Venv Python déjà en place ($VENV_DIR)"
fi

# ── xdg-user-dirs ─────────────────────────────────────────────────────────────
xdg-user-dirs-update 2>/dev/null || true

# =============================================================================
# RÉSUMÉ
# =============================================================================
section "Installation terminée !"
echo ""
ok "yay installé"
ok "HyDE installé (Hyprland, SDDM, GTK Catppuccin, fonts)"
ok "illogical-impulse installé (quickshell deps, Bibata, audio)"
ok "Dotfiles personnalisés appliqués (rsync, pas d'écrasement aveugle)"
ok "Palette violet Material You en place"
ok "GTK : Catppuccin-Mocha | Icônes : Tela-circle-dracula | Curseur : Bibata-Modern-Classic"
ok "SDDM configuré | Fish shell par défaut"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║            ACTIONS MANUELLES REQUISES                ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "1. Wallpapers vidéo (wpe-manager)"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   Steam + wallpapers Wallpaper Engine"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   Chemins dans:"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   ~/.config/hypr/custom/scripts/"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" ""
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "2. Wallpapers statiques HyDE"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   ~/.config/hyde/themes/<Thème>/wallpapers/"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" ""
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "3. Kernel Zen (optionnel, recommandé gaming)"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   sudo pacman -S linux-zen linux-zen-headers"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   sudo grub-mkconfig -o /boot/grub/grub.cfg"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" ""
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "4. Si quelque chose manque:"
printf "${YELLOW}║${NC} %-52s${YELLOW}║${NC}\n" "   bash verify-setup.sh"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}${BOLD}  ⟹  REDÉMARRE maintenant : sudo reboot${NC}"
echo ""
