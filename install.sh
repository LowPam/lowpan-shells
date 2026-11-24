#!/usr/bin/env bash
# LowPan Shells — instalador (PLANEJAMENTO §22).
#
#   ./install.sh plano        mostra o que faria, sem mexer em nada (nesta máquina: tudo "já está")
#   ./install.sh instalar     faz as perguntas, mostra o plano, pede OK e aplica (com manifesto e backups)
#   ./install.sh desinstalar  desfaz pelo manifesto, de trás para frente, remove os pacotes que ele instalou e
#                             apaga os dados do shell. SÓ NA SESSÃO PLASMA:
#                             dentro do LowPan ele se recusa (tiraria o shell que desenha a tela)
#   ./install.sh verificar    o plano + saúde (shell, efeitos carregados, efeitos do AUR, fontes, Mesa); só lê
#   ./install.sh atualizar    git pull (se houver remoto) + instalar só o que mudou ou falta
#
# Opções: --sem-sistema  testes numa HOME falsa: não chama pacman/sudo/systemctl/KWin/kglobalaccel
#         --perguntar    refaz as perguntas mesmo com respostas gravadas
#         --sim          não pede OK (usa as respostas gravadas ou os padrões)
#         --modulo NN    só os módulos cujo nome começa com NN (ex.: --modulo 40)
#         --limpar       (sem efeito desde 2026-11-22: o desinstalar sempre apaga os dados do shell)
#         --detalhes     mostra cada item "já está" (senão cada seção resume "✓ N itens em dia")
#         --raiz-sistema DIR  (com --sem-sistema) tela de login e Kvantum rodam com --raiz DIR, sem sudo, e os
#                        pacotes só são resolvidos (pacman --print): testa os blocos de root sem tocar no sistema
set -euo pipefail

PROJETO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export PROJETO
CMD="${1:-plano}"; shift || true
SEM_SISTEMA=0; PERGUNTAR_DE_NOVO=0; SIM=0; SO_MODULO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sem-sistema) SEM_SISTEMA=1 ;;
        --perguntar) PERGUNTAR_DE_NOVO=1 ;;
        --sim) SIM=1 ;;
        --modulo) SO_MODULO="$2"; shift ;;
        --raiz-sistema) RAIZ_SISTEMA="$(realpath -m "$2")"; export RAIZ_SISTEMA; shift ;;
        --limpar) LIMPAR=1 ;;
        --detalhes) DETALHES=1; export DETALHES ;;
        *) echo "opção desconhecida: $1" >&2; exit 2 ;;
    esac
    shift
done
source "$PROJETO/install/lib.sh"

