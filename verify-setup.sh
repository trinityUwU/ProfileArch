#!/usr/bin/env bash
# =============================================================================
# verify-setup.sh — Scanner & correcteur système TrinityArch
# =============================================================================
# USAGE  : bash verify-setup.sh [--fix] [--fix-quickshell] [--fix-colors]
#          Sans argument  : scan complet + rapport
#          --fix          : corrige automatiquement tout ce qui est réparable
#          --fix-quickshell : corrige uniquement quickshell
#          --fix-colors   : réapplique la palette violet
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
STATE_SRC="$SCRIPT_DIR/local-state"
SHARE_SRC="$SCRIPT_DIR/local-share"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ ✓ ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[ ⚠ ]${NC}  $*"; }
err()     { echo -e "${RED}[ ✗ ]${NC}  $*"; }
fix()     { echo -e "${CYAN}[ FIX]${NC}  $*"; }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}┌$(printf '─%.0s' {1..54})┐${NC}"
    printf "${BOLD}${CYAN}│  %-52s│${NC}\n" "$*"
    echo -e "${BOLD}${CYAN}└$(printf '─%.0s' {1..54})┘${NC}"
}

# ── Mode ──────────────────────────────────────────────────────────────────────
AUTO_FIX=0
FIX_QS=0
FIX_COLORS=0

for arg in "$@"; do
    case "$arg" in
        --fix)            AUTO_FIX=1 ;;
        --fix-quickshell) FIX_QS=1 ;;
        --fix-colors)     FIX_COLORS=1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] && { err "Ne pas lancer en root."; exit 1; }

# ── Compteurs ─────────────────────────────────────────────────────────────────
CHECKS_OK=0; CHECKS_FAIL=0; CHECKS_WARN=0
FIXABLE=()   # liste des corrections disponibles

pass()  { ((CHECKS_OK++));   ok "$1"; }
fail()  { ((CHECKS_FAIL++)); err "$1"; FIXABLE+=("$2"); }
warn2() { ((CHECKS_WARN++)); warn "$1"; }

# =============================================================================
# SECTION 1 — SYSTÈME
# =============================================================================
section "SYSTÈME"

os=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
kernel=$(uname -r)
arch=$(uname -m)
[[ "$os" == "arch" ]] && pass "Distribution : Arch Linux" || warn2 "Distribution : $os (non-Arch)"
ok "Kernel : $kernel | Arch : $arch"
ok "Utilisateur : $USER (uid=$(id -u)) | HOME : $HOME"

# Wayland/Xorg
if [[ -n "$WAYLAND_DISPLAY" ]]; then
    pass "Wayland actif : $WAYLAND_DISPLAY"
elif [[ -n "$DISPLAY" ]]; then
    warn2 "Xorg ($DISPLAY) — Wayland recommandé pour Hyprland"
else
    info "Pas de display server actif (normal si tty/install)"
fi

# Hyprland actif ?
if pgrep -x "hyprland" >/dev/null 2>&1; then
    pass "Hyprland actif (PID: $(pgrep -x hyprland))"
else
    info "Hyprland non actif (normal hors session)"
fi

# =============================================================================
# SECTION 2 — PAQUETS
# =============================================================================
section "PAQUETS REQUIS"

_pkg_check() {
    local pkg="$1"; local name="${2:-$1}"
    if pacman -Qq "$pkg" &>/dev/null; then
        local ver; ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        pass "$name ($ver)"
        return 0
    else
        fail "$name : NOT INSTALLED" "install_pkg:$pkg"
        return 1
    fi
}

# Composants critiques
echo ""
info "Composants Hyprland..."
_pkg_check hyprland
_pkg_check hyprlock "Hyprlock"
_pkg_check hypridle "Hypridle"

echo ""
info "Interface..."
_pkg_check sddm "SDDM"
_pkg_check kitty "Kitty"
_pkg_check fish "Fish shell"

echo ""
info "Bar & widgets..."
if _pkg_check quickshell-git "Quickshell-git"; then
    :
