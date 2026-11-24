# Atalhos globais e app de pastas (§19.2 linhas 6, 23, 39, 40)
titulo "$(t "Shortcuts" "Atalhos")"
a_cmd_sis "$(t "global keys (15 + Meta alone), incl. emergency Meta+Ctrl+Alt+P" "teclas globais (15 + Meta sozinha), com a emergência Meta+Ctrl+Alt+P")" \
    "'$PROJETO/system/lowpan-shells-shortcuts' check" \
    "'$PROJETO/system/lowpan-shells-shortcuts' install" \
    "'$PROJETO/system/lowpan-shells-shortcuts' remove"
a_cmd "$(t "folders open with lowpan-files.desktop" "pastas abrem com lowpan-files.desktop") (mimeapps.list)" \
    "grep -qx 'inode/directory=lowpan-files.desktop' '$CFG/mimeapps.list'" \
    "kwriteconfig6 --file mimeapps.list --group 'Default Applications' --key inode/directory lowpan-files.desktop" \
    "" "$CFG/mimeapps.list"