# ---------------------------------------------------------------- respostas (§22.3 B)
VARS=(PERFIL CAPTURA TILING LOGIN KVANTUM MAGICLAMP WAYDROID DDCUTIL ATIVAR)
valor_cfg() {  # caminho.no.config.json → valor atual (ou do perfil, ou vazio)
    python3 -I - "$1" "$CFG/illogical-impulse/config.json" "$PROJETO/install/perfis/${PERFIL:-}/perfil.json" <<'EOF' 2>/dev/null || true
import json, sys
chave, *arqs = sys.argv[1:]
for a in arqs:
    try:
        o = json.load(open(a))
        for k in chave.split("."):
            o = o[k]
        print(str(o).lower()); break
    except Exception:
        pass
EOF
}
padroes() {   # o padrão de cada pergunta = o que já existe (rodar de novo não desfaz nada)
    # o perfil "pessoal" é do dono (fora do público); sem ele, o "padrao" grava os padrões curados do LowPan + o papel de
    # parede do Plasma (2026-11-23: sem perfil nenhum, o shell criava o config.json pelo esquema do Config.qml)
    if [[ -d "$PROJETO/install/perfis/pessoal" ]]; then resposta PERFIL pessoal; else resposta PERFIL padrao; fi
    local c; c="$(valor_cfg lowpan.captureTool)"; resposta CAPTURA "${c:-spectacle}"
    local tl; tl="$(valor_cfg lowpan.tiling)"; [[ "$tl" == false ]] && resposta TILING nao || resposta TILING sim
    # tela de login: a do LowPan (decisão de 2026-11-20 para o notebook); quem quiser o SDDM etc. responde "manter"
    resposta LOGIN iris
    # sem pergunta (2026-11-21): Kvantum instalado → esconder os Kv*; brilho sem ddcutil só em desktop (num notebook o
    # brilho é do painel interno, e o ddcutil só serve a monitor externo); Waydroid não é configurado na instalação
    pacman -Q kvantum >/dev/null 2>&1 && resposta KVANTUM sim || resposta KVANTUM nao
    pacman -Q kwin-effects-yet-another-magic-lamp-reloaded-git >/dev/null 2>&1 && resposta MAGICLAMP sim || resposta MAGICLAMP nao
    resposta WAYDROID nao
    if [[ -f "$CFG/environment.d/90-no-ddcutil.conf" ]] || ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        resposta DDCUTIL sim; else resposta DDCUTIL nao; fi
    resposta ATIVAR try
}
# Depois da 1ª instalação quem manda na captura e no tiling é o estado atual (o dono pode trocar nas Configurações do
# shell): sem isso o verificar acusava "a fazer" e o atualizar desfazia a escolha (2ª rodada do teste, 2026-11-21).
seguir_estado_atual() {
    local c; c="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["lowpan"]["captureTool"])' "$CFG/illogical-impulse/config.json" 2>/dev/null || true)"
    [[ "$c" == inir || "$c" == spectacle ]] && CAPTURA="$c"
    if "$PROJETO/system/lowpan-shells-tiling" status 2>/dev/null | grep -qE '^tiling: (on|ligado)'; then TILING=sim
    elif [[ "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["lowpan"]["tiling"])' "$CFG/illogical-impulse/config.json" 2>/dev/null)" == False ]]; then TILING=nao; fi
    return 0
}

perguntas() {
    titulo "$(t "Questions" "Perguntas")"
    printf '  %s%s%s\n' "$C_DICA" "$(t "Enter keeps the default (●). Nothing changes until you confirm the plan." "Enter fica com o padrão (●). Nada muda até você confirmar o plano.")" "$C_0" >&2
    perguntar_opcao CAPTURA "$(t "Screenshot and recording tool" "Ferramenta de captura de tela e gravação")" \
        "inir|$(t "LowPan Shells (snip, read text, search, record; takes Print/Meta+Shift+S)" "a do LowPan Shells (recorte, ler texto, pesquisar, gravar; fica com Print/Meta+Shift+S)")" \
        "spectacle|$(t "KDE's Spectacle (nothing changes)" "o Spectacle do KDE (nada muda)")"
    perguntar_sn TILING "$(t "Turn on LowPan Tiling (Niri-style columns)?" "Ligar o LowPan Tiling (colunas no estilo do Niri)?")" \
        "$(t "Takes effect on the next login; can be turned off in Settings › Windows › Tiling." "Vale no próximo login; dá para desligar em Configurações › Janelas › Tiling.")"
    local dm; dm="$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)"; dm="${dm##*/}"; dm="${dm%.service}"
    if [[ "$dm" == greetd ]]; then
        perguntar_opcao LOGIN "$(t "Login screen" "Tela de login")" \
            "iris|$(t "the LowPan screen (greetd is already the login manager here)" "a tela do LowPan (o greetd já é o gerenciador de login aqui)")" \
            "manter|$(t "don't touch the login screen; only add the LowPan and Plasma sessions" "não mexer na tela de login; só acrescentar as sessões LowPan e Plasma")"
    else
        perguntar_opcao LOGIN "$(t "Login screen" "Tela de login")" \
            "iris|$(t "the LowPan screen (greetd); " "a tela do LowPan (greetd); o ")${dm:-$(t "current manager" "gerenciador atual")}$(t " comes back on uninstall" " volta no desinstalar")" \
            "manter|$(t "keep " "manter o ")${dm:-$(t "current manager" "gerenciador atual")}$(t "; only the LowPan and Plasma sessions are added to its menu" "; só entram as sessões LowPan e Plasma no menu dele")"
    fi
    # Kvantum, Waydroid e brilho sem ddcutil: sem pergunta (pedido do dono, 2026-11-21) — ver padroes()
    perguntar_sn MAGICLAMP "$(t "Build the Magic Lamp minimize effect with the LowPan patch?" "Compilar o efeito de minimizar Magic Lamp com o patch do LowPan?")" \
        "$(t "Optional; takes a few minutes and needs sudo." "Opcional; leva alguns minutos e pede sudo.")"
    perguntar_opcao ATIVAR "$(t "Turn LowPan Shells on at the end" "Ligar o LowPan Shells no fim")" \
        "try|$(t "only in this session (the next login is Plasma again) — recommended the first time" "só nesta sessão (o próximo login volta ao Plasma) — recomendado na 1ª vez")" \
        "on|$(t "now and on every login" "agora e em todo login")"
}