elif pacman -Qq quickshell &>/dev/null; then
    warn2 "quickshell (stable) présent — quickshell-git recommandé pour config ii"
    FIXABLE+=("upgrade_quickshell")
else
    fail "Quickshell : NOT INSTALLED (ni stable ni git)" "install_pkg:quickshell-git"
fi

echo ""
info "Outils Wayland..."
_pkg_check rofi-wayland "Rofi Wayland"   || _pkg_check rofi "Rofi"
_pkg_check dunst "Dunst"
_pkg_check wlogout "Wlogout"
_pkg_check waybar "Waybar"

echo ""
info "Paquets essentiels..."
_pkg_check matugen "Matugen"
_pkg_check jq "jq"
_pkg_check nwg-displays "nwg-displays"
_pkg_check nemo "Nemo"
_pkg_check cliphist "Cliphist"
_pkg_check electron "Electron"

echo ""
info "Fonts..."
_pkg_check ttf-jetbrains-mono-nerd "JetBrains Mono Nerd"
_pkg_check ttf-material-symbols-variable-git "Material Symbols" || \
    _pkg_check ttf-material-symbols-variable "Material Symbols (stable)"

echo ""
info "illogical-impulse..."
for pkg in illogical-impulse-basic illogical-impulse-fonts-themes \
           illogical-impulse-bibata-modern-classic-bin illogical-impulse-audio; do
    _pkg_check "$pkg"
done

# =============================================================================
# SECTION 3 — CONFIGS PERSONNALISÉES
# =============================================================================
section "CONFIGS PERSONNALISÉES"

_cfg_check() {
    local path="${1/\~/$HOME}"
    local desc="$2"
    local fix_key="${3:-}"
    if [[ -e "$path" ]]; then
        pass "$desc"
        return 0
    else
        fail "$desc : MANQUANT ($path)" "$fix_key"
        return 1
    fi
}

echo ""
info "Hyprland..."
_cfg_check "~/.config/hypr/hyprland.conf"          "hyprland.conf"         "fix_hypr"
_cfg_check "~/.config/hypr/custom/general.conf"    "custom/general.conf"   "fix_hypr"
_cfg_check "~/.config/hypr/custom/rules.conf"      "custom/rules.conf"     "fix_hypr"
_cfg_check "~/.config/hypr/custom/execs.conf"      "custom/execs.conf"     "fix_hypr"
_cfg_check "~/.config/hypr/custom/env.conf"        "custom/env.conf"       "fix_hypr"
_cfg_check "~/.config/hypr/custom/keybinds.conf"   "custom/keybinds.conf"  "fix_hypr"
_cfg_check "~/.config/hypr/monitors.conf"          "monitors.conf"         "fix_hypr"

echo ""
info "Quickshell..."
_cfg_check "~/.config/quickshell/ii/shell.qml"     "quickshell/ii/shell.qml"    "fix_quickshell"
_cfg_check "~/.config/quickshell/ii/settings.qml"  "quickshell/ii/settings.qml" "fix_quickshell"
_cfg_check "~/.config/quickshell/ii/GlobalStates.qml" "quickshell/ii/GlobalStates.qml" "fix_quickshell"

echo ""
info "Config illogical-impulse (accentColor)..."
II_CFG="$HOME/.config/illogical-impulse/config.json"
if [[ -f "$II_CFG" ]]; then
    if command -v jq &>/dev/null; then
        accent=$(jq -r '.appearance.palette.accentColor // ""' "$II_CFG" 2>/dev/null)
        if [[ "$accent" == "#9d6ff5" ]]; then
            pass "illogical-impulse/config.json — accentColor: #9d6ff5 ✓"
        elif [[ -z "$accent" ]]; then
            fail "illogical-impulse/config.json — accentColor VIDE (couleurs depuis wallpaper = défaut)" "fix_accent"
        else
            warn2 "illogical-impulse/config.json — accentColor: $accent (attendu #9d6ff5)"
            FIXABLE+=("fix_accent")
        fi
    else
        pass "illogical-impulse/config.json présent (jq manquant pour vérifier)"
    fi
