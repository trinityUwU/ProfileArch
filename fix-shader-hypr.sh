#!/usr/bin/env bash
# =============================================================================
# fix-shader-hypr.sh — Corrige "Screen shader path not found" (HyDE / Hyprland)
# =============================================================================
# USAGE : bash fix-shader-hypr.sh
# Cause : shaders.conf utilise $XDG_CONFIG_HOME avant que la variable Hyprland
#         soit définie → chemin vide. On force ~/.config/... + custom/env.conf.
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root."; exit 1; }

HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${BLUE}[fix-shader-hypr]${NC} $HYPR"

_fix_file() {
    local f="$1"
    [[ ! -f "$f" ]] && return 0
    grep -qE 'SCREEN_SHADER|XDG_CONFIG_HOME.*shader' "$f" 2>/dev/null || return 0
    cp -a "$f" "${f}.bak.shaderfix.$(date +%s)"
    # Remplacer les variantes connues
    sed -i \
        -e 's|\$SCREEN_SHADER_PATH = "\$XDG_CONFIG_HOME/hypr/shaders/disable.frag"|\$SCREEN_SHADER_PATH = ~/.config/hypr/shaders/disable.frag|g' \
        -e 's|\$SCREEN_SHADER_PATH = \$XDG_CONFIG_HOME/hypr/shaders/disable.frag|\$SCREEN_SHADER_PATH = ~/.config/hypr/shaders/disable.frag|g' \
        -e 's|\$SCREEN_SHADER_COMPILED = \$XDG_CONFIG_HOME/hypr/shaders/\.compiled\.cache\.glsl|\$SCREEN_SHADER_COMPILED = ~/.config/hypr/shaders/.compiled.cache.glsl|g' \
        -e 's|\$SCREEN_SHADER_COMPILED = "\$XDG_CONFIG_HOME/hypr/shaders/\.compiled\.cache\.glsl"|\$SCREEN_SHADER_COMPILED = ~/.config/hypr/shaders/.compiled.cache.glsl|g' \
        "$f"
    echo -e "${GREEN}[ OK ]${NC} corrigé : $f"
}

# Fichiers où HyDE injecte souvent les shaders
for f in "$HYPR/shaders.conf" "$HYPR/hyprland.conf" "$HYPR/userprefs.conf"; do
    _fix_file "$f"
done

# Tout autre .conf qui mentionne les deux
while IFS= read -r -d '' f; do
    [[ "$f" == *".bak"* ]] && continue
    grep -q 'SCREEN_SHADER_PATH' "$f" 2>/dev/null && grep -q 'XDG_CONFIG_HOME' "$f" 2>/dev/null && _fix_file "$f"
done < <(find "$HYPR" -maxdepth 1 -name '*.conf' -type f -print0 2>/dev/null)

# S'assurer que disable.frag existe
SH="$HYPR/shaders/disable.frag"
if [[ ! -f "$SH" ]]; then
    echo -e "${YELLOW}[WARN]${NC} $SH manquant — installe HyDE ou copie depuis ProfileArch config/hypr/shaders/"
else
    echo -e "${GREEN}[ OK ]${NC} $SH présent"
fi

# Variables Hyprland (filet de sécurité)
ENVF="$HYPR/custom/env.conf"
mkdir -p "$HYPR/custom"
if [[ -f "$ENVF" ]] && ! grep -q '^\$XDG_CONFIG_HOME' "$ENVF" 2>/dev/null; then
    cat >> "$ENVF" << 'ENVEOF'

# PROFILEARCH: XDG pour shaders (filet de sécurité)
$XDG_CONFIG_HOME = ~/.config
$XDG_STATE_HOME = ~/.local/state
$XDG_CACHE_HOME = ~/.cache
$XDG_DATA_HOME = ~/.local/share
ENVEOF
    echo -e "${GREEN}[ OK ]${NC} \$XDG_* ajouté dans custom/env.conf"
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v hyprctl &>/dev/null; then
    hyprctl reload && echo -e "${GREEN}[ OK ]${NC} hyprctl reload"
else
    echo -e "${YELLOW}[INFO]${NC} Relance une session Hyprland ou : hyprctl reload"
fi
