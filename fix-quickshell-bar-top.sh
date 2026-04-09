#!/usr/bin/env bash
# =============================================================================
# fix-quickshell-bar-top.sh — Remet la barre Quickshell collée en haut de l’écran
# =============================================================================
# USAGE : bash fix-quickshell-bar-top.sh
# CONTEXTE : Après suppression de waybar, Hyprland garde parfois une zone réservée
#            et Quickshell reste « décalé » vers le bas. Un restart qs corrige.
#            Vérifie aussi que illogical-impulse/config.json a bar.bottom = false.
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root."; exit 1; }

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
II_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"

echo -e "${BLUE}[fix-quickshell-bar-top]${NC}"

# 1. Config JSON : barre en haut
if [[ -f "$II_CFG" ]] && command -v jq &>/dev/null; then
    _tmp=$(mktemp)
    jq '.bar.bottom = false | .bar.vertical = false' "$II_CFG" > "$_tmp" && mv "$_tmp" "$II_CFG"
    echo -e "${GREEN}[ OK ]${NC} $II_CFG → bar.bottom = false"
else
    echo -e "${YELLOW}[WARN]${NC} jq ou config.json manquant — règle la position dans les réglages Quickshell (bar en haut)"
fi

# 2. Plus de waybar qui réserve le haut
pkill -x waybar 2>/dev/null || true
pkill -f "hyde/waybar\.py" 2>/dev/null || true

# 3. Hyprland + Quickshell
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v hyprctl &>/dev/null; then
    hyprctl reload 2>/dev/null && echo -e "${GREEN}[ OK ]${NC} hyprctl reload"
    sleep 0.5
    if systemctl --user restart quickshell.service 2>/dev/null; then
        echo -e "${GREEN}[ OK ]${NC} systemctl --user restart quickshell.service"
    else
        pkill -x qs 2>/dev/null || pkill -x quickshell 2>/dev/null || true
        sleep 0.5
        nohup qs -c ii >/dev/null 2>&1 &
        echo -e "${GREEN}[ OK ]${NC} qs -c ii relancé"
    fi
    echo ""
    echo "Vérifie la position de quickshell:bar (y doit être 0) :"
    hyprctl layers 2>/dev/null | grep -E "quickshell:bar|waybar" || true
else
    echo -e "${YELLOW}[INFO]${NC} Hors session Hyprland — reconnecte-toi ou : hyprctl reload && systemctl --user restart quickshell"
fi
echo ""