else
    fail "illogical-impulse/config.json MANQUANT (couleurs jamais appliquées)" "fix_accent"
fi

echo ""
info "Templates matugen..."
MATUGEN_CFG="$HOME/.config/matugen"
if [[ -f "$MATUGEN_CFG/config.toml" ]]; then
    pass "matugen/config.toml présent"
    [[ -d "$MATUGEN_CFG/templates" ]] && pass "matugen/templates présent" || \
        fail "matugen/templates MANQUANT" "fix_matugen"
else
    fail "~/.config/matugen MANQUANT — matugen ne peut pas générer les couleurs" "fix_matugen"
fi

echo ""
info "Couleurs Material You (violet)..."
COLORS_FILE="$HOME/.local/state/quickshell/user/generated/colors.json"
if [[ -f "$COLORS_FILE" ]]; then
    if command -v jq &>/dev/null; then
        primary=$(jq -r '.primary // ""' "$COLORS_FILE" 2>/dev/null)
        if [[ "${primary,,}" == "#9d6ff5" ]]; then
            pass "colors.json — palette violet (#9d6ff5) ✓"
        else
            warn2 "colors.json présent mais primary: $primary (attendu #9d6ff5)"
            FIXABLE+=("fix_colors")
        fi
    else
        pass "colors.json présent"
    fi
else
    fail "colors.json MANQUANT" "fix_colors"
fi

SCSS_FILE="$HOME/.local/state/quickshell/user/generated/material_colors.scss"
[[ -f "$SCSS_FILE" ]] && pass "material_colors.scss présent" || fail "material_colors.scss MANQUANT" "fix_colors"

echo ""
info "Autres configs..."
_cfg_check "~/.config/kitty/kitty.conf"    "kitty.conf"   "fix_kitty"
_cfg_check "~/.config/rofi/theme.rasi"     "rofi theme"   "fix_rofi"
_cfg_check "~/.config/dunst/dunstrc"       "dunstrc"      "fix_dunst"
_cfg_check "~/.config/wlogout/style.css"   "wlogout style" "fix_wlogout"
_cfg_check "~/.config/gtk-3.0/settings.ini" "gtk-3.0"     "fix_gtk"
_cfg_check "~/.config/Kvantum/kvantum.kvconfig" "Kvantum"  "fix_kvantum"

echo ""
info "HyDE..."
_cfg_check "~/.config/hyde/config.toml"    "hyde config.toml" "fix_hyde"
_cfg_check "~/.local/share/hyde"           "~/.local/share/hyde" "fix_hyde"

# =============================================================================
# SECTION 4 — PERMISSIONS SCRIPTS
# =============================================================================
section "PERMISSIONS SCRIPTS"

echo ""
SCRIPTS_WRONG=0
while IFS= read -r -d '' sh; do
    if [[ ! -x "$sh" ]]; then
        ((SCRIPTS_WRONG++))
        warn2 "Non-exécutable : $sh"
    fi
done < <(find "$HOME/.config/hypr" "$HOME/.config/quickshell" \
              -name "*.sh" -print0 2>/dev/null)

if [[ $SCRIPTS_WRONG -eq 0 ]]; then
    pass "Tous les scripts .sh sont exécutables"
else
    fail "$SCRIPTS_WRONG scripts sans permission +x" "fix_perms"
fi

# =============================================================================
# SECTION 5 — GTK / THÈMES / CURSEUR
# =============================================================================
section "THÈMES & CURSEUR"

echo ""
# GTK
gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")

[[ "$gtk_theme" == "Catppuccin-Mocha"* ]] && pass "GTK theme : $gtk_theme" || \
    fail "GTK theme : $gtk_theme (attendu: Catppuccin-Mocha)" "fix_gtk"

[[ "$icon_theme" == "Tela-circle-dracula"* ]] && pass "Icon theme : $icon_theme" || \
    fail "Icon theme : $icon_theme (attendu: Tela-circle-dracula)" "fix_gtk"

[[ "$cursor_theme" == "Bibata-Modern-Classic"* ]] && pass "Cursor theme : $cursor_theme" || \
    fail "Cursor theme : $cursor_theme (attendu: Bibata-Modern-Classic)" "fix_gtk"

