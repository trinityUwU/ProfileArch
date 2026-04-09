#!/bin/bash
file="$1"

if [[ "$file" == *.md ]]; then
    glow "$file"
else
    bat --paging=always "$file"
fi

read -p "Appuie sur Entrée pour fermer..."
