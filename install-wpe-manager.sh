#!/usr/bin/env bash
# =============================================================================
# install-wpe-manager.sh — Installation complète WPE Manager (Wallpaper Engine)
# =============================================================================
# USAGE  : bash install-wpe-manager.sh [--skip-deps] [--deps-only]
# REPO   : copie apps/wpe-manager → ~/wpe-manager, deps Arch, conf, .desktop
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/apps/wpe-manager"
DEST="${WPE_INSTALL_DIR:-$HOME/wpe-manager}"

SKIP_DEPS=0
DEPS_ONLY=0
for a in "$@"; do
    case "$a" in
        --skip-deps) SKIP_DEPS=1 ;;
        --deps-only) DEPS_ONLY=1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERR ]${NC}  $*"; }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ $* ═══${NC}"
}

[[ ! -d "$SRC" ]] && { err "Introuvable : $SRC (lance depuis la racine ProfileArch)"; exit 1; }

# ── Paquets (Arch) ──────────────────────────────────────────────────────────
section "Paquets système"

PACMAN_PKGS=(
    python
    mpvpaper
    ffmpeg
    electron
    gtk3
    webkit2gtk
    python-gobject
    libnotify
)

AUR_PKGS_OPTIONAL=(
    linux-wallpaperengine-git
)

if [[ "$SKIP_DEPS" -eq 0 ]]; then
    if ! command -v pacman &>/dev/null; then
        err "pacman introuvable — ce script cible Arch Linux."
        exit 1
    fi
    info "Installation pacman : ${PACMAN_PKGS[*]}"
    sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}" || {
        warn "Certains paquets pacman ont échoué — installe-les manuellement."
    }
    ok "Paquets pacman"

    if command -v yay &>/dev/null; then
        if [[ -n "${WPE_NONINTERACTIVE:-}" ]] || ! [[ -t 0 ]]; then
            info "Mode non-interactif : linux-wallpaperengine non installé (yay -S linux-wallpaperengine-git si besoin)"
        else
            read -rp "$(echo -e "${BOLD}Installer linux-wallpaperengine-git (scenes WE, AUR) ? [o/N] ${NC}")" lwe
            if [[ "$lwe" =~ ^[oOyY]$ ]]; then
                yay -S --needed --noconfirm linux-wallpaperengine-git && ok "linux-wallpaperengine-git" || warn "Échec AUR linux-wallpaperengine-git"
            else
                info "linux-wallpaperengine ignoré (scenes non animées sans LWE)"
            fi
        fi
    else
        warn "yay absent — pour les scenes : yay -S linux-wallpaperengine-git"
    fi
else
    info "--skip-deps : paquets non installés"
fi

[[ "$DEPS_ONLY" -eq 1 ]] && { ok "Fin (--deps-only)"; exit 0; }

# ── Copie application ─────────────────────────────────────────────────────────
section "Application → $DEST"

mkdir -p "$DEST"
# Pas de --delete : on ne supprime pas les fichiers locaux éventuels dans ~/wpe-manager
rsync -a --exclude '.git' "$SRC/" "$DEST/"
chmod +x "$DEST/launch.sh" "$DEST/server.py" "$DEST/wpe_web_wallpaper.py" 2>/dev/null || true
chmod +x "$DEST/__restore_video_wallpaper.sh" 2>/dev/null || true
ok "Fichiers synchronisés"

# ── Répertoire scripts Hyprland ───────────────────────────────────────────────
HYPR_SCRIPTS="$HOME/.config/hypr/custom/scripts"
mkdir -p "$HYPR_SCRIPTS"
RESTORE="$HYPR_SCRIPTS/__restore_video_wallpaper.sh"
if [[ ! -f "$RESTORE" ]]; then
    cp -a "$DEST/__restore_video_wallpaper.sh" "$RESTORE"
    chmod +x "$RESTORE"
    ok "Script restauration Hyprland : $RESTORE"
else
    info "Conservé : $RESTORE (déjà présent — WPE le régénère à l’appliqué)"
fi

# ── wallpaperengine_screens.conf ─────────────────────────────────────────────
section "Configuration écrans"

CONF="$HOME/.config/wallpaperengine_screens.conf"
generate_conf() {
    local lines=()
    lines+=("# Généré par install-wpe-manager.sh — NOM_ECRAN=workshop_id")
    lines+=("# Steam WE : ~/.local/share/Steam/steamapps/workshop/content/431960/")
    if command -v hyprctl &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        mapfile -t MONS < <(hyprctl monitors -j 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for m in d:
        n=m.get('name')
        if n: print(n)
except Exception:
    pass
" 2>/dev/null)
        if [[ ${#MONS[@]} -gt 0 ]]; then
            for m in "${MONS[@]}"; do
                lines+=("${m}=")
            done
        else
            lines+=("DP-1=")
            lines+=("HDMI-A-1=")
        fi
    else
        lines+=("DP-1=")
        lines+=("HDMI-A-1=")
        info "Hors session Hyprland — modèle DP-1 / HDMI-A-1 (édite si besoin)"
    fi
    printf '%s\n' "${lines[@]}" > "$CONF"
}

if [[ -f "$CONF" ]]; then
    warn "$CONF existe déjà — non écrasé (édite à la main ou supprime pour régénérer)"
else
    generate_conf
    ok "$CONF créé"
fi

# ── Raccourci bureau ─────────────────────────────────────────────────────────
section "Lanceur applications"

APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
ELECTRON_BIN="$(command -v electron 2>/dev/null || echo /usr/bin/electron)"
cat > "$APP_DIR/wpe-manager.desktop" << DESKEOF
[Desktop Entry]
Name=WPE Manager
Name[fr]=WPE Manager
Comment=Wallpaper Engine (Steam) — Hyprland
Exec=$ELECTRON_BIN $DEST/electron/main.js --no-sandbox
Icon=$DEST/electron/icon.png
Terminal=false
Type=Application
Categories=Utility;AudioVideo;
StartupNotify=true
DESKEOF
ok "$APP_DIR/wpe-manager.desktop"

# ── Vérifs ───────────────────────────────────────────────────────────────────
section "Vérifications"

command -v python3 &>/dev/null && ok "python3" || err "python3 manquant"
command -v mpvpaper &>/dev/null && ok "mpvpaper" || err "mpvpaper manquant"
[[ -x "$ELECTRON_BIN" ]] || [[ -f "$ELECTRON_BIN" ]] && ok "electron : $ELECTRON_BIN" || err "electron manquant (pacman -S electron)"
python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk, WebKit2" 2>/dev/null && ok "PyGObject + WebKit (fonds HTML)" || warn "WebKit GTK : installe webkit2gtk + python-gobject pour les fonds HTML"

STEAM_WE="$HOME/.local/share/Steam/steamapps/workshop/content/431960"
if [[ -d "$STEAM_WE" ]]; then
    ok "Dossier workshop WE présent ($(find "$STEAM_WE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) abonnement(s) visible(s))"
else
    warn "Dossier Steam WE absent — installe Steam, WE, et abonne-toi à des fonds"
fi

echo ""
echo -e "${GREEN}${BOLD}Installation WPE Manager terminée.${NC}"
echo ""
echo "  Démarrage : $ELECTRON_BIN $DEST/electron/main.js --no-sandbox"
echo "  Ou depuis le menu : WPE Manager"
echo "  Web UI     : http://localhost:6969"
echo "  Doc        : $DEST/README.md"
echo ""
