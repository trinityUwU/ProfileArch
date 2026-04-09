#!/usr/bin/env bash
# =============================================================================
# install-steam-amd-arch.sh — Steam sur Arch Linux + GPU AMD (Mesa / RADV)
# =============================================================================
# USAGE  : bash install-steam-amd-arch.sh [--diagnose-only] [--non-interactive]
# Crash silencieux typique : [multilib] désactivé, lib32-mesa / Vulkan 32 bits
# manquants, versions mesa / lib32-mesa désynchronisées, webhelper WebKit.
# Doc Arch : https://wiki.archlinux.org/title/Steam
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root. Utilise ton utilisateur (sudo sera demandé)."; exit 1; }

DIAG_ONLY=0
NON_INTERACTIVE=0
for a in "$@"; do
    case "$a" in
        --diagnose-only) DIAG_ONLY=1 ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
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
)

info "Cœur : ${CORE_PKGS[*]}"
sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}" || {
    err "Installation échouée — vérifie multilib + miroirs."
    exit 1
}
ok "Paquets cœur installés"

info "Extras (layers, vulkaninfo, mesa-utils 32)…"
sudo pacman -S --needed --noconfirm "${EXTRA_PKGS[@]}" 2>/dev/null || warn "Certains extras indisponibles — non bloquant"

if [[ "$NON_INTERACTIVE" -ne 1 ]]; then
    read -rp "$(echo -e "${BOLD}Installer gamemode + mangohud ? [o/N] ${NC}")" gm
    if [[ "$gm" =~ ^[oOyY]$ ]]; then
        sudo pacman -S --needed --noconfirm gamemode lib32-gamemode mangohud 2>/dev/null || warn "Optionnels partiels"
    fi
fi

# ── Lanceur avec journal (plus de crash « silencieux ») ───────────────────────
section "Lanceur Steam (AMD) + fichier log"

LAUNCHER="$HOME/.local/bin/steam-amd"
mkdir -p "$HOME/.local/bin"
cat > "$LAUNCHER" << 'STEAMLAUNCH'
#!/usr/bin/env bash
# Steam + AMD : WebKit sandbox et GPU web render souvent en cause si crash au boot.
# Log : ~/.local/share/Steam-amd-launch.log

export STEAM_USE_WEBKIT_SANDBOX="${STEAM_USE_WEBKIT_SANDBOX:-0}"

# Si Steam se ferme tout de suite, passe à 1 (décommente la ligne suivante) :
# export STEAM_DISABLE_GPU_WEBRENDER=1

LOG="$HOME/.local/share/Steam-amd-launch.log"
mkdir -p "$(dirname "$LOG")"
{
    echo "======== $(date -Iseconds) ========"
    echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
    echo "mesa: $(pacman -Q mesa lib32-mesa 2>/dev/null | tr '\n' ' ')"
    echo "-----"
} >>"$LOG"
exec >>"$LOG" 2>&1
exec /usr/bin/steam "$@"
STEAMLAUNCH
chmod +x "$LAUNCHER"
ok "$LAUNCHER"

APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
cat > "$APP_DIR/steam-amd.desktop" << DESKEOF
[Desktop Entry]
Name=Steam (AMD — journal)
Name[fr]=Steam (AMD — avec journal)
Comment=Steam Mesa/RADV ; log dans ~/.local/share/Steam-amd-launch.log
Exec=$LAUNCHER %U
Icon=steam
Terminal=false
Type=Application
Categories=Game;
DESKEOF
ok "$APP_DIR/steam-amd.desktop"
command -v update-desktop-database &>/dev/null && update-desktop-database "$APP_DIR" 2>/dev/null || true

section "Diagnostic rapide"
_diagnose

section "Résumé"
ok "Terminé."
echo ""
echo -e "${BOLD}À faire${NC}"
echo "  1. Terminal : ${CYAN}$LAUNCHER${NC}   (ou menu « Steam (AMD — journal) »)"
echo "  2. Log      : ${CYAN}tail -f ~/.local/share/Steam-amd-launch.log${NC}"
echo "  3. Si écran noir / fermeture : édite $LAUNCHER et active STEAM_DISABLE_GPU_WEBRENDER=1"
echo "  4. Sync Mesa : ${CYAN}sudo pacman -Syu mesa lib32-mesa${NC} (même mise à jour)"
echo "  5. Pilote noyau : AMDGPU (amdgpu), pas radeon legacy — voir lspci ci-dessus"
echo ""
