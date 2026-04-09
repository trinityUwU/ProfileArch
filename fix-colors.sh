#!/usr/bin/env bash
# =============================================================================
# fix-colors.sh — Forcer la palette violet #9d6ff5 sur TrinityArch
# =============================================================================
# USAGE : bash fix-colors.sh
# Lance ce script si quickshell/GTK/terminal ont les mauvaises couleurs.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SRC="$SCRIPT_DIR/local-state"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR ]${NC}  $*"; }
step()  { echo ""; echo -e "${BOLD}${CYAN}▶ $*${NC}"; }

ACCENT="#9d6ff5"
MODE="dark"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

QS_STATE="$XDG_STATE_HOME/quickshell/user/generated"
QS_II="$XDG_CONFIG_HOME/quickshell/ii"
II_CFG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_CFG="$XDG_CONFIG_HOME/matugen"

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}   fix-colors.sh — Palette violet ${ACCENT}${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── ÉTAPE 1 : Créer les répertoires requis ────────────────────────────────────
step "1. Préparation des répertoires"
mkdir -p "$QS_STATE"
mkdir -p "$QS_STATE/terminal"
mkdir -p "$XDG_CACHE_HOME/quickshell"
ok "Répertoires créés"

# ── ÉTAPE 2 : Restaurer les templates matugen depuis le backup ────────────────
step "2. Templates matugen"
if [[ -d "$SCRIPT_DIR/config/matugen" ]]; then
    mkdir -p "$MATUGEN_CFG"
    rsync -a "$SCRIPT_DIR/config/matugen/" "$MATUGEN_CFG/"
    ok "Templates matugen restaurés depuis backup"
else
    warn "Templates matugen non trouvés dans le backup"
fi

# ── ÉTAPE 3 : Config illogical-impulse avec accentColor violet ────────────────
step "3. Config illogical-impulse (accentColor)"
mkdir -p "$XDG_CONFIG_HOME/illogical-impulse"

if command -v jq &>/dev/null && [[ -f "$SCRIPT_DIR/config/illogical-impulse/config.json" ]]; then
    if [[ -f "$II_CFG" ]]; then
        # Mettre à jour uniquement accentColor et type dans le fichier existant
        info "Mise à jour accentColor dans config.json existant..."
        _tmp=$(mktemp)
        jq --arg color "$ACCENT" \
           '.appearance.palette.accentColor = $color | .appearance.palette.type = "scheme-tonal-spot"' \
           "$II_CFG" > "$_tmp" && mv "$_tmp" "$II_CFG"
        ok "accentColor → $ACCENT"
    else
        # Copier depuis backup (déjà configuré avec violet)
        cp "$SCRIPT_DIR/config/illogical-impulse/config.json" "$II_CFG"
        ok "config.json créé depuis backup (accentColor: $ACCENT)"
    fi
elif [[ -f "$SCRIPT_DIR/config/illogical-impulse/config.json" ]]; then
    cp "$SCRIPT_DIR/config/illogical-impulse/config.json" "$II_CFG"
    ok "config.json copié depuis backup"
else
    warn "jq ou config backup manquant — création config minimale"
    cat > "$II_CFG" << CFGEOF
{
    "appearance": {
        "palette": {
            "accentColor": "$ACCENT",
            "type": "scheme-tonal-spot"
        },
        "wallpaperTheming": {
            "enableAppsAndShell": true,
            "enableTerminal": true,
            "enableQtApps": true,
            "terminalGenerationProps": {
                "forceDarkMode": false,
                "harmonizeThreshold": 100,
                "harmony": 0.6,
                "termFgBoost": 0.35
            }
        }
    },
    "panelFamily": "ii"
}
CFGEOF
    ok "config.json minimal créé avec accentColor: $ACCENT"
fi

# ── ÉTAPE 4 : Restaurer material_colors.scss et colors.json depuis backup ────
step "4. Fichiers couleurs pré-générés"
if [[ -d "$STATE_SRC/quickshell-generated" ]]; then
    cp "$STATE_SRC/quickshell-generated/colors.json" "$QS_STATE/colors.json" 2>/dev/null \
        && ok "colors.json violet copié"
    cp "$STATE_SRC/quickshell-generated/material_colors.scss" "$QS_STATE/material_colors.scss" 2>/dev/null \
        && ok "material_colors.scss violet copié"
fi

# ── ÉTAPE 5 : Lancer matugen color hex → génère TOUS les templates ────────────
step "5. Génération matugen (${ACCENT})"
if command -v matugen &>/dev/null; then
    info "Lancement : matugen color hex ${ACCENT} --mode ${MODE}"
    if matugen color hex "$ACCENT" --mode "$MODE" 2>/dev/null; then
        ok "matugen exécuté — templates générés"
        ok "  → $QS_STATE/colors.json"
        ok "  → $XDG_CONFIG_HOME/gtk-3.0/gtk.css"
        ok "  → $XDG_CONFIG_HOME/gtk-4.0/gtk.css"
        ok "  → $XDG_CONFIG_HOME/hypr/hyprland/colors.conf"
    else
        warn "matugen a retourné une erreur — utilisation du backup colors.json"
    fi
else
    err "matugen non installé"
    warn "  → yay -S matugen"
    warn "  → Les couleurs du backup seront utilisées (non-idéal)"
fi

# ── ÉTAPE 6 : Générer material_colors.scss via Python si venv dispo ──────────
step "6. Génération material_colors.scss"
VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}"

