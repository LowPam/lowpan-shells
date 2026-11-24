# KWin (§19.2 linhas 18–20, 22, 49, 54)
titulo "KWin"
_tv_src="$PROJETO/shell/third-party/kwin-effects/kwin4_effect_tv"; _tv_dst="$DATA/kwin/effects/kwin4_effect_tv"
a_cmd "$(t "TV effect (project copy, with the fixes)" "efeito TV (cópia do projeto, com as correções)")" \
    "diff -rq --exclude=LICENSE --exclude='*.lowpan-orig' '$_tv_src' '$_tv_dst'" \
    "mkdir -p '$_tv_dst' && rsync -a --delete --exclude=LICENSE --exclude='*.lowpan-orig' '$_tv_src/' '$_tv_dst/'" \
    "" "$_tv_dst"
a_cmd_sis "$(t "TV effect on for open/close (others off)" "efeito TV ligado no abrir/fechar (os outros desligados)")" \
    "[ \"\$(kreadconfig6 --file kwinrc --group Plugins --key kwin4_effect_tvEnabled)\" = true ]" \
    "python3 -I '$PROJETO/install/efeito-abrir.py' guardar '$ESTADO/anterior/efeito-abrir.json' && python3 -I '$PROJETO/shell/scripts/kwin-animations.py' set open kwin4_effect_tv >/dev/null" \
    "if [ -f '$ESTADO/anterior/efeito-abrir.json' ]; then python3 -I '$PROJETO/install/efeito-abrir.py' devolver '$ESTADO/anterior/efeito-abrir.json'; else python3 -I '$PROJETO/shell/scripts/kwin-animations.py' set open \"\$(anterior efeito-abrir)\" >/dev/null; fi"
a_kconf kwinrc Windows DelayFocusInterval 100
# decoração Breeze (§19.2 linha 22; o mesmo que o kwin-decoration.py use-breeze grava). Faz parte do perfil de tema,
# por isso vem depois do 15-separar-tema.
a_kconf kwinrc org.kde.kdecoration2 library org.kde.breeze
a_kconf kwinrc org.kde.kdecoration2 theme Breeze
if pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1; then
    a_klista kwinrc LowPan-Round-Corners Exclusions quickshell
    a_kconf kwinrc LowPan-Round-Corners UseNativeDecorationShadows true
    # cantos por ambiente: o nosso no LowPan, o que a pessoa tinha no Plasma (guarda o dela agora, na instalação)
    a_cmd "$(t "window corners per environment (ours in LowPan, yours in Plasma)" "cantos por ambiente (o nosso no LowPan, o seu no Plasma)")" \
        "[ -f '${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells/cantos-ambiente.json' ]" \
        "'$PROJETO/system/lowpan-cantos-ambiente' agora" "'$PROJETO/system/lowpan-cantos-ambiente' restaurar"
else st_pula "Rounded Corners: $(t "package not installed yet" "pacote ainda não instalado")"; fi
a_klista kwinrc Script-lowpan-tiling floatingClass "[steam_app_]"
a_kconf klaunchrc BusyCursorSettings Timeout 1
