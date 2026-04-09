#!/usr/bin/env bash
# =============================================================================
# verify-setup.sh — Vérification & scanner système TrinityArch
# =============================================================================
# USAGE  : bash verify-setup.sh
# CIBLE  : Arch Linux + Hyprland + HyDE + end-4/dots-hyprland
# FONCTION : Scanner système, vérifier configs, installer end-4 si manquant
# =============================================================================

set -o pipefail

# ── Couleurs terminal ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[✗ ]${NC}  $*"; }
section() {
    echo ""
    echo -e "${BOLD}${CYAN}┌$(printf '─%.0s' {1..48})┐${NC}"
    echo -e "${BOLD}${CYAN}│  $*$(printf '%*s' $((45 - ${#*})) '')│${NC}"
    echo -e "${BOLD}${CYAN}└$(printf '─%.0s' {1..48})┘${NC}"
}

# ── Stats globales ─────────────────────────────────────────────────────────────
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

check() {
    ((TOTAL_CHECKS++))
    if [[ $? -eq 0 ]]; then
        ((PASSED_CHECKS++))
        ok "$1"
        return 0
    else
        ((FAILED_CHECKS++))
        err "$1"
        return 1
    fi
}

warn_check() {
    ((WARNINGS++))
    warn "$1"
}

# ── Vérifications ─────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && { err "Ne pas lancer en root."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"

section "🔍 SCANNER SYSTÈME"
echo ""

# === INFO SYSTÈME ===
info "OS & Kernel"
os_name=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
kernel=$(uname -r)
ok "Distribution : $os_name"
ok "Kernel : $kernel"

# === DISPLAY & WM ===
section "🖥️  AFFICHAGE & GESTIONNAIRE FENÊTRES"
echo ""

info "Vérification Display Server..."
if [[ -n "$WAYLAND_DISPLAY" ]]; then
    ok "Wayland actif : $WAYLAND_DISPLAY"
elif [[ -n "$DISPLAY" ]]; then
    warn_check "Xorg détecté ($DISPLAY) — Wayland recommandé pour Hyprland"
else
    err "Aucun display server détecté"
fi

info "Vérification WM..."
if pgrep -x "hyprland" >/dev/null 2>&1; then
    wm_pid=$(pgrep -x "hyprland")
    ok "Hyprland actif (PID: $wm_pid)"
else
    warn_check "Hyprland non actif (peut être normal si pas en session)"
fi

# === COMPONENTS PRINCIPAUX ===
section "📦 COMPOSANTS PRINCIPAUX"
echo ""

declare -a components=(
    "hyprland:Hyprland (WM)"
    "hyprlock:Hyprlock (Lock screen)"
    "hypridle:Hypridle (Idle manager)"
    "sddm:SDDM (Display Manager)"
    "kitty:Kitty (Terminal)"
    "fish:Fish shell"
    "rofi:Rofi (Launcher)"
    "dunst:Dunst (Notifications)"
    "quickshell:Quickshell (Bar)"
    "wlogout:Wlogout (Logout menu)"
)

for comp in "${components[@]}"; do
    pkg="${comp%%:*}"
    name="${comp##*:}"
    
    if command -v "$pkg" &>/dev/null || pacman -Q "$pkg" >/dev/null 2>&1; then
        version=$(command -v "$pkg" >/dev/null && $pkg --version 2>/dev/null | head -1)
        [[ -z "$version" ]] && version=$(pacman -Q "$pkg" 2>/dev/null | cut -d' ' -f2)
        ok "$name : $version"
    else
        err "$name : ❌ NOT FOUND"
    fi
done

# === THÈMES & ICÔNES ===
section "🎨 THÈMES & ICÔNES"
echo ""

info "Thèmes GTK..."
gtk_themes=("$HOME/.local/share/themes" "/usr/share/themes")
found_catppuccin=0

for dir in "${gtk_themes[@]}"; do
    if [[ -d "$dir" ]] && find "$dir" -name "*atppuccin*" -o -name "*Catppuccin*" 2>/dev/null | grep -q .; then
        found_catppuccin=1
        ok "Catppuccin GTK trouvé"
        break
    fi
done

[[ $found_catppuccin -eq 0 ]] && err "Catppuccin GTK non trouvé"

info "Thèmes icônes..."
icon_themes=("$HOME/.local/share/icons" "/usr/share/icons")
found_tela=0

for dir in "${icon_themes[@]}"; do
    if [[ -d "$dir" ]] && find "$dir" -name "*ela*" -o -name "*dracula*" 2>/dev/null | grep -q .; then
        found_tela=1
        ok "Tela/Dracula icônes trouvé"
        break
    fi
done

[[ $found_tela -eq 0 ]] && err "Tela/Dracula icônes non trouvé"

# === CONFIGURATIONS CUSTOM ===
section "⚙️  CONFIGURATIONS CUSTOM"
echo ""

declare -a config_paths=(
    "~/.config/hypr/custom/general.conf:Hyprland custom (general)"
    "~/.config/hypr/custom/rules.conf:Hyprland custom (rules)"
    "~/.config/quickshell/ii:Quickshell bar (ii)"
    "~/.config/kitty:Kitty configuration"
    "~/.config/fish:Fish shell config"
    "~/.config/gtk-3.0:GTK 3 theme"
    "~/.config/gtk-4.0:GTK 4 theme"
    "~/.config/rofi:Rofi config"
    "~/.config/dunst:Dunst config"
    "~/.config/wlogout:Wlogout config"
    "~/.local/share/hyde:HyDE data"
    "~/.local/state/quickshell/user/generated:Quickshell colors"
)