# Thème GTK sur le FS
found_ctpk=0
for d in "$HOME/.local/share/themes" "/usr/share/themes"; do
    [[ -d "$d" ]] && ls "$d" 2>/dev/null | grep -qi "catppuccin" && { found_ctpk=1; break; }
done
[[ $found_ctpk -eq 1 ]] && pass "Catppuccin GTK installé sur le FS" || \
    fail "Catppuccin GTK absent du FS" "install_pkg:catppuccin-gtk-theme-mocha"

# Bibata curseur
found_bibata=0
for d in "$HOME/.local/share/icons" "/usr/share/icons"; do
    [[ -d "$d/Bibata-Modern-Classic" ]] && { found_bibata=1; break; }
done
[[ $found_bibata -eq 1 ]] && pass "Bibata-Modern-Classic curseur installé" || \
    fail "Bibata-Modern-Classic curseur absent" "install_pkg:illogical-impulse-bibata-modern-classic-bin"

# =============================================================================
# SECTION 5b — SHADER & ENV VARIABLES HYPRLAND
# =============================================================================
section "SHADER & VARIABLES HYPRLAND"

echo ""
info "Variable \$XDG_CONFIG_HOME dans custom/env.conf..."
CUSTOM_ENV="$HOME/.config/hypr/custom/env.conf"
if [[ -f "$CUSTOM_ENV" ]]; then
    if grep -q '^\$XDG_CONFIG_HOME' "$CUSTOM_ENV" 2>/dev/null; then
        pass "\$XDG_CONFIG_HOME défini dans custom/env.conf ✓"
    else
        fail "\$XDG_CONFIG_HOME ABSENT de custom/env.conf → erreur shader Hyprland" "fix_xdg_var"
    fi
else
    fail "custom/env.conf MANQUANT → variables XDG non définies" "fix_hypr"
fi

info "Shader disable.frag..."
SHADER_FILE="$HOME/.config/hypr/shaders/disable.frag"
[[ -f "$SHADER_FILE" ]] && pass "disable.frag présent" || fail "disable.frag MANQUANT" "fix_hypr"

# =============================================================================
# SECTION 6 — SERVICES
# =============================================================================
section "SERVICES SYSTEMD"

echo ""
systemctl is-enabled sddm &>/dev/null && pass "sddm.service : activé" || \
    fail "sddm.service : non activé" "enable_sddm"

# Service quickshell
QS_SERVICE="$HOME/.config/systemd/user/quickshell.service"
if [[ -f "$QS_SERVICE" ]]; then
    systemctl --user is-enabled quickshell.service &>/dev/null && \
        pass "quickshell.service (user) : activé" || \
        fail "quickshell.service présent mais NON activé" "enable_qs_service"
else
    fail "quickshell.service MANQUANT dans ~/.config/systemd/user/" "install_qs_service"
fi

# Python venv
VENV_DIR="$HOME/.local/state/quickshell/.venv"
if [[ -f "$VENV_DIR/bin/activate" ]]; then
    pass "Python venv end-4 présent ($VENV_DIR)"
    source "$VENV_DIR/bin/activate" 2>/dev/null
    py_ok=0
    python3 -c "import materialyoucolor" 2>/dev/null && py_ok=1
    deactivate 2>/dev/null
    [[ $py_ok -eq 1 ]] && pass "materialyoucolor installé dans venv" || \
        fail "materialyoucolor MANQUANT dans venv (switchwall.sh cassé)" "fix_venv"
else
    fail "Python venv manquant → switchwall.sh ne peut pas générer les couleurs" "fix_venv"
fi

# =============================================================================
# SECTION 7 — QUICKSHELL DIAGNOSTIC APPROFONDI
# =============================================================================
section "QUICKSHELL DIAGNOSTIC"

echo ""
QS_II="$HOME/.config/quickshell/ii"
QS_SCRIPTS="$QS_II/scripts/colors/applycolor.sh"

