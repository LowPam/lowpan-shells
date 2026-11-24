# Preferências do shell (§19.2 linha 11, §19.3). Antes dos opcionais: a captura e o tiling gravam a própria escolha
# no config.json; o perfil deixa essas chaves para eles (--ignorar), senão perfil e resposta se desfariam a cada execução.
titulo "$(t "Shell preferences" "Preferências do shell")"
if [[ -z "$PERFIL" ]]; then st_pula "$(t "no profile: shell defaults" "sem perfil: valem os padrões do shell")"
elif [[ ! -f "$PROJETO/install/perfis/$PERFIL/perfil.json" ]]; then st_erro "$(t "profile not found" "perfil não encontrado"): $PERFIL"
else
    # captureTool e tiling (com "sim") são gravados pelo próprio script no passo dos opcionais: o perfil não mexe.
    # Fixar aqui fazia o status da captura achar que já estava feito e o script nunca tomava as teclas (teste da E3).
    _op="--ignorar lowpan.captureTool"
    if [[ "$TILING" == sim ]]; then _op+=" --ignorar lowpan.tiling"
    # "não" nunca desliga o que já está ligado: aí a chave fica como está
    elif "$PROJETO/system/lowpan-shells-tiling" status 2>/dev/null | grep -E 'LowPan: (on|ligado)' >/dev/null; then _op+=" --ignorar lowpan.tiling"
    else _op+=" --fixar lowpan.tiling=false"; fi
    _ss=""; [[ "$SEM_SISTEMA" == 1 ]] && _ss=" --sem-sistema"
    # só na 1ª vez (sem config.json): depois o config é do dono — o que ele muda nas Configurações não é "a fazer" e o
    # atualizar não desfaz (2ª rodada do teste). Para reaplicar de propósito: install/perfil.py aplicar <perfil> --parar
    a_cmd "$(t "profile" "perfil") \"$PERFIL\" $(t "in" "em") $(curto "$CFG/illogical-impulse/config.json") ($(t "first install only" "só na 1ª instalação"))" \
        "[ -f '$CFG/illogical-impulse/config.json' ]" \
        "python3 -I '$PROJETO/install/perfil.py' aplicar '$PERFIL' --parar$_ss $_op" \
        "" "$CFG/illogical-impulse/config.json" "$DATA/lowpan-shells/papeis"
fi
