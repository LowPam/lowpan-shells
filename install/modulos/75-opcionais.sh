# Opcionais (§22.3 B) — cada um segue a resposta gravada em respostas.env
titulo "$(t "Optional" "Opcionais")"
_cap="$PROJETO/system/lowpan-shells-capture"
a_cmd_sis "$(t "capture tool" "ferramenta de captura"): $CAPTURA" \
    "'$_cap' status | grep -qE '^(tool|ferramenta): $CAPTURA' && ! '$_cap' status | grep -qE '^  $([[ $CAPTURA == inir ]] && echo '-' || echo '✓') '" \
    "'$_cap' $CAPTURA" "'$_cap' spectacle"
if [[ "$TILING" == sim ]]; then
    # o motor vai compilado no projeto (pkg/, 2026-11-21): a instalação copia e guarda o hash do git do pkg/; um pkg/
    # novo (atualizar) é copiado de novo. Sem hash guardado (instalação antiga) basta o motor existir. O KWin só relê o
    # script num novo login.
    _th="$(git -C "$PROJETO" rev-parse --verify -q HEAD:shell/kwin-tiling/pkg 2>/dev/null || true)"
    a_cmd "$(t "LowPan Tiling engine (build; new login to take effect)" "motor do LowPan Tiling (compilado; vale no próximo login)")" \
        "[ -f '$DATA/kwin/scripts/lowpan-tiling/metadata.json' ] && { [ -z \"\$(anterior tiling-fonte)\" ] || [ \"\$(anterior tiling-fonte)\" = '$_th' ]; }" \
        "'$PROJETO/shell/kwin-tiling/lowpan-install.sh' --sem-compilar && salvar_anterior tiling-fonte '$_th'" "" \
        "$DATA/kwin/scripts/lowpan-tiling" "$DATA/kwin/effects/lowpan_drag_inset"
    # Krohnkite (o LowPan Tiling é o fork dele), 2026-11-22, notebook — decisão do dono: no Plasma fica o tiling que a
    # pessoa usava, com os ajustes e as teclas dela, mas pelo NOSSO motor: o Krohnkite desligado na sessão não para
    # (nem com unloadScript) e brigava com o motor ao trocar para o LowPan. "capturar" guarda o perfil dele
    # (tiling-krohnkite.json), desliga-o no kwinrc (vale no próximo login) e, se estava ligado, liga o tiling no Plasma;
    # o tiling por ambiente aplica o perfil no Plasma. Antes do passo do tiling: o desinstalar desfaz na ordem inversa
    # e o "restaurar" (krohnkiteEnabled original de volta) vem por último.
    if [[ -d "$DATA/kwin/scripts/krohnkite" || -d /usr/share/kwin/scripts/krohnkite ]]; then
        a_cmd_sis "$(t "Krohnkite profile in Plasma (our tiling with its settings and keys; Krohnkite stays off)" "perfil do Krohnkite no Plasma (nosso tiling com os ajustes e as teclas dele; o Krohnkite fica desligado)")" \
            "[ -f '${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells/tiling-krohnkite.json' ] && [ \"\$(kreadconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled)\" = false ]" \
            "'$PROJETO/system/lowpan-shells-tiling' krohnkite capturar" "'$PROJETO/system/lowpan-shells-tiling' krohnkite restaurar"
    fi
    # Tiling por ambiente (2026-11-22): ligado no LowPan (a escolha dele = lowpan.tiling do config.json); o Plasma fica
    # desligado (sem ~/.local/state/lowpan-shells/tiling-plasma). Instalando pelo Plasma, o "on --ambiente iris" só deixa
    # o motor pronto e grava a escolha; teclas, botões e encaixe entram no 1º login do LowPan (lowpan-tiling-sessao).
    a_cmd_sis "$(t "tiling on in LowPan (Plasma stays off; next login)" "tiling ligado no LowPan (o Plasma fica desligado; vale no próximo login)")" \
        "_ts=\"\$('$PROJETO/system/lowpan-shells-tiling' status)\"; grep -qE 'LowPan: (on|ligado)' <<<\"\$_ts\" && grep -qE '^(engine: installed|motor: instalado)' <<<\"\$_ts\" && [ \"\$(kreadconfig6 --file kwinrc --group Plugins --key lowpan-tilingEnabled)\" = true ]" \
        "'$PROJETO/system/lowpan-shells-tiling' on --ambiente iris" "'$PROJETO/system/lowpan-shells-tiling' off --ambiente iris"