[[ -d "$QS_II" ]] && pass "Répertoire quickshell/ii présent" || \
    fail "Répertoire quickshell/ii ABSENT" "fix_quickshell"

[[ -f "$QS_SCRIPTS" ]] && pass "applycolor.sh présent" || \
    fail "applycolor.sh ABSENT" "fix_quickshell"

[[ -x "$QS_SCRIPTS" ]] && pass "applycolor.sh exécutable" || {
    fail "applycolor.sh non exécutable" "fix_perms"
}

# Vérifier que $qsConfig est bien "ii" dans hyprland.conf
HYPR_MAIN="$HOME/.config/hypr/hyprland.conf"
if [[ -f "$HYPR_MAIN" ]]; then
    if grep -q 'qsConfig = ii' "$HYPR_MAIN" 2>/dev/null; then
        pass 'hyprland.conf : $qsConfig = ii ✓'
    else
        fail 'hyprland.conf : $qsConfig != ii (mauvaise config bar)' "fix_hypr"
    fi
fi

# Vérifier que quickshell est lancé dans execs
HYPR_EXECS="$HOME/.config/hypr/hyprland/execs.conf"
if [[ -f "$HYPR_EXECS" ]]; then
    if grep -q "quickshell\|qs " "$HYPR_EXECS" 2>/dev/null; then
        pass "quickshell dans hyprland/execs.conf ✓"
    else
        fail "quickshell absent de hyprland/execs.conf" "fix_qs_exec"
    fi
fi

# =============================================================================
# RAPPORT FINAL
# =============================================================================
section "RAPPORT"

echo ""
TOTAL=$((CHECKS_OK + CHECKS_FAIL + CHECKS_WARN))
echo -e "  ${GREEN}✓ Réussis    : $CHECKS_OK${NC}"
echo -e "  ${RED}✗ Échecs     : $CHECKS_FAIL${NC}"
echo -e "  ${YELLOW}⚠ Avertiss. : $CHECKS_WARN${NC}"
echo -e "  Total checks : $TOTAL"

