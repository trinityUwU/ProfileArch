#!/usr/bin/env python3
"""WPE Manager v3 - mpvpaper + linux-wallpaperengine (scenes)"""

import json, os, subprocess, mimetypes, shutil, sys, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, unquote

WORKSHOP  = Path.home() / ".local/share/Steam/steamapps/workshop/content/431960"
CONF      = Path.home() / ".config/wallpaperengine_screens.conf"
RESTORE   = Path.home() / ".config/hypr/custom/scripts/__restore_video_wallpaper.sh"


def _detect_screens():
    """Ordre : WPE_SCREENS (csv) → hyprctl monitors → défaut dual-head."""
    env = os.environ.get("WPE_SCREENS", "").strip()
    if env:
        return [s.strip() for s in env.split(",") if s.strip()]
    try:
        out = subprocess.check_output(
            ["hyprctl", "monitors", "-j"], text=True, timeout=3
        )
        names = [m["name"] for m in json.loads(out) if m.get("name")]
        if names:
            return names
    except Exception:
        pass
    return ["DP-1", "HDMI-A-1"]


SCREENS = _detect_screens()
PORT      = 6969
MPV_OPTS  = "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0"

VIDEO_EXT = {".mp4", ".webm", ".mkv", ".avi", ".mov"}
# Types "scene" WE (scenes, web, application) — nécessitent linux-wallpaperengine
SCENE_TYPES = ("scene", "web", "application")
# Désactivé par défaut : LWE affiche souvent les scenes en fixe (pas d’animation)
# Mettre WPE_USE_LWE=1 pour tenter d’appliquer les scenes via LWE
USE_LWE_FOR_SCENES = os.environ.get("WPE_USE_LWE", "").strip() == "1"

def _lwe_bin():
    return shutil.which("linux-wallpaperengine") or "linux-wallpaperengine"

# Runner WebView pour wallpapers HTML (type web) — sans LWE
_WEB_RUNNER = Path(__file__).resolve().parent / "wpe_web_wallpaper.py"

def find_video(wp_id):
    folder = WORKSHOP / wp_id
    for f in folder.iterdir() if folder.exists() else []:
        if f.suffix.lower() in VIDEO_EXT:
            return str(f)
    return None

def get_wallpapers():
    wps = []
    if not WORKSHOP.exists(): return wps
    for folder in sorted(WORKSHOP.iterdir()):
        if not folder.is_dir(): continue
        wp_id = folder.name
        proj  = folder / "project.json"
        title, wp_type, preview_path = wp_id, "unknown", None

        if proj.exists():
            try:
                d      = json.loads(proj.read_text(errors="ignore"))
                title  = d.get("title", wp_id)
                wp_type= d.get("type", "unknown")
            except: pass

        # Find preview
        for name in ["preview.gif", "preview.webm", "preview.mp4", "preview.jpg", "preview.png"]:
            if (folder / name).exists():
                preview_path = f"/preview/{wp_id}/{name}"
                break

        # Find video file
        video = find_video(wp_id)
        # Scene = type scene/web/application sans vidéo
        is_scene = video is None and (wp_type in SCENE_TYPES)
        # Web = fichier HTML (project.json "file", index.html, ou n'importe quel .html)
        web_entry = None
        if proj.exists():
            try:
                d = json.loads(proj.read_text(errors="ignore"))
                f = d.get("file", "").strip()
                if f and f.lower().endswith((".html", ".htm")) and (folder / f).exists():
                    web_entry = f
            except Exception:
                pass
        if not web_entry and (folder / "index.html").exists():
            web_entry = "index.html"
        if not web_entry and folder.exists():
            # Type web/scene : chercher tout .html à la racine ou un niveau
            for pattern in ("*.html", "*/*.html", "*.htm", "*/*.htm"):
                for p in folder.glob(pattern):
                    if p.is_file():
                        try:
                            web_entry = str(p.relative_to(folder))
                        except ValueError:
                            web_entry = p.name
                        break
                if web_entry:
                    break

        wps.append({
            "id": wp_id,
            "title": title,
            "type": wp_type,
            "preview": preview_path,
            "has_video": video is not None,
            "video_path": video,
            "is_scene": is_scene,
            "has_web_entry": bool(web_entry),
            "web_entry": web_entry,
        })
    return wps

