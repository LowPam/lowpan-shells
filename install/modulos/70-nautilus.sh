# Nautilus do LowPan (§19.2 linhas 32–36, 38–41, 46; decisão de 2026-11-20: vai junto)
titulo "Nautilus"
a_cmd "$(t "LowPanNautilus theme, launchers, D-Bus and gtk.css" "tema LowPanNautilus, lançadores, D-Bus e gtk.css")" \
    "'$PROJETO/system/lowpan-nautilus-tema' status" \
    "'$PROJETO/system/lowpan-nautilus-tema' instalar && '$PROJETO/system/lowpan-nautilus-tema' css-usuario" \
    "'$PROJETO/system/lowpan-nautilus-tema' desfazer --tudo" "$CFG/gtk-4.0/gtk.css"
a_unit localsearch-3.service mask
a_unit localsearch-control-3.service mask
a_klista kwinrc Script-lowpan-tiling floatingClass org.gnome.Nautilus
# if (não "&&"): como última linha do módulo, o "falso" sem o Rounded Corners virava o status do source e o set -e
# encerrava o instalador sem mensagem (VM limpa, 2026-11-21)
if pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1; then
    a_klista kwinrc LowPan-Round-Corners Exclusions org.gnome.Nautilus
fi
