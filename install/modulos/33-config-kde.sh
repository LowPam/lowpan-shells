# Configurações pessoais do KDE que vêm no perfil (3ª rodada do teste, 2026-11-21): cantos/contorno/sombra das janelas
# (Rounded Corners), efeitos ligados e as opções deles, 4 áreas de trabalho, foco, luz noturna, Alt+Tab, sombra do
# Breeze, botões das janelas GTK, o Kate. Depois do 15 (vão para o perfil de tema do LowPan) e do 32 (efeitos), antes
# dos atalhos pessoais (o atalho do cubo só existe com o efeito ligado). Exportar: install/config-kde.py exportar <perfil>
titulo "$(t "Personal KDE settings" "Configurações pessoais do KDE")"
if [[ -z "$PERFIL" || ! -f "$PROJETO/install/perfis/$PERFIL/config-kde.json" ]]; then
    st_pula "$(t "none in the profile" "nenhuma no perfil")"
else
    # seletor de tarefas (Alt+Tab) do projeto, no estilo macOS (§21.47; volta em 2026-11-21 no lugar do Flip): o
    # perfil grava kwinrc [TabBox] LayoutName=lowpan-mac, então o pacote tem de existir antes
    a_link "$PROJETO/shell/kwin-tabbox/lowpan-mac" "$DATA/kwin/tabbox/lowpan-mac"
    _ck="LOWPAN_SEM_SISTEMA=$SEM_SISTEMA python3 -I '$PROJETO/install/config-kde.py'"
    # Kate aberto: ao fechar (no logoff do fim) ele regrava a configuração inteira que tem na memória por cima da do
    # perfil, e a pasta das ferramentas externas também (5ª rodada do teste: tema e opções do Kate "não vinham")
    if [[ "$SEM_SISTEMA" != 1 ]] && pgrep -u "$(id -u)" -x kate >/dev/null 2>&1; then
        if [[ "$MODO" == plano ]]; then
            st_aviso "$(t "Kate is open: close it before applying (it would overwrite its settings when closing)" "o Kate está aberto: feche antes de aplicar (ao fechar ele regravaria as configurações dele)")"
        else
            while pgrep -u "$(id -u)" -x kate >/dev/null 2>&1; do
                printf '\n  %s%s%s ' "$C_PERG" "$(t "Close Kate (save what you need) and press Enter…" "Feche o Kate (salve o que precisar) e tecle Enter…")" "$C_0" >&2
                ler >/dev/null
            done
        fi
    fi
    a_cmd "$(t "window corners/outline/shadow, effects, 4 desktops, focus, Kate… (profile" "cantos/contorno/sombra das janelas, efeitos, 4 áreas de trabalho, foco, Kate… (perfil") \"$PERFIL\")" \
        "$_ck verificar '$PERFIL'" \
        "$_ck aplicar '$PERFIL' >/dev/null" \
        "$_ck desfazer >/dev/null"
fi
