# Efeitos de janela do perfil (3ª rodada do teste, 2026-11-21: o Achatar2 não vinha). O Achatar2 (Squash2, KDE Store,
# Leo_sk) com as nossas correções fica em extras/ (§19.2 linha 14); as animações por categoria (minimizar, maximizar,
# tela cheia, troca de área) vêm do perfil e passam pelo kwin-animations.py, que também ajusta as esperas do tiling.
# Abrir/fechar é do 40-kwin (efeito TV).
titulo "$(t "Window effects" "Efeitos das janelas")"
_sq="$DATA/kwin/effects/kwin4_effect_squash2"
if [[ -f "$PROJETO/extras/squash2-main.js" ]]; then
    a_cmd "$(t "Squash2 minimize effect (project copy)" "efeito de minimizar Achatar2 (cópia do projeto)")" \
        "cmp -s '$PROJETO/extras/squash2-main.js' '$_sq/contents/code/main.js' && cmp -s '$PROJETO/extras/squash2-metadata.json' '$_sq/metadata.json' && cmp -s '$PROJETO/extras/squash2-config-main.xml' '$_sq/contents/config/main.xml'" \
        "mkdir -p '$_sq/contents/code' '$_sq/contents/config' && cp '$PROJETO/extras/squash2-metadata.json' '$_sq/metadata.json' && cp '$PROJETO/extras/squash2-main.js' '$_sq/contents/code/main.js' && cp '$PROJETO/extras/squash2-config-main.xml' '$_sq/contents/config/main.xml'" \
        "" "$_sq"
else st_pula "Achatar2: $(t "not in this copy of the project (extras/)" "não está nesta cópia do projeto (extras/)")"; fi
# sem perfil (a instalação pública, 2026-11-23): o padrão do projeto = Achatar2 no minimizar (decisão do dono); a
# Lâmpada Mágica é a alternativa (pergunta do instalador + Configurações › Janelas). As outras categorias ficam como
# o KDE deixou.
_an="$PROJETO/install/perfis/${PERFIL:-_}/animacoes.json"
[[ -n "$PERFIL" && -f "$_an" ]] || _an="$PROJETO/install/animacoes-padrao.json"
if [[ -f "$_an" ]]; then
    _anim="python3 -I '$PROJETO/shell/scripts/kwin-animations.py'"
    while IFS=$'\t' read -r _cat _ef; do
        [[ -n "$_cat" ]] || continue
        a_cmd_sis "$(t "animation" "animação") $_cat: $_ef" \
            "$_anim state | python3 -I -c 'import json,sys; sys.exit(0 if any(c[\"id\"]==\"$_cat\" and c[\"active\"]==\"$_ef\" for c in json.load(sys.stdin)[\"categories\"]) else 1)'" \
            "salvar_anterior animacao-$_cat \"\$($_anim state | python3 -I -c 'import json,sys; print(next(c[\"active\"] for c in json.load(sys.stdin)[\"categories\"] if c[\"id\"]==\"$_cat\") or \"none\")')\" && $_anim set $_cat $_ef >/dev/null" \
            "$_anim set $_cat \"\$(anterior animacao-$_cat)\" >/dev/null"
    done < <(python3 -I -c 'import json,sys; [print(f"{k}\t{v}") for k,v in json.load(open(sys.argv[1])).items() if v]' "$_an")
fi