if [[ $CHECKS_FAIL -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}${BOLD}  ✨ Tout est en ordre !${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Corrections disponibles :${NC}"
echo -e "  ${CYAN}bash verify-setup.sh --fix${NC}             → tout corriger automatiquement"
echo -e "  ${CYAN}bash verify-setup.sh --fix-quickshell${NC}  → corriger quickshell seulement"
echo -e "  ${CYAN}bash verify-setup.sh --fix-colors${NC}      → réappliquer palette violet"

# =============================================================================
# CORRECTIONS AUTOMATIQUES
# =============================================================================

if [[ "$AUTO_FIX" -eq 0 && "$FIX_QS" -eq 0 && "$FIX_COLORS" -eq 0 ]]; then
    echo ""
    read -rp "$(echo -e "${BOLD}Lancer les corrections maintenant ? [o/N] ${NC}")" do_fix
    [[ "$do_fix" =~ ^[oOyY]$ ]] && AUTO_FIX=1
fi

[[ "$AUTO_FIX" -eq 0 && "$FIX_QS" -eq 0 && "$FIX_COLORS" -eq 0 ]] && exit 0

section "CORRECTIONS EN COURS"

# ── Fix : permissions scripts ──────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_perms"; then
    fix "Correction des permissions +x..."
    find "$HOME/.config/hypr"       -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$HOME/.config/quickshell" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$HOME/.config/hyde"       -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    ok "Permissions corrigées"
fi

# ── Fix : quickshell config ────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 || "$FIX_QS" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_quickshell"; then
    fix "Restauration config quickshell/ii depuis backup..."
    if [[ -d "$CONFIG_SRC/quickshell/ii" ]]; then
        mkdir -p "$HOME/.config/quickshell"
        rsync -a --backup --suffix=".orig" "$CONFIG_SRC/quickshell/ii/" "$HOME/.config/quickshell/ii/"
        find "$HOME/.config/quickshell" -name "*.sh" -exec chmod +x {} \;
        ok "quickshell/ii restauré"
    else
        err "Source quickshell/ii introuvable dans le backup"
    fi
fi

# ── Fix : accentColor illogical-impulse ───────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 || "$FIX_COLORS" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_accent"; then
    fix "Forcer accentColor #9d6ff5 dans illogical-impulse/config.json..."
    mkdir -p "$HOME/.config/illogical-impulse"
    II_CFG="$HOME/.config/illogical-impulse/config.json"
    if [[ -f "$II_CFG" ]] && command -v jq &>/dev/null; then
        _tmp=$(mktemp)
        jq '.appearance.palette.accentColor = "#9d6ff5" | .appearance.palette.type = "scheme-tonal-spot"' \
            "$II_CFG" > "$_tmp" && mv "$_tmp" "$II_CFG"
        ok "accentColor → #9d6ff5"
    elif [[ -f "$SCRIPT_DIR/config/illogical-impulse/config.json" ]]; then
        cp "$SCRIPT_DIR/config/illogical-impulse/config.json" "$II_CFG"
        ok "config.json copié depuis backup (accentColor: #9d6ff5)"
    else
        warn "Impossible de corriger accentColor — lance: bash fix-colors.sh"
    fi
fi

# ── Fix : templates matugen ───────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_matugen"; then
    fix "Restauration templates matugen..."
    if [[ -d "$SCRIPT_DIR/config/matugen" ]]; then
        mkdir -p "$HOME/.config/matugen"
        rsync -a "$SCRIPT_DIR/config/matugen/" "$HOME/.config/matugen/"
        ok "Templates matugen restaurés"
    fi
fi

# ── Fix : couleurs violet (pipeline complet) ──────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 || "$FIX_COLORS" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_colors"; then
    fix "Application complète palette violet via fix-colors.sh..."
    if [[ -f "$SCRIPT_DIR/fix-colors.sh" ]]; then
        bash "$SCRIPT_DIR/fix-colors.sh"
    else
        # Fallback manuel
        mkdir -p "$HOME/.local/state/quickshell/user/generated"
        [[ -d "$STATE_SRC/quickshell-generated" ]] && \
            cp "$STATE_SRC/quickshell-generated/"* "$HOME/.local/state/quickshell/user/generated/" 2>/dev/null
        [[ -f "$HOME/.config/matugen/config.toml" ]] && command -v matugen &>/dev/null && \
            matugen color hex "#9d6ff5" --mode dark 2>/dev/null && ok "matugen lancé"
        APPLYCOLOR="$HOME/.config/quickshell/ii/scripts/colors/applycolor.sh"
        [[ -f "$APPLYCOLOR" ]] && bash "$APPLYCOLOR" 2>/dev/null && ok "Palette appliquée"
    fi
fi

# ── Fix : configs hypr ────────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_hypr"; then
    fix "Restauration config hyprland..."
    if [[ -d "$CONFIG_SRC/hypr" ]]; then
        rsync -a --backup --suffix=".orig" "$CONFIG_SRC/hypr/" "$HOME/.config/hypr/"
        find "$HOME/.config/hypr" -name "*.sh" -exec chmod +x {} \;
        ok "Hyprland config restaurée"
    fi
fi

# ── Fix : kitty ───────────────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_kitty"; then
    [[ -d "$CONFIG_SRC/kitty" ]] && {
        fix "Restauration config kitty..."
        rsync -a --backup --suffix=".orig" "$CONFIG_SRC/kitty/" "$HOME/.config/kitty/"
        ok "Kitty config restaurée"
    }
fi

# ── Fix : rofi / dunst / wlogout ──────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]]; then
    for app in rofi dunst wlogout waybar; do
        [[ -d "$CONFIG_SRC/$app" ]] && {
            fix "Restauration $app..."
            rsync -a --backup --suffix=".orig" "$CONFIG_SRC/$app/" "$HOME/.config/$app/"
            ok "$app restauré"
        }
    done
fi

# ── Fix : GTK gsettings ───────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_gtk"; then
    fix "Réapplication des thèmes GTK..."
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
    gsettings set org.gnome.desktop.interface gtk-theme     "Catppuccin-Mocha"       2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme    "Tela-circle-dracula"    2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme  "Bibata-Modern-Classic"  2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme  "prefer-dark"            2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-name     "JetBrains Mono 11"      2>/dev/null || true
    ok "GTK/icônes/curseur réappliqués"

    # Aussi dans les fichiers gtk settings.ini
    for v in 3.0 4.0; do
        GSET="$HOME/.config/gtk-$v/settings.ini"
        if [[ -f "$GSET" ]]; then
            sed -i "s/gtk-theme-name=.*/gtk-theme-name=Catppuccin-Mocha/" "$GSET"
            sed -i "s/gtk-icon-theme-name=.*/gtk-icon-theme-name=Tela-circle-dracula/" "$GSET"
            sed -i "s/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Bibata-Modern-Classic/" "$GSET"
            ok "gtk-$v/settings.ini mis à jour"
        fi
    done
fi

# ── Fix : HyDE config ─────────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_hyde"; then
    fix "Restauration config HyDE..."
    mkdir -p "$HOME/.config/hyde/themes"
    [[ -f "$CONFIG_SRC/hyde-config.toml" ]] && \
        cp "$CONFIG_SRC/hyde-config.toml" "$HOME/.config/hyde/config.toml"
    [[ -d "$CONFIG_SRC/hyde-wallbash" ]] && \
        rsync -a --backup --suffix=".orig" "$CONFIG_SRC/hyde-wallbash/" "$HOME/.config/hyde/wallbash/"
    if [[ -d "$CONFIG_SRC/hyde-themes" ]]; then
        for td in "$CONFIG_SRC/hyde-themes/"/*/; do
            tname=$(basename "$td")
            mkdir -p "$HOME/.config/hyde/themes/$tname"
            rsync -a "$td" "$HOME/.config/hyde/themes/$tname/" 2>/dev/null
        done
    fi
    [[ -d "$SHARE_SRC/hyde" ]] && {
        mkdir -p "$HOME/.local/share/hyde"
        rsync -a "$SHARE_SRC/hyde/" "$HOME/.local/share/hyde/"
    }
    ok "HyDE config restaurée"
fi

# ── Fix : quickshell dans execs.conf ──────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_qs_exec"; then
    HYPR_EXECS="$HOME/.config/hypr/hyprland/execs.conf"
    if [[ -f "$HYPR_EXECS" ]] && ! grep -q "quickshell\|qs " "$HYPR_EXECS" 2>/dev/null; then
        fix "Ajout de quickshell dans execs.conf..."
        echo "" >> "$HYPR_EXECS"
        echo "# Quickshell bar (config ii)" >> "$HYPR_EXECS"
        echo 'exec-once = qs -p $HOME/.config/quickshell/ii' >> "$HYPR_EXECS"
        ok "quickshell ajouté à execs.conf"
    fi
fi

# ── Fix : variable $XDG_CONFIG_HOME dans custom/env.conf ─────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_xdg_var"; then
    fix "Ajout \$XDG_CONFIG_HOME dans custom/env.conf..."
    CUSTOM_ENV="$HOME/.config/hypr/custom/env.conf"
    if [[ -f "$CUSTOM_ENV" ]] && ! grep -q '^\$XDG_CONFIG_HOME' "$CUSTOM_ENV" 2>/dev/null; then
        cat >> "$CUSTOM_ENV" << 'ENVEOF'

# ######## XDG Dirs (requis pour shaders.conf HyDE) #########
# Sans ces variables, Hyprland affiche: "Screen shader path not found"
$XDG_CONFIG_HOME = ~/.config
$XDG_STATE_HOME = ~/.local/state
$XDG_CACHE_HOME = ~/.cache
$XDG_DATA_HOME = ~/.local/share
ENVEOF
        ok "\$XDG_CONFIG_HOME ajouté → shader Hyprland corrigé"
        [[ -n "$WAYLAND_DISPLAY" ]] && hyprctl reload 2>/dev/null && ok "Hyprland rechargé"
    elif [[ ! -f "$CUSTOM_ENV" ]] && [[ -f "$SCRIPT_DIR/config/hypr/custom/env.conf" ]]; then
        cp "$SCRIPT_DIR/config/hypr/custom/env.conf" "$CUSTOM_ENV"
        ok "custom/env.conf restauré depuis backup"
    fi
fi

# ── Fix : service quickshell ─────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "install_qs_service\|enable_qs_service"; then
    fix "Installation/activation service quickshell..."
    mkdir -p "$HOME/.config/systemd/user"
    QS_SERVICE="$HOME/.config/systemd/user/quickshell.service"
    if [[ ! -f "$QS_SERVICE" ]] && [[ -f "$SCRIPT_DIR/config/systemd-user/quickshell.service" ]]; then
        cp "$SCRIPT_DIR/config/systemd-user/quickshell.service" "$QS_SERVICE"
        ok "quickshell.service copié"
    elif [[ ! -f "$QS_SERVICE" ]]; then
        # Créer le service si absent du backup
        cat > "$QS_SERVICE" << 'SVCEOF'
[Unit]
Description=Quickshell
After=graphical-session.target
Wants=graphical-session.target

[Service]
ExecStart=/usr/bin/qs -c ii
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
SVCEOF
        ok "quickshell.service créé"
    fi
    systemctl --user daemon-reload
    systemctl --user enable quickshell.service 2>/dev/null && ok "quickshell.service activé" || warn "enable quickshell: hors session"
    [[ -n "$WAYLAND_DISPLAY" ]] && systemctl --user start quickshell.service 2>/dev/null && ok "quickshell démarré"
fi

# ── Fix : Python venv end-4 ───────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "fix_venv"; then
    fix "Création/réparation venv Python end-4..."
    VENV_DIR="$HOME/.local/state/quickshell/.venv"
    mkdir -p "$HOME/.local/state/quickshell"
    if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
        python3 -m venv "$VENV_DIR" && ok "Venv créé" || err "Impossible de créer le venv"
    fi
    if [[ -f "$VENV_DIR/bin/activate" ]]; then
        source "$VENV_DIR/bin/activate"
        pip install --quiet materialyoucolor Pillow 2>/dev/null \
            && ok "materialyoucolor + Pillow installés dans venv" \
            || warn "pip install partiel"
        deactivate
    fi
fi

# ── Fix : SDDM ────────────────────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]] || echo "${FIXABLE[*]}" | grep -q "enable_sddm"; then
    fix "Activation SDDM..."
    sudo systemctl enable sddm 2>/dev/null && ok "sddm activé" || warn "sddm enable échoué"
fi

# ── Fix : paquets manquants ───────────────────────────────────────────────────
if [[ "$AUTO_FIX" -eq 1 ]]; then
    echo ""
    fix "Vérification paquets manquants..."
    MISSING_PKGS=()
    for item in "${FIXABLE[@]}"; do
        [[ "$item" == install_pkg:* ]] && MISSING_PKGS+=("${item#install_pkg:}")
    done
    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
        fix "Installation : ${MISSING_PKGS[*]}"
        yay -S --needed --noconfirm --answerdiff=None --answerclean=None "${MISSING_PKGS[@]}" \
            && ok "Paquets installés" || warn "Certains paquets ont échoué"
    else
        ok "Aucun paquet manquant à installer"
    fi
fi

# =============================================================================
# RÉSUMÉ FINAL DES CORRECTIONS
# =============================================================================
echo ""
section "CORRECTIONS TERMINÉES"
echo ""
ok "Toutes les corrections automatiques ont été appliquées."
echo ""
echo -e "${CYAN}Relance le scanner pour vérifier :${NC}"
echo -e "  bash verify-setup.sh"
echo ""

if pgrep -x "hyprland" >/dev/null 2>&1; then
    echo -e "${YELLOW}Recharge Hyprland pour appliquer les changements :${NC}"
    echo -e "  ${CYAN}hyprctl reload${NC}           → recharger config Hyprland"
    echo -e "  ${CYAN}pkill quickshell${NC}          → redémarrer quickshell"
    echo -e "  ${CYAN}dunstctl reload${NC}            → recharger dunst"
fi
echo ""
