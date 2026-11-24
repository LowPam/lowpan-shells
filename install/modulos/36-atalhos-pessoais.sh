# Atalhos pessoais do KWin/plasmashell que vêm no perfil (Meta+Q fechar, Meta+Ctrl minimizar, Meta+W maximizar…;
# 2ª rodada do teste, 2026-11-21). Exportados com: install/atalhos-kde.py exportar <perfil>
titulo "$(t "Personal KDE shortcuts" "Atalhos pessoais do KDE")"
if [[ -z "$PERFIL" || ! -f "$PROJETO/install/perfis/$PERFIL/atalhos-kde.json" ]]; then
    st_pula "$(t "none in the profile" "nenhum no perfil")"
else
    _n="$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$PROJETO/install/perfis/$PERFIL/atalhos-kde.json")"
    a_cmd_sis "$_n $(t "shortcuts from the profile" "atalhos do perfil") \"$PERFIL\" (Meta+Q, Meta+Ctrl, Meta+W…)" \
        "python3 -I '$PROJETO/install/atalhos-kde.py' verificar '$PERFIL'" \
        "python3 -I '$PROJETO/install/atalhos-kde.py' aplicar '$PERFIL'" \
        "python3 -I '$PROJETO/install/atalhos-kde.py' desfazer"
    # o que for pulado (efeito ainda não carregado) é aplicado sozinho no próximo login (2026-11-22, VM limpa: o
    # atalho do Cubo ficava "a fazer" até rodar o instalador de novo)
    a_link "$PROJETO/install/atalhos-kde.py" "$BIN/lowpan-atalhos-kde"
    a_link "$PROJETO/system/lowpan-atalhos-pendentes.service" "$UNITS/lowpan-atalhos-pendentes.service"
    a_unit lowpan-atalhos-pendentes.service
fi