def get_assignment():
    asgn = {s: "" for s in SCREENS}
    if CONF.exists():
        for line in CONF.read_text().splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                s, _, v = line.partition("=")
                asgn[s.strip()] = v.strip()
    return asgn

def save_conf(asgn):
    CONF.write_text("\n".join(f"{s}={asgn.get(s,'')}" for s in SCREENS) + "\n")

def _wp_lookup():
    return {w["id"]: w for w in get_wallpapers()}

def apply_wallpapers(asgn):
    """Vidéo → mpvpaper. Web (HTML) → wpe_web_wallpaper.py. Scene pur → LWE si activé."""
    subprocess.run(["pkill", "-f", "-9", "mpvpaper"], capture_output=True)
    subprocess.run(["pkill", "-f", "-9", "linux-wallpaperengine"], capture_output=True)
    subprocess.run(["pkill", "-f", "-9", "wpe_web_wallpaper"], capture_output=True)
    time.sleep(0.8)

    wps = _wp_lookup()
    video_list = []
    web_list = []
    scene_list = []
    web_error = None

    for screen, wp_id in asgn.items():
        if not wp_id: continue
        wp = wps.get(wp_id)
        if not wp: continue
        if wp.get("has_video"):
            video_list.append((screen, wp_id))
        elif wp.get("has_web_entry"):
            web_list.append((screen, wp_id))
        elif wp.get("is_scene"):
            scene_list.append((screen, wp_id))

    for screen, wp_id in video_list:
        video = find_video(wp_id)
        if video:
            subprocess.Popen(
                ["mpvpaper", "-o", MPV_OPTS, screen, video],
                start_new_session=True
            )
            time.sleep(0.1)

    # Web (HTML) : runner WebView (X11/XWayland)
    web_error = None
    if web_list and _WEB_RUNNER.exists():
        for screen, wp_id in web_list:
            wp = wps.get(wp_id)
            if not wp: continue
            folder = WORKSHOP / wp_id
            entry = wp.get("web_entry") or "index.html"
            cmd = [sys.executable, str(_WEB_RUNNER), "--output", screen, "--path", str(folder), "--entry", entry]
            proc = subprocess.Popen(
                cmd,
                start_new_session=True,
                cwd=str(folder),
                stderr=subprocess.PIPE,
                env=os.environ.copy(),
            )
            time.sleep(1.0)
            ret = proc.poll()
            if ret is not None and web_error is None:
                try:
                    err = (proc.stderr.read() or b"").decode("utf-8", "replace").strip()
                    web_error = f"WebView quitté (code {ret}): {err}" if err else f"WebView quitté (code {ret})"
                except Exception:
                    web_error = f"WebView quitté (code {ret})"
            time.sleep(0.1)

    # Scenes sans HTML : seulement si LWE activé (WPE_USE_LWE=1)
    if USE_LWE_FOR_SCENES and scene_list:
        lwe = _lwe_bin()
        cmd = [lwe, "--silent"]
        for screen, wp_id in scene_list:
            cmd.extend(["--screen-root", screen, "--bg", wp_id])
        subprocess.Popen(cmd, start_new_session=True)

    # Script de restauration
    lines = ["#!/bin/bash", "pkill -f -9 mpvpaper", "pkill -f -9 linux-wallpaperengine", "pkill -f -9 wpe_web_wallpaper", "sleep 1", ""]
    for screen, wp_id in video_list:
        video = find_video(wp_id)
        if video:
            lines.append(f'mpvpaper -o "{MPV_OPTS}" {screen} "{video}" &')
            lines.append("sleep 0.1")
    if web_list and _WEB_RUNNER.exists():
        for screen, wp_id in web_list:
            wp = wps.get(wp_id)
            if not wp: continue
            folder = WORKSHOP / wp_id
            entry = wp.get("web_entry") or "index.html"
            runner = str(_WEB_RUNNER)
            lines.append(f'python3 "{runner}" --output {screen} --path "{folder}" --entry "{entry}" &')
            lines.append("sleep 0.15")
    if USE_LWE_FOR_SCENES and scene_list:
        lwe = _lwe_bin()
        parts = [lwe, "--silent"]
        for screen, wp_id in scene_list:
            parts.extend(["--screen-root", screen, "--bg", wp_id])
        lines.append(" ".join(f'"{p}"' if " " in p else p for p in parts) + " &")
    lines.append("")
    RESTORE.write_text("\n".join(lines))
    RESTORE.chmod(0o755)
    return {"web_error": web_error}

