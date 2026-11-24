# Tela de login (§19.2 linhas 44–45; decisão de 2026-11-20: no notebook vai a do LowPan). Pergunta "Tela de login":
#   iris    greetd + tela do LowPan no lugar do gerenciador atual (ele é guardado e volta no desinstalar)
#   manter  fica o gerenciador atual (ex.: SDDM); só as sessões "LowPan" e "Plasma" entram no menu de sessões dele
titulo "$(t "Login screen" "Tela de login")"
_g="$PROJETO/system/lowpan-greeter"
_r=""; _sudo="sudo "; _rot=""
if [[ -n "$RAIZ_SISTEMA" ]]; then _r="--raiz '$RAIZ_SISTEMA'"; _sudo=""; _rot=" ([$(t "test root" "raiz de teste")])"; fi
_passo=a_cmd_sis; [[ -n "$RAIZ_SISTEMA" ]] && _passo=a_cmd
if [[ "$LOGIN" == iris ]]; then
    $_passo "$(t "LowPan login screen (greetd; takes effect on boot)" "tela de login do LowPan (greetd; vale no próximo boot)")$_rot" \
        "'$_g' $_r status | grep -q 'greetd.service' && ! '$_g' $_r status | grep -qE ': (não|no)\$'" \
        "$_sudo'$_g' $_r instalar && $_sudo'$_g' $_r ativar" \
        "$_sudo'$_g' $_r desfazer --tudo"
else
    $_passo "$(t "LowPan and Plasma sessions in the current login screen" "sessões LowPan e Plasma na tela de login atual")$_rot" \
        "'$_g' $_r status | grep -qE '^sessões LowPan/Plasma +: sim'" \
        "$_sudo'$_g' $_r sessoes" \
        "$_sudo'$_g' $_r desfazer --tudo"
fi
# Tela de bloqueio no visual da tela de login (2026-11-23, decisão do dono: nas sessões LowPan e Plasma). Vale no
# próximo login: o KWin herda o PLASMA_DEFAULT_SHELL do drop-in ao iniciar.
a_link "$PROJETO/system/plasma-shell/org.lowpan.shells" "$DATA/plasma/shells/org.lowpan.shells"
a_link "$PROJETO/system/plasma-kwin_wayland-lowpan-bloqueio.conf" "$UNITS/plasma-kwin_wayland.service.d/lowpan-bloqueio.conf"
a_kconf ksplashrc KSplash Engine none
a_kconf ksplashrc KSplash Theme None
