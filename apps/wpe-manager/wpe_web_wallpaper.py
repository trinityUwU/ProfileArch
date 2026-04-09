#!/usr/bin/env python3
"""
Fond d'écran HTML (type web Wallpaper Engine) via WebKit + XWayland + Hyprland.
La fenêtre est placée en fond via des window rules Hyprland (float, pin, nofocus)
puis poussée en bas du z-order (alterzorder bottom).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

WINDOW_TITLE_PREFIX = "WPE-WEB-WALLPAPER"


def _detect_display():
    """Détecte le DISPLAY XWayland via le process Xwayland."""
    try:
        out = subprocess.run(["pgrep", "-a", "Xwayland"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            m = re.search(r"Xwayland\s+(:[\d]+)", out.stdout)
            if m:
                return m.group(1)
    except Exception:
        pass
    return os.environ.get("DISPLAY", ":1")


def _get_monitor_geometry(output_name):
    """Récupère position/taille d'un écran via hyprctl."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            for mon in json.loads(out.stdout):
                if mon.get("name") == output_name:
                    return mon["x"], mon["y"], mon["width"], mon["height"]
    except Exception:
        pass
    return 0, 0, 1920, 1080


def _setup_hyprland_rules():
    """Pose les window rules Hyprland AVANT d'ouvrir la fenêtre."""
    prefix = WINDOW_TITLE_PREFIX
    rules = [
        f"float, title:^{prefix}",
        f"nofocus, title:^{prefix}",
        f"noinitialfocus, title:^{prefix}",
        f"renderunfocused, title:^{prefix}",
        f"noblur, title:^{prefix}",
        f"noshadow, title:^{prefix}",
        f"noborder, title:^{prefix}",
        f"noanim, title:^{prefix}",
    ]
    for rule in rules:
        subprocess.run(["hyprctl", "keyword", "windowrulev2", rule], capture_output=True, timeout=2)


def _push_to_background(win_title, mx, my, mw, mh):
    """Attend que la fenêtre apparaisse, la positionne, pin, et alterzorder bottom."""
    for _ in range(50):
        time.sleep(0.15)
        try:
            out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2)
            if out.returncode != 0:
                continue
            for client in json.loads(out.stdout):
                if client.get("title") == win_title:
                    addr = client["address"]
                    subprocess.run(["hyprctl", "dispatch", f"resizewindowpixel exact {mw} {mh},address:{addr}"], capture_output=True, timeout=2)
                    time.sleep(0.05)
                    subprocess.run(["hyprctl", "dispatch", f"movewindowpixel exact {mx} {my},address:{addr}"], capture_output=True, timeout=2)
                    time.sleep(0.05)
                    subprocess.run(["hyprctl", "dispatch", f"pin address:{addr}"], capture_output=True, timeout=2)
                    time.sleep(0.05)
                    subprocess.run(["hyprctl", "dispatch", f"alterzorder bottom,address:{addr}"], capture_output=True, timeout=2)
                    return
        except Exception:
            continue


def main():
    ap = argparse.ArgumentParser(description="Wallpaper HTML (WebView)")
    ap.add_argument("--output", required=True, help="Nom de l'écran (ex: DP-1)")
    ap.add_argument("--path", required=True, type=Path, help="Dossier du wallpaper")
    ap.add_argument("--entry", default="index.html", help="Fichier HTML d'entrée")
    args = ap.parse_args()

    html = args.path / args.entry
    if not html.exists():
        print(f"Erreur: Fichier introuvable: {html}", file=sys.stderr)
        if args.path.exists():
            names = [p.name for p in args.path.iterdir()]
            if any(n.endswith(".pkg") for n in names):
                print("Ce dossier contient un scene.pkg (type scene), pas du HTML.", file=sys.stderr)
            else:
                print("Contenu:", " ".join(names[:15]), file=sys.stderr)
        sys.exit(1)

    os.environ["DISPLAY"] = _detect_display()
    os.environ["GDK_BACKEND"] = "x11"
    os.environ["WEBKIT_DISABLE_COMPOSITING_MODE"] = "1"

    import gi
    gi.require_version("Gtk", "3.0")
    try:
        gi.require_version("WebKit2", "4.1")
    except ValueError:
        gi.require_version("WebKit2", "4.0")
    from gi.repository import Gtk, WebKit2

    mx, my, mw, mh = _get_monitor_geometry(args.output)
    win_title = f"{WINDOW_TITLE_PREFIX}-{args.output}"

    _setup_hyprland_rules()

    window = Gtk.Window()
    window.set_title(win_title)
    window.set_default_size(mw, mh)
    window.set_decorated(False)
    window.set_resizable(False)

    ctx = WebKit2.WebContext.get_default()
    ctx.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)

    web = WebKit2.WebView.new_with_context(ctx)
    settings = web.get_settings()
    settings.set_enable_webgl(True)
    settings.set_allow_file_access_from_file_urls(True)
    settings.set_allow_universal_access_from_file_urls(True)
    settings.set_enable_javascript(True)
    settings.set_enable_write_console_messages_to_stdout(True)
    try:
        settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.ON_DEMAND)
    except Exception:
        pass

    web.load_uri(html.as_uri())
    window.add(web)

    bg_thread = threading.Thread(target=_push_to_background, args=(win_title, mx, my, mw, mh), daemon=True)
    bg_thread.start()

    window.show_all()

    window.connect("destroy", Gtk.main_quit)
    Gtk.main()


if __name__ == "__main__":
    main()