def apply_switchwall(wp_id):
    """Use HyDE switchwall for non-video wallpapers (images)"""
    script = Path.home() / ".config/quickshell/ii/scripts/colors/switchwall.sh"
    video = find_video(wp_id)
    if video and script.exists():
        subprocess.Popen([str(script), "--image", video], start_new_session=True)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204); self.cors(); self.end_headers()

    def do_GET(self):
        p = urlparse(unquote(self.path)).path

        if p == "/api/wallpapers":    return self.send_json(get_wallpapers())
        if p == "/api/assignment":    return self.send_json(get_assignment())
        if p == "/api/screens":      return self.send_json(SCREENS)
        if p == "/api/capabilities":
            return self.send_json({
                "linux_wallpaperengine": bool(shutil.which("linux-wallpaperengine")),
                "use_scenes_via_lwe": USE_LWE_FOR_SCENES,
                "web_runner_available": _WEB_RUNNER.exists(),
            })

        # Preview files
        if p.startswith("/preview/"):
            parts = p.split("/", 3)
            if len(parts) == 4:
                _, _, wp_id, fname = parts
                fpath = WORKSHOP / wp_id / fname
                if fpath.exists():
                    data = fpath.read_bytes()
                    mime = mimetypes.guess_type(fname)[0] or "application/octet-stream"
                    self.send_response(200); self.cors()
                    self.send_header("Content-Type", mime)
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("Cache-Control", "public, max-age=3600")
                    self.end_headers()
                    self.wfile.write(data); return
            return self.send_json({"error": "not found"}, 404)

        # Static files
        base  = Path(__file__).parent / "app"
        fpath = base / ("index.html" if p == "/" else p.lstrip("/"))
        if fpath.exists() and fpath.is_file():
            data = fpath.read_bytes()
            mime = mimetypes.guess_type(str(fpath))[0] or "text/plain"
            self.send_response(200); self.cors()
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        p    = urlparse(self.path).path
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try: data = json.loads(body)
        except: return self.send_json({"error": "bad json"}, 400)

        if p == "/api/apply":
            asgn = data.get("assignment", {})
            save_conf(asgn)
            wps = _wp_lookup()
            scene_only = sum(1 for sid in asgn.values() if sid and wps.get(sid, {}).get("is_scene") and not wps.get(sid, {}).get("has_web_entry"))
            web_count = sum(1 for sid in asgn.values() if sid and wps.get(sid, {}).get("has_web_entry"))
            extra = apply_wallpapers(asgn)
            out = {"ok": True}
            if extra.get("web_error"):
                out["warning"] = "WebView: " + extra["web_error"]
            elif web_count and not _WEB_RUNNER.exists():
                out["warning"] = "Fonds web assignés mais wpe_web_wallpaper.py introuvable."
            elif scene_only and USE_LWE_FOR_SCENES and not shutil.which("linux-wallpaperengine"):
                out["warning"] = "Scenes assignés mais linux-wallpaperengine introuvable."
            elif scene_only and not USE_LWE_FOR_SCENES:
                out["info"] = "Scenes sans HTML non appliqués (LWE désactivé). Vidéo et web appliqués."
            return self.send_json(out)

        if p == "/api/apply-screen":
            # Apply single screen without touching others
            screen = data.get("screen")
            wp_id  = data.get("wp_id")
            if screen and wp_id:
                asgn = get_assignment()
                asgn[screen] = wp_id
                save_conf(asgn)
                apply_wallpapers(asgn)
                return self.send_json({"ok": True})
            return self.send_json({"error": "missing params"}, 400)

        self.send_json({"error": "not found"}, 404)

if __name__ == "__main__":
    print(f"\n  🎛  WPE Manager v3  →  http://localhost:{PORT}\n")
    HTTPServer(("localhost", PORT), H).serve_forever()