else st_pula "tiling ($(t "answer" "resposta"): $TILING)"; fi
if ! pacman -Q kvantum >/dev/null 2>&1; then st_pula "$(t "Kv* colour schemes: kvantum not installed" "esquemas Kv*: kvantum não instalado")"
elif [[ "$KVANTUM" == sim ]]; then
    _kv="$PROJETO/system/lowpan-hide-kvantum-colors"
    if [[ -n "$RAIZ_SISTEMA" ]]; then   # teste: raiz falsa, sem sudo
        a_cmd "$(t "hide Kv* colour schemes" "esconder os esquemas Kv*") ([$(t "test root" "raiz de teste")])" \
            "'$_kv' --raiz '$RAIZ_SISTEMA' status | grep -q 'sim; .* 0$'" \
            "'$_kv' --raiz '$RAIZ_SISTEMA' apply" "'$_kv' --raiz '$RAIZ_SISTEMA' undo"
    else
        a_cmd_sis "$(t "hide Kv* colour schemes (sudo)" "esconder os esquemas Kv* (sudo)")" \
            "'$_kv' status | grep -q 'sim; .* 0$'" \
            "sudo '$_kv' apply" "sudo '$_kv' undo"
    fi
else st_pula "$(t "Kv* colour schemes" "esquemas Kv*") ($(t "answer" "resposta"): $KVANTUM)"; fi
if [[ "$MAGICLAMP" == sim ]]; then
    a_cmd_sis "Magic Lamp $(t "with the LowPan patch" "com o patch do LowPan")" \
        "pacman -Q kwin-effects-yet-another-magic-lamp-reloaded-git" \
        "compilar_pacote '$PROJETO/extras/magic-lamp-reloaded' # makepkg -si" \
        "pacote_para_remover kwin-effects-yet-another-magic-lamp-reloaded-git"
else st_pula "Magic Lamp ($(t "answer" "resposta"): $MAGICLAMP)"; fi
if ! command -v waydroid >/dev/null; then st_pula "Waydroid: $(t "not installed" "não instalado")"
elif [[ "$WAYDROID" == nao ]]; then st_pula "Waydroid ($(t "answer" "resposta"): $(t "no" "não"))"
else
    a_cmd_sis "Waydroid: $(t "fixed screen" "tela fixa") $WAYDROID" \
        "[ \"\$(waydroid prop get persist.waydroid.width 2>/dev/null)x\$(waydroid prop get persist.waydroid.height 2>/dev/null)\" = '$WAYDROID' ]" \
        "waydroid prop set persist.waydroid.width '${WAYDROID%x*}' && waydroid prop set persist.waydroid.height '${WAYDROID#*x}'" \
        "waydroid prop set persist.waydroid.width '' && waydroid prop set persist.waydroid.height ''"
fi
if [[ "$DDCUTIL" == sim ]]; then
    a_cmd "$(t "brightness without ddcutil" "brilho sem ddcutil") (POWERDEVIL_NO_DDCUTIL)" \
        "grep -qx 'POWERDEVIL_NO_DDCUTIL=1' '$CFG/environment.d/90-no-ddcutil.conf'" \
        "mkdir -p '$CFG/environment.d' && echo POWERDEVIL_NO_DDCUTIL=1 > '$CFG/environment.d/90-no-ddcutil.conf'" \
        "" "$CFG/environment.d/90-no-ddcutil.conf"
else st_pula "$(t "brightness without ddcutil" "brilho sem ddcutil") ($(t "answer" "resposta"): $DDCUTIL)"; fi