# ---------------------------------------------------------------- execução
# saída inesperada no meio dos módulos (set -e) não pode ser muda: na VM limpa o instalador voltou ao prompt sem dizer
# nada (2026-11-21, última linha "cond && ação" de um módulo virando o status do source)
_parada_muda() {
    local rc=$?
    if [[ $rc -ne 0 && -n "${MODULO:-}" && "${_MODULOS_OK:-0}" != 1 ]]; then
        printf '\n  %s%s%s\n' "$C_ERRO" "$(t "the installer stopped inside module $MODULO (exit $rc) — please report it" "o instalador parou dentro do módulo $MODULO (saída $rc) — avise")" "$C_0" >&2
    fi
}
trap _parada_muda EXIT
rodar_modulos() {
    local m nome
    _MODULOS_OK=0
    MOD_I=0; MOD_N=$(ls "$PROJETO"/install/modulos/[0-9]*.sh | wc -l)
    for m in "$PROJETO"/install/modulos/[0-9]*.sh; do
        nome="$(basename "$m" .sh)"
        [[ -n "$SO_MODULO" && "$nome" != "$SO_MODULO"* ]] && continue
        MODULO="$nome"; MOD_I=$((MOD_I + 1))
        # shellcheck disable=SC1090
        source "$m"
        if [[ "$nome" == 00-* && "$MODO" == instalar && "${CHECAGEM_ERRO:-0}" == 1 ]]; then
            st_erro "$(t "checks failed: nothing was changed" "a checagem falhou: nada foi mudado")"; _MODULOS_OK=1; exit 1
        fi
    done
    fecha_secao; MOD_I=0; MOD_N=0
    _MODULOS_OK=1
}
# contagem colorida: _cont cor ícone número "rótulo"
_cont() { printf '%s%s %s%s %s%s' "$1" "$2" "$3" "$C_0" "$C_DICA$4" "$C_0"; }
_linha_info() { printf '  %s%s%*s%s %s\n' "$C_DICA" "$1" $(( 11 - ${#1} )) "" "$C_0" "$2"; }   # ${#}: conta letras, não bytes
resumo() {
    titulo "$(t "Summary" "Resumo")"
    local sep="$C_LINHA  ·  $C_0"
    if [[ "$MODO" == plano ]]; then
        printf '  %s%s%s%s%s%s%s%s%s\n' "$(_cont "$C_VAI" → "$N_VAI" "$(t "to do" "a fazer")")" "$sep" \
            "$(_cont "$C_OK" ✓ "$N_OK" "$(t "in place" "em dia")")" "$sep" "$(_cont "$C_PULA" – "$N_PULA" "$(t "skipped" "pulados")")" "$sep" \
            "$(_cont "$C_AVISO" ! "$N_AVISO" "$(t "notes" "avisos")")" "$sep" "$(_cont "$C_ERRO" ✗ "$N_ERRO" "$(t "errors" "erros")")"
        [[ -f "$RESPOSTAS" ]] && _linha_info "$(t "answers" "respostas")" "$(curto "$RESPOSTAS")" \
            || _linha_info "$(t "answers" "respostas")" "$(t "defaults (nothing saved yet)" "padrões (nada gravado ainda)")"
        _linha_info "" "$(for v in "${VARS[@]}"; do printf '%s%s%s=%s ' "$C_DICA" "${v,,}" "$C_0" "${!v:-—}"; done)"
    else
        printf '  %s%s%s%s%s%s%s\n' "$(_cont "$C_OK" ✓ "$N_FEITO" "$(t "done" "feitos")")" "$sep" \
            "$(_cont "$C_PULA" ✓ "$N_OK" "$(t "already in place" "já estavam")")" "$sep" "$(_cont "$C_PULA" – "$N_PULA" "$(t "skipped" "pulados")")" "$sep" \
            "$(_cont "$C_ERRO" ✗ "$N_ERRO" "$(t "errors" "erros")")"
        _linha_info "$(t "manifest" "manifesto")" "$(curto "$MANIFESTO")"
        [[ -n "$REGISTRO" ]] && _linha_info "$(t "log" "registro")" "$(curto "$REGISTRO")"
        local prox=""
        [[ "$TILING" == sim ]] && prox+="$(t "LowPan Tiling: next login" "LowPan Tiling: no próximo login")"
        # só enquanto o greetd não é quem está rodando (depois do reinício a tela de login já vale)
        if [[ "$LOGIN" == iris ]] && ! systemctl is-active -q greetd 2>/dev/null; then
            prox+="${prox:+ · }$(t "login screen: next boot" "tela de login: no próximo boot")"; fi
        [[ -n "$prox" ]] && _linha_info "$(t "takes effect" "vale")" "$prox"
        _linha_info "$(t "emergency" "emergência")" "Meta+Ctrl+Alt+P · lowpan-shells-switch off · ./install.sh desinstalar"
    fi
}

# Sair da sessão no fim (pedido do dono na 4ª rodada do teste): o tiling, os efeitos e atalhos que só existem com o
# efeito carregado, o tema de ícones nos apps já abertos e a Meta+F só valem por inteiro num login novo. Pergunta com
# S como padrão; não sai no --sim (atualizar), nos testes (--sem-sistema) nem quando nada foi feito.
# Pede ao KDE para sair/reiniciar 2 s DEPOIS de o instalador terminar, num processo à parte: chamado direto, o KDE
# mandava o terminal fechar antes de o shell redesenhar o prompt, e o kitty perguntava "Are you sure… It is running:
# /usr/bin/zsh" (notebook, 2026-11-22) — parecia que algo ainda rodava. $1 = logout | logoutAndReboot
fim_de_sessao() {
    local alt
    if [[ "$1" == logout ]]; then alt="loginctl terminate-session '${XDG_SESSION_ID:-}'"; else alt="systemctl reboot"; fi
    echo "  $(t "in 2 seconds…" "em 2 segundos…")"
    setsid -f sh -c "sleep 2; qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.$1 >/dev/null 2>&1 || $alt >/dev/null 2>&1" \
        </dev/null >/dev/null 2>&1 \
        || st_erro "$(t "could not log out/restart: do it from the menu" "não consegui sair/reiniciar: faça pelo menu")"
}

sair_no_fim() {
    [[ "$SIM" == 1 || "$SEM_SISTEMA" == 1 || "$N_FEITO" == 0 ]] && return 0
    # tela de login do LowPan recém-ligada (greetd é o display-manager, mas quem roda ainda é o antigo, ex.: sddm): sair
    # da sessão voltaria ao gerenciador antigo — só um reinício troca (VM limpa, 2026-11-22)
    local dm; dm="$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)"
    if [[ "$dm" == */greetd.service ]] && ! systemctl is-active -q greetd 2>/dev/null; then
        printf '\n  %s%s%s\n' "$C_DICA" "$(t "The LowPan login screen only starts after a restart (the current login manager is still running). On it, choose the LowPan session." "A tela de login do LowPan só entra depois de reiniciar (o gerenciador de login atual ainda está rodando). Nela, escolha a sessão LowPan.")" "$C_0" >&2
        confirmar "$(t "Restart the computer now (save your work in open apps first)?" "Reiniciar o computador agora (salve antes o que estiver aberto)?")" s || {
            echo "  $(t "ok — restart later to use the LowPan login screen" "ok — reinicie depois para usar a tela de login do LowPan")"; return 0; }
        fim_de_sessao logoutAndReboot
        return 0
    fi
    printf '\n  %s%s%s\n' "$C_DICA" "$(t "Some settings only take full effect after logging in again. On the login screen choose the LowPan session." "Algumas configurações só valem por inteiro depois de entrar de novo. Na tela de login, escolha a sessão LowPan.")" "$C_0" >&2
    confirmar "$(t "Log out now (save your work in open apps first)?" "Sair da sessão agora (salve antes o que estiver aberto)?")" s || {
        echo "  $(t "ok — log out later (Meta+Shift+Q → Log out)" "ok — saia depois (Meta+Shift+Q → Sair)")"; return 0; }
    fim_de_sessao logout
}

# Depois de remover: a tela de login antiga volta só no próximo boot e o KWin/plasmashell desta sessão ainda têm os
# efeitos, atalhos e fontes carregados — um reinício deixa a máquina como antes (pedido do dono, 2026-11-22)
reiniciar_depois_de_remover() {
    [[ "$SIM" == 1 || "$SEM_SISTEMA" == 1 ]] && return 0
    printf '\n  %s%s%s\n' "$C_DICA" "$(t "LowPan Shells was removed. Restart to finish: the login screen and this session still have the old state loaded." "O LowPan Shells foi removido. Reinicie para terminar: a tela de login e esta sessão ainda estão com o estado antigo carregado.")" "$C_0" >&2
    confirmar "$(t "Restart the computer now (save your work in open apps first)?" "Reiniciar o computador agora (salve antes o que estiver aberto)?")" s || {
        echo "  $(t "ok — restart later" "ok — reinicie depois")"; return 0; }
    fim_de_sessao logoutAndReboot
    return 0
}

case "$CMD" in plano|instalar|desinstalar|verificar|atualizar) cabecalho "$(case "$CMD" in plano) t "plan (nothing changes)" "plano (nada muda)" ;; instalar) t "install" "instalar" ;; desinstalar) t "uninstall" "desinstalar" ;; verificar) t "check" "verificar" ;; atualizar) t "update" "atualizar" ;; esac)" ;; esac
case "$CMD" in
    plano)
        MODO=plano; carregar_respostas; [[ -f "$RESPOSTAS" ]] && seguir_estado_atual; padroes; rodar_modulos; resumo ;;
    instalar)
        MODO=plano; carregar_respostas
        # com --perguntar as respostas gravadas viram o padrão de cada pergunta
        padroes
        # pergunta na 1ª vez (sem respostas gravadas) ou com --perguntar; reexecução usa o que já foi respondido
        if [[ "$SIM" != 1 && ( ! -f "$RESPOSTAS" || "$PERGUNTAR_DE_NOVO" == 1 ) ]]; then MODO=instalar; perguntas; MODO=plano
        elif [[ -f "$RESPOSTAS" ]]; then seguir_estado_atual; fi
        rodar_modulos; resumo
        if [[ "$N_VAI" == 0 ]]; then echo; echo "  $(t "nothing to do" "nada a fazer")"; exit 0; fi
        if [[ "$SIM" != 1 ]]; then
            confirmar "$(t "Apply the plan above?" "Aplicar o plano acima?")" s || { echo "$(t "nothing changed (answers not saved)" "nada mudou (respostas não gravadas)")"; exit 0; }
        fi
        # só agora: antes, um "não" no plano deixava as respostas gravadas e a execução seguinte nem perguntava
        gravar_respostas "${VARS[@]}"
        sudo_preparar
        inventario_antes   # só na 1ª instalação: o desinstalar apaga só o que não estava aqui
        rm -f "$ESTADO/desinstalado"   # instalar de novo libera o switch e o login da sessão LowPan
        N_OK=0; N_VAI=0; N_PULA=0; N_AVISO=0; N_ERRO=0
        MODO=instalar; rodar_modulos
        if [[ "$SEM_SISTEMA" != 1 ]]; then
            qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
            kbuildsycoca6 >/dev/null 2>&1 || true
        fi
        resumo
        sair_no_fim ;;
    desinstalar)
        if [[ "$SEM_SISTEMA" != 1 ]] && no_iris; then
            st_erro "$(t "you are in the LowPan session: uninstalling here would leave the session without a desktop" "você está na sessão LowPan: desinstalar aqui deixaria a sessão sem ambiente gráfico")"
            printf '\n  %s%s%s\n' "$C_PERG" "$(t "Do this first:" "Faça antes:")" "$C_0" >&2
            printf '    1. %s\n    2. %s\n    3. %s\n\n' \
                "$(t "Log out (Meta+Shift+Q → Log out)" "Saia da sessão (Meta+Shift+Q → Sair)")" \
                "$(t "On the login screen choose the Plasma session and log in" "Na tela de login, escolha a sessão Plasma e entre")" \
                "$(t "Run again:" "Rode de novo:") $PROJETO/install.sh desinstalar" >&2
            printf '  %s%s%s\n\n' "$C_DICA" "$(t "If you only used 'try' inside a Plasma session: Meta+Ctrl+Alt+P brings Plasma back, then run it again." "Se você só usou o 'try' dentro de uma sessão Plasma: Meta+Ctrl+Alt+P traz o Plasma de volta; depois rode de novo.")" "$C_0" >&2
            exit 1
        fi
        if [[ "$SIM" != 1 ]]; then
            confirmar "$(t "Uninstall LowPan Shells?" "Desinstalar LowPan Shells?")" n || { echo "$(t "nothing changed" "nada mudou")"; exit 0; }
        fi
        # sudo: os passos de root do manifesto e a remoção dos pacotes (linhas "pacotes")
        [[ "$SEM_SISTEMA" == 1 ]] || { N_SUDO=$(grep -cE 'sudo |	pacotes	' "$MANIFESTO" 2>/dev/null || true); sudo_preparar; }
        desinstalar
        reiniciar_depois_de_remover ;;
    verificar)
        MODO=plano; carregar_respostas; [[ -f "$RESPOSTAS" ]] && seguir_estado_atual; padroes; rodar_modulos; saude; resumo
        [[ "$N_VAI" == 0 && "$N_ERRO" == 0 && "$N_SAUDE" == 0 ]] ;;
    atualizar)
        titulo "$(t "Update" "Atualizar")"
        if git -C "$PROJETO" remote | grep -q .; then
            git -C "$PROJETO" pull --ff-only || { st_erro "$(t "git pull failed: local changes? nothing else done" "git pull falhou: mudanças locais? nada mais foi feito")"; exit 1; }
        else st_pula "git pull ($(t "no remote" "sem remoto"))"; fi
        # reaplica só o que mudou ou falta (efeito TV recopiado, tiling recompilado se o fonte mudou, módulos novos)
        _arg=(instalar --sim); [[ "$SEM_SISTEMA" == 1 ]] && _arg+=(--sem-sistema)
        [[ -n "${RAIZ_SISTEMA:-}" ]] && _arg+=(--raiz-sistema "$RAIZ_SISTEMA")
        exec "$0" "${_arg[@]}" ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
