#!/usr/bin/env bash
# =============================================================================
# fix-shader-hypr.sh — Corrige "Screen shader path not found" (HyDE / Hyprland)
# =============================================================================
# USAGE : bash fix-shader-hypr.sh
# Causes fréquentes :
#   - Chemins avec ~ non résolus pour decoration:screen_shader
#   - shaders.conf sourcé avant $XDG_CONFIG_HOME
#   - ~/.config/hypr/shaders/.compiled.cache.glsl manquant (copie / gitignore)
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SHADER_DIR="$SCRIPT_DIR/config/hypr/shaders"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${BLUE}[fix-shader-hypr]${NC} $HYPR"

_fix_file() {
    local f="$1"
    [[ ! -f "$f" ]] && return 0
    grep -q 'SCREEN_SHADER' "$f" 2>/dev/null || return 0
    cp -a "$f" "${f}.bak.shaderfix.$(date +%s)"
    sed -i \
        -e 's|\$SCREEN_SHADER_PATH = "\$XDG_CONFIG_HOME/hypr/shaders/disable.frag"|\$SCREEN_SHADER_PATH = $XDG_CONFIG_HOME/hypr/shaders/disable.frag|g' \
        -e 's|\$SCREEN_SHADER_PATH = ~/.config/hypr/shaders/disable.frag|\$SCREEN_SHADER_PATH = $XDG_CONFIG_HOME/hypr/shaders/disable.frag|g' \
        -e 's|\$SCREEN_SHADER_COMPILED = "\$XDG_CONFIG_HOME/hypr/shaders/\.compiled\.cache\.glsl"|\$SCREEN_SHADER_COMPILED = $XDG_CONFIG_HOME/hypr/shaders/.compiled.cache.glsl|g' \
        -e 's|\$SCREEN_SHADER_COMPILED = ~/.config/hypr/shaders/\.compiled\.cache\.glsl|\$SCREEN_SHADER_COMPILED = $XDG_CONFIG_HOME/hypr/shaders/.compiled.cache.glsl|g' \
        "$f"
    echo -e "${GREEN}[ OK ]${NC} corrigé : $f"
}

# Fichiers où HyDE injecte souvent les shaders
for f in "$HYPR/shaders.conf" "$HYPR/hyprland.conf" "$HYPR/userprefs.conf"; do
    _fix_file "$f"
done

while IFS= read -r -d '' f; do
    [[ "$f" == *".bak"* ]] && continue
    grep -q 'SCREEN_SHADER_PATH' "$f" 2>/dev/null && grep -q '~/' "$f" 2>/dev/null && _fix_file "$f"
done < <(find "$HYPR" -maxdepth 1 -name '*.conf' -type f -print0 2>/dev/null)

# hyprland.conf : source=shaders.conf après custom/env.conf
HYPR_MAIN="$HYPR/hyprland.conf"
if [[ -f "$HYPR_MAIN" ]] && ! grep -qE '^source[[:space:]]*=[[:space:]]*shaders\.conf' "$HYPR_MAIN"; then
    if grep -q '^source=custom/env.conf' "$HYPR_MAIN"; then
        cp -a "$HYPR_MAIN" "${HYPR_MAIN}.bak.shaderfix.$(date +%s)"
        sed -i '/^source=custom\/env\.conf$/a source=shaders.conf' "$HYPR_MAIN"
        echo -e "${GREEN}[ OK ]${NC} source=shaders.conf ajouté dans hyprland.conf"
    fi
fi

# Fichiers shader
mkdir -p "$HYPR/shaders"
SH_FRAG="$HYPR/shaders/disable.frag"
SH_GLSL="$HYPR/shaders/.compiled.cache.glsl"

if [[ ! -f "$SH_FRAG" ]] && [[ -f "$REPO_SHADER_DIR/disable.frag" ]]; then
    cp -a "$REPO_SHADER_DIR/disable.frag" "$SH_FRAG"
    echo -e "${GREEN}[ OK ]${NC} copié disable.frag depuis le dépôt"
elif [[ -f "$SH_FRAG" ]]; then
    echo -e "${GREEN}[ OK ]${NC} $SH_FRAG présent"
else
    echo -e "${YELLOW}[WARN]${NC} $SH_FRAG manquant — copie config/hypr/shaders/ depuis ProfileArch"
fi

if [[ ! -f "$SH_GLSL" ]] && [[ -f "$REPO_SHADER_DIR/.compiled.cache.glsl" ]]; then
    cp -a "$REPO_SHADER_DIR/.compiled.cache.glsl" "$SH_GLSL"
    echo -e "${GREEN}[ OK ]${NC} copié .compiled.cache.glsl depuis le dépôt"
elif [[ -f "$SH_GLSL" ]]; then
    echo -e "${GREEN}[ OK ]${NC} $SH_GLSL présent"
else
    echo -e "${YELLOW}[WARN]${NC} $SH_GLSL manquant — le bandeau Hyprland peut persister"
fi

# custom/general.conf : screen_shader (filet si ancienne copie)
GEN_CUSTOM="$HYPR/custom/general.conf"
if [[ -f "$GEN_CUSTOM" ]] && ! grep -q 'screen_shader[[:space:]]*=' "$GEN_CUSTOM" 2>/dev/null; then
    if grep -q '^decoration {' "$GEN_CUSTOM"; then
        cp -a "$GEN_CUSTOM" "${GEN_CUSTOM}.bak.shaderfix.$(date +%s)"
        sed -i '/^decoration {/a\    screen_shader = $SCREEN_SHADER_COMPILED' "$GEN_CUSTOM"
        echo -e "${GREEN}[ OK ]${NC} screen_shader ajouté dans custom/general.conf"
    fi
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
