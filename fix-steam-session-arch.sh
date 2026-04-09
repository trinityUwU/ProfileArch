#!/usr/bin/env bash
# fix-steam-session-arch.sh — correctifs rapides Steam sous Hyprland/Wayland (Arch)
# Erreurs ciblées : SDL_VIDEODRIVER=wayland seul, setlocale(en_US.UTF-8) failed
# Usage : bash fix-steam-session-arch.sh [--locale]   (--locale : sudo locale-gen en_US)
set -euo pipefail
[[ "$EUID" -eq 0 ]] && { echo "Lance en utilisateur (sudo seulement avec --locale)."; exit 1; }

HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# 1) Hyprland : SDL wayland → wayland,x11
if [[ -f "$HYPR" ]]; then
    if grep -qE '^env = SDL_VIDEODRIVER,wayland$' "$HYPR"; then
        cp -a "$HYPR" "${HYPR}.bak.steamfix.$(date +%s)"
        sed -i 's/^env = SDL_VIDEODRIVER,wayland$/env = SDL_VIDEODRIVER,wayland,x11/' "$HYPR"
        echo -e "${GREEN}[ok]${NC} $HYPR : SDL_VIDEODRIVER=wayland,x11"
    elif grep -qE '^env = SDL_VIDEODRIVER,wayland,x11$' "$HYPR"; then
        echo -e "${GREEN}[ok]${NC} SDL_VIDEODRIVER déjà en wayland,x11"
    else
        echo -e "${YELLOW}[!]${NC} Pas de ligne « env = SDL_VIDEODRIVER,wayland » exacte — vérifie $HYPR à la main"
    fi
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v hyprctl &>/dev/null; then
        hyprctl reload &>/dev/null && echo -e "${GREEN}[ok]${NC} hyprctl reload" || true
    fi
else
    echo -e "${YELLOW}[!]${NC} $HYPR absent — ignore si tu n’utilises pas Hyprland"
fi

# 2) Locale en_US.UTF-8 (Steam l’appelle au démarrage)
if locale -a 2>/dev/null | grep -qiE '^en_US\.(utf8|UTF-8)$'; then
    echo -e "${GREEN}[ok]${NC} locale en_US.UTF-8 disponible"
else
    echo -e "${YELLOW}[!]${NC} en_US.UTF-8 manquant. Commande :"
    echo -e "    ${CYAN}sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen${NC}"
    if [[ "${1:-}" == "--locale" ]]; then
        sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        sudo locale-gen
        echo -e "${GREEN}[ok]${NC} locale-gen exécuté"
    fi
fi

echo ""
echo "Lance Steam avec :  ${CYAN}SDL_VIDEODRIVER=wayland,x11 steam${NC}"
echo "ou réutilise :      ${CYAN}~/.local/bin/steam-amd${NC} (install-steam-amd-arch.sh)"
