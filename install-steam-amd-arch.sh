#!/usr/bin/env bash
# =============================================================================
# install-steam-amd-arch.sh — Steam sur Arch Linux + GPU AMD (Mesa / RADV)
# =============================================================================
# USAGE  : bash install-steam-amd-arch.sh [options]
#   --diagnose-only      : rien n’installe
#   --non-interactive    : pas de questions (multilib auto, pas gamemode)
#   --with-aur-native    : tente yay/paru pour steam-native-runtime (AUR)
# Crash silencieux typique : [multilib] désactivé, lib32-mesa / Vulkan 32 bits,
# runtime Valve / pressure-vessel (bubblewrap, userns), libs mélangées, webhelper.
# Wayland/Hyprland : SDL_VIDEODRIVER=wayland seul → warning Steam puis segfault possible ;
# locale en_US.UTF-8 manquante → setlocale failed. Ne pas lancer 2× steam pendant l’install.
# Doc Arch : https://wiki.archlinux.org/title/Steam
# Runtime  : https://wiki.archlinux.org/title/Steam/Troubleshooting#Steam_runtime
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root. Utilise ton utilisateur (sudo sera demandé)."; exit 1; }

DIAG_ONLY=0
NON_INTERACTIVE=0
WITH_AUR_NATIVE=0
for a in "$@"; do
    case "$a" in
        --diagnose-only) DIAG_ONLY=1 ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        --with-aur-native) WITH_AUR_NATIVE=1 ;;
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
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
}

