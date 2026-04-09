#!/usr/bin/env bash
# =============================================================================
# disable-waybar.sh — Désactive la barre HyDE (waybar) quand Quickshell est la barre
# =============================================================================
# USAGE  : bash disable-waybar.sh [--dry-run]
# CONTEXTE : HyDE lance waybar (souvent via waybar.py --watch) en plus de quickshell:bar
#            → deux barres empilées. Ce script tue waybar et empêche son redémarrage.
# =============================================================================

[[ "$EUID" -eq 0 ]] && { echo "Ne pas lancer en root."; exit 1; }

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Désactivation waybar (HyDE) — barre Quickshell uniquement${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── 1. HyDE : demander à cacher waybar (si hyde-shell dispo) ─────────────────
if command -v hyde-shell &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] hyde-shell waybar --hide"
    else
        hyde-shell waybar --hide 2>/dev/null && ok "hyde-shell waybar --hide" || warn "hyde-shell waybar --hide (ignoré)"
    fi
else
    info "hyde-shell absent — on continue avec kill + config"
fi

# ── 2. Arrêter les processus waybar + watcher HyDE ────────────────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] pkill waybar / waybar.py"
else
    pkill -x waybar 2>/dev/null && ok "waybar arrêté" || info "waybar déjà absent"
    pkill -f "hyde/waybar\.py" 2>/dev/null && ok "waybar.py (HyDE) arrêté" || true
    pkill -f "\.local/lib/hyde/waybar\.py" 2>/dev/null && ok "watcher HyDE arrêté" || true
fi

# ── 3. systemd user : désactiver un éventuel service waybar ──────────────────
while read -r unit; do
    [[ -z "$unit" ]] && continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] systemctl --user disable --now $unit"
    else
        systemctl --user disable --now "$unit" 2>/dev/null && ok "Service désactivé : $unit" || true
    fi
done < <(systemctl --user list-unit-files --no-legend 2>/dev/null | awk '/waybar/ {print $1}')

# ── 4. Commenter exec-once qui lancent waybar dans ~/.config/hypr ─────────────
_comment_exec_waybar() {
    local f="$1"
    [[ ! -f "$f" ]] && return 0
    # Ligne exec-once contenant waybar et pas déjà commentée (# en tête)
    grep -qE '^[[:space:]]*exec-once[[:space:]]*=.*waybar' "$f" 2>/dev/null || return 0

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] commenter waybar dans : $f"
        grep -nE '^[[:space:]]*exec-once[[:space:]]*=.*waybar' "$f" || true
        return 0
    fi

    local bak="${f}.bak.profilearch"
    cp -a "$f" "$bak"
    # Commenter seulement les lignes exec-once contenant waybar et non déjà commentées
    sed -i '/^[[:space:]]*exec-once[[:space:]]*=.*waybar/{
        /^[[:space:]]*#/!s/^[[:space:]]*/# PROFILEARCH_quickshell_only: /
    }' "$f"
    ok "Config mise à jour : $f (backup: $bak)"
}

info "Recherche exec-once … waybar dans $HYPR_DIR …"
if [[ -d "$HYPR_DIR" ]]; then
    while IFS= read -r -d '' conf; do
        # Ignorer sauvegardes / vieux fichiers
        [[ "$conf" == *".bak"* ]] && continue
        [[ "$conf" == *".old" ]] && continue
        [[ "$conf" == *".broken" ]] && continue
        if grep -qE '^[[:space:]]*exec-once[[:space:]]*=.*waybar' "$conf" 2>/dev/null; then
            _comment_exec_waybar "$conf"
        fi
    done < <(find "$HYPR_DIR" -name '*.conf' -type f -print0 2>/dev/null)
else
    warn "Dossier introuvable : $HYPR_DIR"
fi

# ── 5. illogical-impulse : barre en HAUT (pas en bas) ─────────────────────────
II_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
if [[ -f "$II_CFG" ]] && command -v jq &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] jq .bar.bottom = false sur illogical-impulse/config.json"
    else
        _tmp=$(mktemp)
        jq '.bar.bottom = false | .bar.vertical = false' "$II_CFG" > "$_tmp" \
            && mv "$_tmp" "$II_CFG" \
            && ok "illogical-impulse : bar.bottom = false (barre collée en haut)"
    fi
elif [[ -f "$II_CFG" ]]; then
    warn "jq absent — vérifie manuellement que \"bar.bottom\" est false dans $II_CFG"
fi

# ── 6. Recharger Hyprland + redémarrer Quickshell (sinon la barre reste « sous » l’ancienne zone waybar)
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v hyprctl &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] hyprctl reload + restart quickshell"
    else
        hyprctl reload 2>/dev/null && ok "hyprctl reload" || warn "hyprctl reload (hors session Hyprland ?)"
        sleep 0.5
        if systemctl --user restart quickshell.service 2>/dev/null; then
            ok "quickshell redémarré (systemd) — barre doit être en y=0"
        else
            pkill -x qs 2>/dev/null || pkill -x quickshell 2>/dev/null || true
            sleep 0.5
            nohup qs -c ii >/dev/null 2>&1 &
            ok "quickshell relancé (qs -c ii)"
        fi
        sleep 1
        if hyprctl layers 2>/dev/null | grep -q 'namespace: waybar'; then
            warn "waybar encore présent dans les layers — pkill waybar puis relance ce script"
        else
            ok "Aucune couche waybar (hyprctl layers)"
        fi
    fi
else
    info "Pas de session Hyprland active — au prochain login : barre en haut après restart quickshell"
fi

echo ""
echo -e "${GREEN}${BOLD}Terminé.${NC} Si waybar revient au reboot, vérifie :"
echo -e "  ${CYAN}grep -rn exec-once ~/.config/hypr/ | grep waybar${NC}"
echo -e "  ${CYAN}systemctl --user list-unit-files | grep -i waybar${NC}"
echo ""
