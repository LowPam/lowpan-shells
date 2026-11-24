# Separar o tema do Plasma ANTES de qualquer mudança visual (decoração, cores, gtk.css).
# O lowpan-theme-profile trata "sem perfil vivo" como "own" (LowPan), e no 1º `off` cria o perfil do Plasma como
# cópia do own: sem este passo, o que o instalador muda para o LowPan vazaria para o Plasma. Aqui o tema que a
# máquina tem agora é guardado como perfil "plasma" e o vivo passa a ser "own" (§22.10, E2).
titulo "$(t "Theme profiles" "Perfis de tema")"
_tp="$PROJETO/shell/scripts/lowpan-theme-profile"
_st="${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells"
separar_tema() {
    mkdir -p "$_st"
    printf 'plasma\n' > "$_st/theme-profile-live"
    # switch own: guarda o vivo (agora "plasma") e, sem perfil own, não escreve nada (sai 1: esperado)
    # gsettings guardados do vivo; só nos testes (--sem-sistema) não lê o dconf real
    if [[ "$SEM_SISTEMA" == 1 ]]; then LOWPAN_THEME_NO_LIVE=1 python3 -I "$_tp" switch own >/dev/null 2>&1 || true
    else python3 -I "$_tp" switch own >/dev/null 2>&1 || true; fi
    printf 'own\n' > "$_st/theme-profile-live"
    [[ -f "$_st/theme-profiles/plasma/ini.json" ]]
}
a_cmd "$(t "current theme saved as the Plasma profile (LowPan changes stay out of Plasma)" "tema atual guardado como perfil do Plasma (as mudanças do LowPan não vazam para o Plasma)")" \
    "[ -f '$_st/theme-profiles/plasma/ini.json' ]" \
    "separar_tema" \
    "" "$_st/theme-profiles/plasma" "$_st/theme-profile-live" "$_st/theme-profile.lock"