if [[ -n "$VENV" && -f "$VENV/bin/activate" ]]; then
    info "Python venv trouvé : $VENV"
    GEN_PY="$QS_II/scripts/colors/generate_colors_material.py"
    TERMSCHEME="$QS_II/scripts/colors/terminal/scheme-base.json"
    if [[ -f "$GEN_PY" ]]; then
        source "$VENV/bin/activate"
        python3 "$GEN_PY" \
            --color "$ACCENT" \
            --mode "$MODE" \
            --scheme "scheme-tonal-spot" \
            --termscheme "$TERMSCHEME" \
            --blend_bg_fg \
            --cache "$QS_STATE/color.txt" \
            > "$QS_STATE/material_colors.scss" 2>/dev/null \
            && ok "material_colors.scss généré via Python" \
            || warn "Génération Python échouée — backup utilisé"
        deactivate
    fi
else
    info "ILLOGICAL_IMPULSE_VIRTUAL_ENV non défini"
    info "  → material_colors.scss du backup utilisé (suffisant)"
fi

# ── ÉTAPE 7 : Appliquer les couleurs terminal ─────────────────────────────────
step "7. Application couleurs terminal"
APPLYCOLOR="$QS_II/scripts/colors/applycolor.sh"
if [[ -f "$APPLYCOLOR" ]]; then
    chmod +x "$APPLYCOLOR"
    bash "$APPLYCOLOR" 2>/dev/null && ok "Couleurs terminal appliquées" || warn "applycolor.sh erreur mineure"
else
    err "applycolor.sh non trouvé"
    warn "  → Lance d'abord : bash install.sh"
fi

# ── ÉTAPE 8 : GTK via gsettings ───────────────────────────────────────────────
step "8. GTK / Icônes / Curseur"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
gsettings set org.gnome.desktop.interface gtk-theme     "Catppuccin-Mocha"       2>/dev/null && ok "GTK: Catppuccin-Mocha"       || warn "gsettings gtk-theme"
gsettings set org.gnome.desktop.interface icon-theme    "Tela-circle-dracula"    2>/dev/null && ok "Icons: Tela-circle-dracula"  || warn "gsettings icon-theme"
gsettings set org.gnome.desktop.interface cursor-theme  "Bibata-Modern-Classic"  2>/dev/null && ok "Cursor: Bibata-Modern-Classic" || warn "gsettings cursor-theme"
gsettings set org.gnome.desktop.interface color-scheme  "prefer-dark"            2>/dev/null || true

# Mise à jour gtk-3.0/settings.ini et gtk-4.0/settings.ini
for ver in 3.0 4.0; do
    gset_file="$XDG_CONFIG_HOME/gtk-$ver/settings.ini"
    if [[ -f "$gset_file" ]]; then
        sed -i "s/^gtk-theme-name=.*/gtk-theme-name=Catppuccin-Mocha/"         "$gset_file"
        sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=Tela-circle-dracula/" "$gset_file"
        sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Bibata-Modern-Classic/" "$gset_file"
        ok "gtk-$ver/settings.ini mis à jour"
    fi
done

# ── ÉTAPE 9 : Hyprland couleurs ───────────────────────────────────────────────
step "9. Couleurs Hyprland"
HYPR_COLORS="$XDG_CONFIG_HOME/hypr/hyprland/colors.conf"
if [[ -f "$HYPR_COLORS" ]]; then
    ok "hyprland/colors.conf présent"
    if [[ -n "$WAYLAND_DISPLAY" ]] && command -v hyprctl &>/dev/null; then
        hyprctl reload 2>/dev/null && ok "Hyprland rechargé" || warn "hyprctl reload"
    fi
fi

# ── ÉTAPE 10 : Redémarrer quickshell si session active ───────────────────────
step "10. Quickshell"
if [[ -n "$WAYLAND_DISPLAY" ]]; then
    if pgrep -x "qs" &>/dev/null || pgrep -x "quickshell" &>/dev/null; then
        info "Redémarrage de quickshell..."
        pkill -x qs 2>/dev/null || pkill -x quickshell 2>/dev/null || true
        sleep 1
        nohup qs -p "$QS_II" > /dev/null 2>&1 &
        ok "quickshell redémarré"
    else
        info "Quickshell non actif (sera lancé par Hyprland au prochain démarrage)"
    fi
else
    info "Hors session Wayland — quickshell sera relancé au prochain login"
fi

# ── RÉSUMÉ ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ Palette violet ${ACCENT} appliquée !${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Si les couleurs ne changent pas dans quickshell :"
echo -e "  ${CYAN}pkill qs && qs -p ~/.config/quickshell/ii${NC}"
echo ""
echo -e "  Si GTK ne change pas :"
echo -e "  ${CYAN}nwg-look${NC} ou relancer les apps"
echo ""
