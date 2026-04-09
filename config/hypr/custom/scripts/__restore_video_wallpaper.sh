#!/bin/bash
pkill -f -9 mpvpaper
pkill -f -9 linux-wallpaperengine
pkill -f -9 wpe_web_wallpaper
sleep 1

mpvpaper -o "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0" DP-1 "/home/trinity/.local/share/Steam/steamapps/workshop/content/431960/2945283312/宇宙飞船 窗外 4k动态壁纸.mp4" &
sleep 0.1
mpvpaper -o "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0" HDMI-A-1 "/home/trinity/.local/share/Steam/steamapps/workshop/content/431960/2820429124/Lucy Edgerunner.mp4" &
sleep 0.1
