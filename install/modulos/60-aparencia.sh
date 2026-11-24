# Esquema de cores do LowPan (§19.2 linha 47). Vai para o perfil "own"; o do Plasma ficou guardado no 15-separar-tema.
titulo "$(t "Appearance" "Aparência")"
a_link "$PROJETO/system/color-schemes/BreezeDarkLowPan.colors" "$DATA/color-schemes/BreezeDarkLowPan.colors"
_live="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells/theme-profile-live" 2>/dev/null || echo own)"
if [[ "$_live" == own ]]; then
    a_cmd_sis "$(t "colour scheme" "esquema de cores") Breeze Dark (LowPan) $(t "in the LowPan profile" "no perfil do LowPan")" \
        "[ \"\$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)\" = BreezeDarkLowPan ]" \
        "salvar_anterior esquema-cores \"\$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)\" && plasma-apply-colorscheme BreezeDarkLowPan" \
        "plasma-apply-colorscheme \"\$(anterior esquema-cores)\""
else
    st_pula "$(t "colour scheme: the Plasma profile is live; choose Breeze Dark (LowPan) in Settings › Colours while in LowPan" "esquema de cores: o perfil vivo é o do Plasma; escolha Breeze Dark (LowPan) em Configurações › Cores estando no LowPan")"
fi
# Fontes do LowPan (Roboto Flex, Readex Pro, Gabarito, Space Grotesk, Oxanium; OFL): no projeto desde 2026-11-22, ligadas
# na pasta de fontes da conta. Vinham do AUR, e o otf-space-grotesk baixava 31 MB e compilava com fontforge + Go.
_fo="$DATA/fonts/lowpan-shells"
a_cmd "$(t "LowPan fonts (Roboto Flex, Readex Pro, Gabarito, Space Grotesk, Oxanium)" "fontes do LowPan (Roboto Flex, Readex Pro, Gabarito, Space Grotesk, Oxanium)")" \
    "[ \"\$(readlink '$_fo')\" = '$PROJETO/system/fonts' ] && fc-list : file | grep -F '$_fo/' >/dev/null" \
    "mkdir -p '$DATA/fonts' && ln -sfn '$PROJETO/system/fonts' '$_fo' && fc-cache '$DATA/fonts'" \
    "rm -f '$_fo' && { fc-cache '$DATA/fonts' 2>/dev/null || true; }"
# Sem --notify (2026-11-22): o plasmashell que ainda roda recarregava os ícones na hora e caía (duas threads montando o
# KIconTheme juntas → malloc abort; notebook do dono). O tema é do LowPan: vale quando ele sobe / no próximo login.
# Tema de ícones LowPan (4ª rodada do teste: não vinha). Vai no projeto (system/icons, base McMojave-circle-light) e
# vale só no perfil do LowPan — o Plasma guarda o dele no perfil "plasma" (15-separar-tema). O shell segue o do sistema
# (appearance.iconTheme vazio no perfil).
a_link "$PROJETO/system/icons/icons-lowpan" "$DATA/icons/icons-lowpan"
if [[ "$_live" == own ]]; then
    a_cmd_sis "$(t "icon theme" "tema de ícones") LowPan $(t "in the LowPan profile" "no perfil do LowPan")" \
        "[ \"\$(kreadconfig6 --file kdeglobals --group Icons --key Theme)\" = icons-lowpan ]" \
        "salvar_anterior tema-icones \"\$(kreadconfig6 --file '$CFG/kdeglobals' --group Icons --key Theme)\" && kwriteconfig6 --file kdeglobals --group Icons --key Theme icons-lowpan" \
        "if [ -n \"\$(anterior tema-icones)\" ]; then kwriteconfig6 --file kdeglobals --group Icons --key Theme \"\$(anterior tema-icones)\"; else python3 -I '$PROJETO/install/apagar-chave.py' '$CFG/kdeglobals' Icons Theme; fi"
else
    st_pula "$(t "icon theme: the Plasma profile is live; choose LowPan in Settings › Icons while in LowPan" "tema de ícones: o perfil vivo é o do Plasma; escolha LowPan em Configurações › Ícones estando no LowPan")"
fi

# Cores do KDE para os apps GTK (~/.config/gtk-4.0/colors.css, do módulo gtkconfig do kded): o tema do Nautilus usa
# os @*_breeze de lá. Numa instalação mínima (plasma-desktop) o kde-gtk-config não vinha e o Nautilus ficou
# transparente (VM limpa, 2026-11-22). O módulo grava tudo quando carrega: recarregar depois de instalar o pacote
# vale já nesta sessão (senão só no próximo login). Depois: nautilus -q, para ele reler o CSS.
_gtkcores() {
    qdbus6 org.kde.kded6 /kded org.kde.kded6.unloadModule gtkconfig >/dev/null 2>&1 || true
    qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule gtkconfig >/dev/null 2>&1 || true
    local i; for i in 1 2 3 4 5 6; do grep -q theme_bg_color_breeze "$CFG/gtk-4.0/colors.css" 2>/dev/null && break; sleep 0.5; done
    command -v nautilus >/dev/null && nautilus -q >/dev/null 2>&1 || true
    grep -q theme_bg_color_breeze "$CFG/gtk-4.0/colors.css"
}
a_cmd_sis "$(t "KDE colours for GTK apps (Nautilus)" "cores do KDE para os apps GTK (Nautilus)")" \
    "grep -q theme_bg_color_breeze '$CFG/gtk-4.0/colors.css' 2>/dev/null" \
    "_gtkcores" ""