# ── Diagnostic (utilisable sans sudo, sans multilib) ─────────────────────────
_diagnose() {
    echo "--- GPU (noyau / module) ---"
    if command -v lspci &>/dev/null; then
        lspci -k | grep -A3 -E 'VGA|3D|Display' || true
    else
        warn "lspci absent (paquet pciutils)"
    fi
    echo ""
    echo "--- Versions Mesa (doivent être identiques ou très proches) ---"
    pacman -Q mesa lib32-mesa 2>/dev/null || warn "mesa ou lib32-mesa non installé"
    echo ""
    echo "--- DRI 64 bits ---"
    ls /usr/lib/dri/radeonsi_dri.so /usr/lib/dri/swrast_dri.so 2>/dev/null || warn "DRI 64 bits incomplet"
    echo ""
    echo "--- DRI 32 bits (obligatoire pour Steam) ---"
    if [[ -d /usr/lib32/dri ]]; then
        ls /usr/lib32/dri/radeonsi_dri.so /usr/lib32/dri/swrast_dri.so 2>/dev/null \
            || warn "Installe lib32-mesa et active [multilib]"
    else
        err "/usr/lib32/dri absent → active [multilib] dans /etc/pacman.conf puis : sudo pacman -Syu lib32-mesa"
    fi
    echo ""
    echo "--- ICD Vulkan (RADV / AMD) ---"
    ls -1 /usr/share/vulkan/icd.d/*radeon* 2>/dev/null || true
    ls -1 /usr/share/vulkan/icd.d/*lvp* 2>/dev/null || true
    echo ""
    if command -v vulkaninfo &>/dev/null; then
        echo "--- vulkaninfo --summary (extrait) ---"
        vulkaninfo --summary 2>/dev/null | head -30 || warn "vulkaninfo a échoué"
    else
        info "Pour plus de détail : sudo pacman -S vulkan-tools && vulkaninfo"
    fi
    echo ""
    echo "--- binaire steam ---"
    if command -v steam &>/dev/null; then
        ls -la "$(command -v steam)"
    else
        warn "steam pas dans PATH (paquet multilib/steam)"
    fi
    echo ""
    echo "--- derniers journaux Steam (si présents) ---"
    for d in "$HOME/.steam/steam/logs" "$HOME/.local/share/Steam/logs"; do
        if [[ -d "$d" ]]; then
            echo ">>> $d"
            ls -lt "$d" 2>/dev/null | head -5
        fi
    done
    echo ""
    echo "--- Runtime Steam (répertoire scout / scripts) ---"
    if [[ -d "$HOME/.steam/root/ubuntu12_32" ]]; then
        ls "$HOME/.steam/root/ubuntu12_32"/steam-runtime* 2>/dev/null | head -3 || true
        ls "$HOME/.steam/root/ubuntu12_32"/steam.sh 2>/dev/null || true
    else
        warn "~/.steam/root/ubuntu12_32 absent (Steam pas encore lancé ou install cassée)"
    fi
    echo ""
    echo "--- pressure-vessel / conteneurs (user namespaces) ---"
    if command -v bubblewrap &>/dev/null; then
        ok "bubblewrap : $(command -v bubblewrap) ($(pacman -Q bubblewrap 2>/dev/null || echo '?'))"
    else
        warn "bubblewrap absent — installe le paquet bubblewrap (requis pour Steam Linux Runtime / Proton)"
    fi
    if [[ -r /proc/sys/kernel/unprivileged_userns_clone ]]; then
        userns="$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo '?')"
        if [[ "$userns" == "0" ]]; then
            err "kernel.unprivileged_userns_clone=0 — pressure-vessel peut échouer (linux-hardened ?). Voir wiki Steam-runtime / bubblewrap-suid ou passer ce sysctl à 1."
        else
            ok "kernel.unprivileged_userns_clone=$userns"
        fi
    fi
    if [[ "$(uname -r)" == *hardened* ]]; then
        warn "Noyau « hardened » : vérifier bubblewrap + userns (doc steam-runtime Valve)"
    fi
    echo ""
    echo "--- steam-native (contournement runtime système) ---"
    if command -v steam-native &>/dev/null; then
        ok "steam-native trouvé : $(command -v steam-native) (paquet steam-native-runtime AUR)"
    else
        info "Pas de steam-native — lanceur ~/.local/bin/steam-amd-native utilise STEAM_RUNTIME=0 (sans AUR si besoin)"
    fi
    echo ""
    echo "--- Locale (Steam teste en_US.UTF-8 au boot) ---"
    locale 2>/dev/null | grep -E 'LANG=|LC_' | head -5 || true
    if locale -a 2>/dev/null | grep -qiE '^en_US\.(utf8|UTF-8)$'; then
        ok "locale en_US.UTF-8 disponible (locale -a)"
    else
        warn "en_US.UTF-8 absent — sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && sudo locale-gen"
    fi
    echo ""
    echo "--- SDL_VIDEODRIVER (session / shell) ---"
    echo "    SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-<non défini>}"
    echo "    (Hyprland ne doit pas forcer « wayland » seul pour Steam — voir hyprland.conf)"
    echo ""
    echo "--- stdout Steam (wrapper Arch redirige vers /tmp/dumps) ---"
    shopt -s nullglob
    for f in /tmp/dumps/*_stdout.txt; do
        echo ">>> $f (dernières lignes)"
        tail -8 "$f" 2>/dev/null || true
    done
    shopt -u nullglob
}

if ! command -v pacman &>/dev/null; then
    err "pacman introuvable — ce script est pour Arch Linux."
    exit 1
fi

if [[ "$DIAG_ONLY" -eq 1 ]]; then
    section "Diagnostic uniquement (--diagnose-only)"
    _diagnose
    exit 0
fi

# ── Multilib ─────────────────────────────────────────────────────────────────
section "Dépôt [multilib] (libs 32 bits)"

_multilib_enabled() {
    grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null \
        && grep -A2 '^\[multilib\]' /etc/pacman.conf | grep -q '^Include'
}

if _multilib_enabled; then
    ok "multilib actif"
else
    warn "multilib désactivé — Steam ne peut pas fonctionner correctement sans lib32-*"
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        # Méthode Arch Wiki : décommente le bloc [multilib]
        sudo cp -a /etc/pacman.conf /etc/pacman.conf.bak.steam-amd."$(date +%s)"
        sudo sed -i '/\[multilib\]/,/Include/s/^#//g' /etc/pacman.conf
        if _multilib_enabled; then
            ok "multilib activé automatiquement (--non-interactive)"
            sudo pacman -Sy
        else
            err "Impossible d’activer multilib automatiquement — édite /etc/pacman.conf"
            exit 1
        fi
    else
        echo ""
        echo -e "${BOLD}Commande recommandée (Arch Wiki) :${NC}"
        echo "  sudo sed -i '/\\[multilib\\]/,/Include/s/^#//g' /etc/pacman.conf"
        echo ""
        read -rp "$(echo -e "${BOLD}Activer multilib automatiquement ? [o/N] ${NC}")" ans
        if [[ "$ans" =~ ^[oOyY]$ ]]; then
            sudo cp -a /etc/pacman.conf /etc/pacman.conf.bak.steam-amd."$(date +%s)"
            sudo sed -i '/\[multilib\]/,/Include/s/^#//g' /etc/pacman.conf
            if _multilib_enabled; then
                ok "multilib activé"
                sudo pacman -Sy
            else
                err "Échec — ouvre /etc/pacman.conf et décommente [multilib] + Include = .../mirrorlist"
                exit 1
            fi
        else
            exit 1
        fi
    fi
fi

# ── Paquets ───────────────────────────────────────────────────────────────────
section "Paquets : firmware + Mesa/Vulkan AMD + Steam"

# Le méta-paquet steam tire la plupart des lib32 ; on force l’empilement graphique AMD.
CORE_PKGS=(
    linux-firmware
    bubblewrap
    mesa
    lib32-mesa
    vulkan-radeon
    lib32-vulkan-radeon
    vulkan-icd-loader
    lib32-vulkan-icd-loader
    steam
)

EXTRA_PKGS=(
    vulkan-mesa-layers
    lib32-vulkan-mesa-layers
    vulkan-tools
    lib32-mesa-utils
    lib32-sdl2
)

info "Cœur : ${CORE_PKGS[*]}"
sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}" || {
    err "Installation échouée — vérifie multilib + miroirs."
    exit 1
}
ok "Paquets cœur installés"

info "Extras (layers, vulkaninfo, mesa-utils 32)…"
sudo pacman -S --needed --noconfirm "${EXTRA_PKGS[@]}" 2>/dev/null || warn "Certains extras indisponibles — non bloquant"

if ! locale -a 2>/dev/null | grep -qiE '^en_US\.(utf8|UTF-8)$'; then
    warn "Steam signale souvent « setlocale(en_US.UTF-8) failed » sans cette locale."
    warn "Corriger : sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && sudo locale-gen"
fi

if [[ "$NON_INTERACTIVE" -ne 1 ]]; then
    read -rp "$(echo -e "${BOLD}Installer gamemode + mangohud ? [o/N] ${NC}")" gm
    if [[ "$gm" =~ ^[oOyY]$ ]]; then
        sudo pacman -S --needed --noconfirm gamemode lib32-gamemode mangohud 2>/dev/null || warn "Optionnels partiels"
    fi
fi

_aur_install_steam_native_runtime() {
    if command -v paru &>/dev/null; then
        paru -S --needed --noconfirm steam-native-runtime
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm steam-native-runtime
    else
        err "yay ou paru introuvable — installe steam-native-runtime depuis l’AUR à la main."
        return 1
    fi
}

if [[ "$WITH_AUR_NATIVE" -eq 1 ]]; then
    section "AUR : steam-native-runtime (libs système à la place du runtime Valve)"
    _aur_install_steam_native_runtime && ok "steam-native-runtime installé" || warn "Échec AUR — utilise steam-amd-native sans le méta-paquet AUR"
elif [[ "$NON_INTERACTIVE" -ne 1 ]]; then
    read -rp "$(echo -e "${BOLD}Installer steam-native-runtime depuis l’AUR (yay/paru) ? [o/N] ${NC}")" aurn
    if [[ "$aurn" =~ ^[oOyY]$ ]]; then
        section "AUR : steam-native-runtime"
        _aur_install_steam_native_runtime && ok "steam-native-runtime installé" || warn "Échec AUR"
    fi
fi

# ── Lanceurs + journal (plus de crash « silencieux ») ─────────────────────────
section "Lanceurs Steam (AMD) + fichier log"

LAUNCHER="$HOME/.local/bin/steam-amd"
LAUNCHER_NATIVE="$HOME/.local/bin/steam-amd-native"
mkdir -p "$HOME/.local/bin"
cat > "$LAUNCHER" << 'STEAMLAUNCH'
#!/usr/bin/env bash
# Steam + AMD : wrapper Arch (/usr/bin/steam) + correctifs WebKit.
# Si ça crash encore : essaie steam-amd-native (runtime désactivé) ou steam-native (AUR).
# Log : ~/.local/share/Steam-amd-launch.log
#
# Ne lance pas steam en parallèle (autre terminal / script) : « Log already open ».

export STEAM_USE_WEBKIT_SANDBOX="${STEAM_USE_WEBKIT_SANDBOX:-0}"

# Hyprland définit souvent SDL_VIDEODRIVER=wayland sans repli → steam.sh warning + segfault / X errors.
export SDL_VIDEODRIVER="${STEAM_SDL_VIDEODRIVER:-wayland,x11}"
# Tout le client en XWayland si encore instable (SteamUpdateUI BadValue, crash après XRR*) :
# export GDK_BACKEND=x11
# export STEAM_SDL_VIDEODRIVER=x11

# Crash webhelper / CEF au démarrage :
# export STEAM_DISABLE_GPU_WEBRENDER=1

# Rare : Mesa + pressure-vessel et GBM (voir steam-runtime#797) — décommente si erreur libgbm :
# export GBM_BACKENDS_PATH="/usr/lib/gbm"

LOG="$HOME/.local/share/Steam-amd-launch.log"
mkdir -p "$(dirname "$LOG")"
{
    echo "======== $(date -Iseconds) mode=runtime-valve-wrapper ========"
    echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
    echo "mesa: $(pacman -Q mesa lib32-mesa 2>/dev/null | tr '\n' ' ')"
    echo "-----"
} >>"$LOG"
exec >>"$LOG" 2>&1
exec /usr/bin/steam "$@"
STEAMLAUNCH
chmod +x "$LAUNCHER"
ok "$LAUNCHER"

cat > "$LAUNCHER_NATIVE" << 'STEAMNAT'
#!/usr/bin/env bash
# Contournement « runtime Steam » : libs système (Arch) comme steam-native (AUR).
# Arch Wiki : STEAM_RUNTIME=0 et -compat-force-slr off
# Préfère steam-native si installé (steam-native-runtime AUR, ~130 deps).

export STEAM_USE_WEBKIT_SANDBOX="${STEAM_USE_WEBKIT_SANDBOX:-0}"
export SDL_VIDEODRIVER="${STEAM_SDL_VIDEODRIVER:-wayland,x11}"
# export GDK_BACKEND=x11
# export STEAM_DISABLE_GPU_WEBRENDER=1

LOG="$HOME/.local/share/Steam-amd-native-launch.log"
mkdir -p "$(dirname "$LOG")"
{
    echo "======== $(date -Iseconds) mode=native-runtime-off ========"
    echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    echo "-----"
} >>"$LOG"
exec >>"$LOG" 2>&1

if command -v steam-native &>/dev/null; then
    exec steam-native "$@"
fi
export STEAM_RUNTIME=0
exec /usr/bin/steam -compat-force-slr off "$@"
STEAMNAT
chmod +x "$LAUNCHER_NATIVE"
ok "$LAUNCHER_NATIVE"

APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
cat > "$APP_DIR/steam-amd.desktop" << DESKEOF
[Desktop Entry]
Name=Steam (AMD — journal)
Name[fr]=Steam (AMD — avec journal)
Comment=Steam Mesa/RADV ; runtime Valve + wrapper Arch ; log ~/.local/share/Steam-amd-launch.log
Exec=$LAUNCHER %U
Icon=steam
Terminal=false
Type=Application
Categories=Game;
DESKEOF
ok "$APP_DIR/steam-amd.desktop"

cat > "$APP_DIR/steam-amd-native.desktop" << DESKEOF
[Desktop Entry]
Name=Steam (AMD — libs système)
Name[fr]=Steam (AMD — runtime natif)
Comment=STEAM_RUNTIME=0 / steam-native si AUR ; si le client crash avec le runtime Valve
Exec=$LAUNCHER_NATIVE %U
Icon=steam
Terminal=false
Type=Application
Categories=Game;
DESKEOF
ok "$APP_DIR/steam-amd-native.desktop"
command -v update-desktop-database &>/dev/null && update-desktop-database "$APP_DIR" 2>/dev/null || true

section "Diagnostic rapide"
_diagnose

section "Résumé"
ok "Terminé."
echo ""
echo -e "${BOLD}À faire${NC}"
echo "  1. D’abord : ${CYAN}$LAUNCHER${NC}   (wrapper Arch + runtime Valve)"
echo "  2. Si crash / silence : ${CYAN}$LAUNCHER_NATIVE${NC}   (runtime désactivé, ou steam-native si AUR)"
echo "  3. Logs     : ${CYAN}tail -f ~/.local/share/Steam-amd-launch.log${NC} et Steam-amd-native-launch.log"
echo "  4. Autre log client : ${CYAN}/tmp/dumps/*_stdout.txt${NC}"
echo "  5. Web / CEF : édite le lanceur et STEAM_DISABLE_GPU_WEBRENDER=1"
echo "  6. pressure-vessel : ${CYAN}sysctl kernel.unprivileged_userns_clone${NC} doit être 1 (sauf config explicite) ; paquet bubblewrap installé"
echo "  7. Sync Mesa : ${CYAN}sudo pacman -Syu mesa lib32-mesa${NC}"
echo "  8. Locale Steam : ${CYAN}en_US.UTF-8${NC} dans /etc/locale.gen + ${CYAN}sudo locale-gen${NC}"
echo "  9. Hyprland : ${CYAN}SDL_VIDEODRIVER=wayland,x11${NC} (pas wayland seul) — mis à jour dans ce dépôt config/hypr/hyprland.conf"
echo " 10. Un seul Steam à la fois ; pas pendant que install-steam-amd-arch.sh tourne."
echo " 11. Doc runtime : https://wiki.archlinux.org/title/Steam/Troubleshooting#Steam_runtime"
echo ""
