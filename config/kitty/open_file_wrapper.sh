#!/bin/bash
file="$1"

kitty @ launch --type=overlay --hold sh -c "
if [[ '$file' == *.md ]]; then
    glow '$file'
else
    bat --paging=always '$file'
fi
echo ''
echo 'Appuie sur une touche pour fermer...'
read -n 1
"