for path_info in "${config_paths[@]}"; do
    path="${path_info%%:*}"
    desc="${path_info##*:}"
    expanded_path="${path/\~/$HOME}"
    
    if [[ -e "$expanded_path" ]]; then
        ok "$desc"
    else
        err "$desc : MISSING"
    fi
done

# === HyDE & end-4/dots-hyprland ===
section "🎭 HyDE & end-4/dots-hyprland"
echo ""

info "Vérification HyDE..."
if command -v hyde-shell &>/dev/null || [[ -f "$HOME/.local/bin/hyde-shell" ]]; then
    ok "HyDE installé"
else
    err "HyDE NOT INSTALLED"
fi

info "Vérification end-4/dots-hyprland..."
end4_dir="$HOME/.config/hyde/themes/illogical-impulse"
if [[ -d "$end4_dir" ]]; then
    ok "end-4/dots-hyprland trouvé ($end4_dir)"
    file_count=$(find "$end4_dir" -type f | wc -l)
    ok "  └─ $file_count fichiers présents"
else
    err "end-4/dots-hyprland NOT FOUND"
    warn_check "  └─ Installation recommandée"
fi

# === PALETTE COULEURS ===
section "🎨 PALETTE COULEURS (Material You Violet)"
echo ""

colors_file="$HOME/.local/state/quickshell/user/generated/colors.json"
if [[ -f "$colors_file" ]]; then
    ok "colors.json présent"
    # Vérifier quelques couleurs clés
    if grep -q "#9d6ff5\|#0d0b14" "$colors_file" 2>/dev/null; then
        ok "Couleurs personnalisées détectées"
    else
        warn_check "Palette couleurs différente du backup original"
    fi
else
    err "colors.json NOT FOUND"
fi

# === DOTFILES INSTALLÉS ===
section "📁 DOTFILES PERSONNALISÉS"
echo ""

info "Comparaison dotfiles backup vs ~/.config..."

config_dirs=("hypr" "kitty" "quickshell" "rofi" "waybar" "dunst" "gtk-3.0" "gtk-4.0" "Kvantum" "wlogout")
configs_found=0

for dir in "${config_dirs[@]}"; do
    src="$CONFIG_SRC/$dir"
    dst="$HOME/.config/$dir"
    
    if [[ -d "$src" && -d "$dst" ]]; then
        ((configs_found++))
        file_count=$(find "$dst" -type f 2>/dev/null | wc -l)
        ok "$dir : $file_count fichiers"
    elif [[ -d "$src" ]]; then
        err "$dir : backup existe mais PAS copié"
    fi
done

info "Total configs trouvées : $configs_found/10"

# === APPS CUSTOM ===
section "🚀 APPS PERSONNALISÉES"
echo ""

if [[ -d "$SCRIPT_DIR/apps/wpe-manager" ]]; then
    ok "wpe-manager (Wallpaper Engine Manager) trouvé"
    [[ -d "$HOME/.local/bin" ]] && ok "  └─ ~/.local/bin accessible"
else
    warn_check "wpe-manager non trouvé"
fi

# === RÉSUMÉ ===
section "📊 RÉSUMÉ VÉRIFICATION"
echo ""

passed_pct=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
failed_pct=$((FAILED_CHECKS * 100 / TOTAL_CHECKS))

echo -e "  ${GREEN}✓ Réussis${NC}   : $PASSED_CHECKS/$TOTAL_CHECKS"
echo -e "  ${RED}✗ Échoués${NC}    : $FAILED_CHECKS/$TOTAL_CHECKS"
[[ $WARNINGS -gt 0 ]] && echo -e "  ${YELLOW}⚠ Avertissements${NC} : $WARNINGS"

echo ""
[[ $FAILED_CHECKS -eq 0 ]] && ok "Tous les checks sont passés ! ✨" || err "$FAILED_CHECKS checks échoués"

# === PROPOSITION INSTALLATION end-4 ===
if [[ ! -d "$end4_dir" ]]; then
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
    read -rp "$(echo -e "${BOLD}Installer end-4/dots-hyprland maintenant ? [o/N] ${NC}")" confirm
    
    if [[ "$confirm" =~ ^[oOyY]$ ]]; then
        section "📥 INSTALLATION end-4/dots-hyprland"
        echo ""
        
        info "Création du répertoire HyDE themes..."
        mkdir -p "$HOME/.config/hyde/themes"
        
        info "Clonage du repo end-4/dots-hyprland..."
        git clone https://github.com/end-4/dots-hyprland "$end4_dir" 2>&1 | grep -E "(Cloning|Receiving|Resolving)" || true
        
        if [[ -d "$end4_dir" ]]; then
            ok "end-4/dots-hyprland cloné avec succès"
            file_count=$(find "$end4_dir" -type f | wc -l)
            ok "  └─ $file_count fichiers"
            
            info "Copie des configs end-4 (optionnel)..."
            # Copier les wallpapers si disponibles
            [[ -d "$end4_dir/wallpapers" ]] && cp -r "$end4_dir/wallpapers" "$HOME/.config/hyde/" && ok "Wallpapers copiés"
            
            # Copier configs modulaires
            [[ -d "$end4_dir/config" ]] && cp -r "$end4_dir/config"/* "$HOME/.config/" 2>/dev/null && ok "Configs end-4 appliquées"
            
            echo ""
            ok "Installation end-4 terminée !"
            echo -e "${CYAN}ℹ Redémarrez Hyprland pour appliquer : Super+Q puis reconnectez${NC}"
        else
            err "Impossible de cloner end-4"
        fi
    fi
fi

echo ""
section "✅ VÉRIFICATION TERMINÉE"
echo ""
info "Pour plus de détails, consultez le README.md"
info "Pour reconfigurer : bash verify-setup.sh"
echo ""
