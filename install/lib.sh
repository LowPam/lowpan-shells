# LowPan Shells — biblioteca do instalador (PLANEJAMENTO §22). Carregada pelo install.sh; não roda sozinha.
#
# Cada ação é uma primitiva "a_*". A mesma chamada serve aos dois modos:
#   MODO=plano     só confere e mostra: "já está", "vai criar", "vai mudar A → B", "pulado: motivo"
#   MODO=instalar  confere; se faltar, guarda o valor/arquivo antigo, aplica e escreve uma linha no manifesto
# O desinstalar (E5) lê o manifesto de trás para frente.
# shellcheck shell=bash

PROJETO="${PROJETO:?}"
ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells/install"
MANIFESTO="$ESTADO/manifesto.tsv"
RESPOSTAS="$ESTADO/respostas.env"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
UNITS="$CFG/systemd/user"
BIN="$HOME/.local/bin"
MODO="${MODO:-plano}"
SEM_SISTEMA="${SEM_SISTEMA:-0}"   # 1 = testes numa HOME falsa: sem pacman, sudo, systemctl, D-Bus
RAIZ_SISTEMA="${RAIZ_SISTEMA:-}"  # com --sem-sistema: greeter e Kvantum rodam com --raiz nesta pasta, pacotes só listados
N_SUDO=0                          # passos pendentes que pedem sudo (o instalar pede a senha uma vez antes)
MODULO="?"
N_OK=0; N_VAI=0; N_PULA=0; N_AVISO=0; N_FEITO=0; N_ERRO=0
BACKUP_DIR=""

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) LP_PT=1 ;; *) LP_PT=0 ;; esac
t() { if [[ $LP_PT == 1 ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ---------------------------------------------------------------- aparência (2026-11-22: interface "moderna")
# Cores em 24 bits quando o terminal aceita (COLORTERM=truecolor/24bit; kitty, Konsole), senão as 8 básicas; sem
# terminal (ou NO_COLOR) sem cor. Também com a saída num `| tee arquivo`: aí o stdout é pipe, mas o stdin é o terminal.
DETALHES="${DETALHES:-0}"   # --detalhes: mostra cada "já está" (senão cada seção resume "✓ N em dia")
if [[ -z "${NO_COLOR:-}" && ( -t 1 || -t 0 ) ]]; then
    if [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* || "${TERM:-}" == *kitty* ]]; then
        rgb() { printf '\e[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
    else
        rgb() { local r=$1 g=$2 b=$3; printf '\e[3%dm' "$(( (r > 127) + 2 * (g > 127) + 4 * (b > 127) ))"; }
    fi
    C_0=$'\e[0m'; C_NEG=$'\e[1m'; C_DICA=$'\e[2m'
    C_OK="$(rgb 120 220 150)"; C_VAI="$(rgb 120 190 255)"; C_PULA="$(rgb 120 124 134)"; C_AVISO="$(rgb 255 190 90)"
    C_ERRO=$'\e[1m'"$(rgb 255 105 105)"; C_TIT=$'\e[1m'"$(rgb 230 232 240)"; C_ACENTO="$(rgb 255 158 64)"
    C_PERG=$'\e[1m'"$(rgb 240 240 245)"; C_OPC="$(rgb 190 150 255)"; C_PAD=$'\e[1m'"$(rgb 120 220 150)"
    C_LINHA="$(rgb 70 74 86)"
    COR=1
else
    rgb() { :; }
    C_0=""; C_NEG=""; C_DICA=""; C_OK=""; C_VAI=""; C_PULA=""; C_AVISO=""; C_ERRO=""; C_TIT=""; C_ACENTO=""
    C_PERG=""; C_OPC=""; C_PAD=""; C_LINHA=""; COR=0
fi
LARG=$(( $(tput cols 2>/dev/null || echo 80) )); (( LARG > 78 )) && LARG=78; (( LARG < 50 )) && LARG=50
repete() { local i s=""; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }
# degradê laranja → violeta (as cores do relógio e dos destaques do LowPan) letra a letra
degrade() {
    local txt="$1" n=${#1} i r g b
    if [[ $COR != 1 ]]; then printf '%s' "$txt"; return; fi
    for ((i = 0; i < n; i++)); do
        r=$(( 255 - (255 - 176) * i / (n > 1 ? n - 1 : 1) )); g=$(( 158 - (158 - 132) * i / (n > 1 ? n - 1 : 1) ))
        b=$(( 64 + (255 - 64) * i / (n > 1 ? n - 1 : 1) ))
        printf '%s\e[1m%s' "$(rgb $r $g $b)" "${txt:i:1}"
    done
    printf '%s' "$C_0"
}

# ---------------------------------------------------------------- saída
SECAO_OK=0                      # "já está" guardados da seção atual (resumidos no fim dela)
MOD_I=0; MOD_N=0                # número da seção (módulo) e total, para o "03/17"
fecha_secao() {
    if (( SECAO_OK > 0 && DETALHES != 1 )); then
        printf '  %s✓ %s%s\n' "$C_PULA" "$( (( SECAO_OK == 1 )) && t "1 item already in place" "1 item em dia" || t "$SECAO_OK items already in place" "$SECAO_OK itens em dia")" "$C_0"
    fi
    SECAO_OK=0
}
titulo() {
    fecha_secao
    local num=""
    (( MOD_N > 0 && MOD_I > 0 )) && num="$(printf '%02d/%02d' "$MOD_I" "$MOD_N")  "
    local txt="$num$*" resto
    resto=$(( LARG - ${#txt} - 7 )); (( resto < 3 )) && resto=3
    printf '\n %s◆%s %s%s%s%s %s%s%s\n' "$C_ACENTO" "$C_0" "$C_DICA" "$num" "$C_0" "$C_TIT$*$C_0" "$C_LINHA" "$(repete ─ "$resto")" "$C_0"
}
cabecalho() {
    local modo="$1" sis kv
    sis="$(. /etc/os-release 2>/dev/null; echo "${NAME:-Linux}")"
    kv="$(pacman -Q kwin 2>/dev/null | awk '{print $2}' || true)"; kv="${kv%%-*}"; kv="${kv#*:}"
    local l1="LowPan Shells" l2 linha
    l2="$sis · KWin ${kv:-?} · $(id -un)"
    linha="$(repete ─ $((LARG - 4)))"
    printf '\n  %s╭%s╮%s\n' "$C_LINHA" "$linha" "$C_0"
    printf '  %s│%s  %s◆%s %s%*s%s%s%s  %s│%s\n' "$C_LINHA" "$C_0" "$C_ACENTO" "$C_0" "$(degrade "$l1")" \
        $(( LARG - 4 - 6 - ${#l1} - ${#modo} )) "" "$C_DICA" "$modo" "$C_0" "$C_LINHA" "$C_0"
    printf '  %s│%s    %s%s%*s%s%s│%s\n' "$C_LINHA" "$C_0" "$C_DICA" "$l2" $(( LARG - 8 - ${#l2} )) "" "$C_0" "$C_LINHA" "$C_0"
    printf '  %s╰%s╯%s\n' "$C_LINHA" "$linha" "$C_0"
}
_st() { printf '  %s%s%s %s%s%s\n' "$1" "$2" "$C_0" "$3" "$4" "$C_0"; }
st_ok()    { N_OK=$((N_OK + 1)); if (( DETALHES == 1 )); then _st "$C_PULA" "✓" "$C_DICA" "$*"; else SECAO_OK=$((SECAO_OK + 1)); fi; }
st_vai()   { N_VAI=$((N_VAI + 1));   _st "$C_VAI" "→" "" "$*"; }
st_feito() { N_FEITO=$((N_FEITO + 1)); _st "$C_OK" "✓" "" "$*"; }
st_pula()  { N_PULA=$((N_PULA + 1)); _st "$C_PULA" "–" "$C_PULA" "$*"; }
st_aviso() { N_AVISO=$((N_AVISO + 1)); _st "$C_AVISO" "!" "$C_AVISO" "$*"; }
st_erro()  { N_ERRO=$((N_ERRO + 1)); _st "$C_ERRO" "✗" "$C_ERRO" "$*" >&2; }

# rodar_longo "rótulo" — roda o comando (resto dos argumentos, via eval) com a saída no registro e, na tela, uma linha
# que gira com o tempo decorrido; ao terminar a linha é apagada (quem chamou mostra o ✓/✗). Na falha mostra as
# últimas linhas do registro. Sem terminal: só roda, com a saída no registro. stdin do /dev/null: nada pode esperar
# resposta escondido (pacman/yay/makepkg vão com --noconfirm; o sudo já foi autorizado antes).
REGISTRO=""
abrir_registro() {   # sem $(…): o nome tem de ficar na variável global (um registro por execução)
    [[ -n "$REGISTRO" ]] || { mkdir -p "$ESTADO/registros"; REGISTRO="$ESTADO/registros/$CMD-$(date +%Y%m%d-%H%M%S).txt"; }
}
rodar_longo() {
    local rotulo="$1"; shift
    abrir_registro; local log="$REGISTRO"
    printf '\n=== %s — %s\n' "$(date '+%T')" "$rotulo" >> "$log"
    # a linha que gira vai direto ao terminal: com `install.sh … 2>&1 | tee arquivo` (p4.sh da VM) o stderr é pipe,
    # mas o /dev/tty continua sendo a tela — e assim ela não suja o arquivo do tee (2026-11-22: a tela ficava parada)
    local tela=""
    if [[ -t 2 ]]; then tela=/dev/stderr
    elif [[ -t 0 ]] && { : > /dev/tty; } 2>/dev/null; then tela=/dev/tty; fi
    local quadros=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) ini=$SECONDS gira="" rc=0
    # a linha não pode passar da largura do terminal: quebrada em duas, o \r só volta ao começo da 2ª e o texto se
    # empilha (VM, 2026-11-22: "tela de login do LowPan (greetd; vale no…" repetido)
    local cols; cols="$(stty size < /dev/tty 2>/dev/null | awk '{print $2}' || true)"; cols="${cols:-80}"
    local cabe=$(( cols - 14 )); (( cabe < 20 )) && cabe=20
    (( ${#rotulo} > cabe )) && rotulo="${rotulo:0:cabe-1}…"
    if [[ -n "$tela" ]]; then (   i=0
        while :; do
            printf '\r  %s%s%s %s %s(%ds)%s\e[K' "$C_ACENTO" "${quadros[i % 10]}" "$C_0" "$rotulo" "$C_DICA" $((SECONDS - ini)) "$C_0" > "$tela"
            i=$((i + 1)); sleep 0.1
        done ) & gira=$!; fi
    eval "$*" >> "$log" 2>&1 < /dev/null || rc=$?
    if [[ -n "$gira" ]]; then kill "$gira" 2>/dev/null; wait "$gira" 2>/dev/null || true; printf '\r\e[K' > "$tela"; fi
    if (( rc != 0 )); then
        printf '  %s┆ %s%s\n' "$C_ERRO" "$(t "last lines of the log" "últimas linhas do registro")" "$C_0" >&2
        tail -n 12 "$log" | sed "s/^/  ${C_ERRO}┆${C_0} /" >&2
        printf '  %s┆ %s: %s%s\n' "$C_ERRO" "$(t "full log" "registro completo")" "$(curto "$log")" "$C_0" >&2
    fi
    return $rc
}
curto() {      # caminho mais curto para a tela: <projeto>/… e ~/…
    local s="$1"
    if [[ "$s" == "$PROJETO"/* ]]; then s="<projeto>${s#"$PROJETO"}"; elif [[ "$s" == "$HOME"/* ]]; then s="~${s#"$HOME"}"; fi
    printf '%s' "$s"
}
# verificação de um passo: sem pipefail (grep -q fecha o pipe cedo e o SIGPIPE do outro lado contaria como falha)
verif() { ( set +o pipefail; eval "$1" ) >/dev/null 2>&1; }

# ---------------------------------------------------------------- manifesto e backup
manifesto() {   # tipo alvo antigo [backup]
    mkdir -p "$ESTADO"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$MODULO" "$1" "$2" "${3:-}" "${4:-}" >> "$MANIFESTO"
}
backup() {      # caminho → imprime onde ficou a cópia ("" se não existia)
    [[ -e "$1" || -L "$1" ]] || { printf ''; return; }
    [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$ESTADO/backups/$(date +%Y%m%d-%H%M%S)"
    local dest="$BACKUP_DIR${1}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$1" "$dest"
    printf '%s' "$dest"
}

# ---------------------------------------------------------------- respostas
# resposta VAR padrão — valor gravado em respostas.env, senão o padrão (que cada pergunta calcula do que já existe).
carregar_respostas() { [[ -f "$RESPOSTAS" ]] && source "$RESPOSTAS"; return 0; }
resposta() {
    local var="$1" padrao="$2"
    [[ -n "${!var:-}" ]] || printf -v "$var" '%s' "$padrao"
}
# Perguntas (2026-11-21, teste da E5: "s" recusado numa pergunta de escolha confundiu; agora sim/não é [S/n] e as
# escolhas são numeradas, com descrição). Só perguntam no instalar com terminal; senão fica o valor atual/padrão.
pode_perguntar() { [[ "$MODO" == instalar && -t 0 ]]; }
ler() { local r; read -r r || r=""; printf '%s' "$r"; }
# perguntar_sn VAR "pergunta" ["dica"] — VAR fica sim|nao
_sn_op() { [[ "$1" == s ]] && printf '%sS%s/n' "$C_PAD" "$C_0" || printf 's/%sN%s' "$C_PAD" "$C_0"; }
perguntar_sn() {
    local var="$1" texto="$2" dica="${3:-}" atual="${!1:-sim}" r
    pode_perguntar || return 0
    while true; do
        printf '\n  %s?%s %s%s%s  %s[%b%s]%s\n' "$C_OPC" "$C_0" "$C_PERG" "$texto" "$C_0" "$C_DICA" "$(_sn_op "${atual:0:1}")" "$C_DICA" "$C_0" >&2
        [[ -n "$dica" ]] && printf '    %s%s%s\n' "$C_DICA" "$dica" "$C_0" >&2
        printf '    %s›%s ' "$C_ACENTO" "$C_0" >&2
        r="$(ler)"
        case "${r,,}" in
            "") break ;;
            s|sim|y|yes) atual=sim; break ;;
            n|nao|não|no) atual=nao; break ;;
            *) printf '    %s%s%s\n' "$C_ERRO" "$(t "answer s (yes) or n (no), or Enter for the default" "responda s (sim) ou n (não), ou Enter para o padrão")" "$C_0" >&2 ;;
        esac
    done
    printf -v "$var" '%s' "$atual"
}
# perguntar_opcao VAR "pergunta" "valor|descrição" … — aceita o número, o valor ou Enter (padrão = valor atual)
perguntar_opcao() {
    local var="$1" texto="$2"; shift 2
    local atual="${!var:-${1%%|*}}" r i=0 o v d padrao=1
    pode_perguntar || return 0
    printf '\n  %s?%s %s%s%s\n' "$C_OPC" "$C_0" "$C_PERG" "$texto" "$C_0" >&2
    for o in "$@"; do
        i=$((i + 1)); v="${o%%|*}"; d="${o#*|}"
        if [[ "$v" == "$atual" ]]; then padrao=$i
            printf '   %s●%s %s%d  %-10s%s %s  %s%s%s\n' "$C_PAD" "$C_0" "$C_PAD" "$i" "$v" "$C_0" "$d" "$C_DICA" "$(t "default" "padrão")" "$C_0" >&2
        else printf '   %s○%s %s%d%s  %-10s %s%s%s\n' "$C_PULA" "$C_0" "$C_OPC" "$i" "$C_0" "$v" "$C_DICA" "$d" "$C_0" >&2; fi
    done
    while true; do
        printf '    %s›%s %s[%d]%s ' "$C_ACENTO" "$C_0" "$C_DICA" "$padrao" "$C_0" >&2
        r="$(ler)"; r="${r,,}"
        [[ -z "$r" ]] && break
        if [[ "$r" =~ ^[0-9]+$ && "$r" -ge 1 && "$r" -le $# ]]; then o="${!r}"; atual="${o%%|*}"; break; fi
        for o in "$@"; do [[ "$r" == "${o%%|*}" ]] && { atual="$r"; break 2; }; done
        printf '    %s%s 1–%d%s\n' "$C_ERRO" "$(t "type a number" "digite um número de")" "$#" "$C_0" >&2
    done
    printf -v "$var" '%s' "$atual"
}
# perguntar_texto VAR "pergunta" "regex" "dica"
perguntar_texto() {
    local var="$1" texto="$2" re="$3" dica="$4" atual="${!1:-}" r
    pode_perguntar || return 0
    while true; do
        printf '\n  %s?%s %s%s%s %s(%s: %s)%s\n    %s%s%s\n    → ' "$C_OPC" "$C_0" "$C_PERG" "$texto" "$C_0" "$C_PAD" "$(t "default" "padrão")" "${atual:-—}" "$C_0" "$C_DICA" "$dica" "$C_0" >&2
        r="$(ler)"; r="${r:-$atual}"
        [[ "$r" =~ $re ]] && break
        printf '    %s%s%s\n' "$C_ERRO" "$dica" "$C_0" >&2
    done
    printf -v "$var" '%s' "$r"
}
# confirmar "pergunta" [padrão s|n] → 0 se sim
confirmar() {
    local texto="$1" pad="${2:-n}" r
    while true; do
        printf '\n  %s?%s %s%s%s  %s[%b%s]%s\n    %s›%s ' "$C_OPC" "$C_0" "$C_PERG" "$texto" "$C_0" "$C_DICA" "$(_sn_op "$pad")" "$C_DICA" "$C_0" "$C_ACENTO" "$C_0" >&2
        r="$(ler)"; r="${r,,}"; [[ -z "$r" ]] && r="$pad"
        case "$r" in s|sim|y|yes) return 0 ;; n|nao|não|no) return 1 ;; esac
        printf '    %s%s%s\n' "$C_ERRO" "$(t "answer s or n" "responda s ou n")" "$C_0" >&2
    done
}
gravar_respostas() {
    mkdir -p "$ESTADO"
    local v; : > "$RESPOSTAS"
    for v in "$@"; do printf '%s=%q\n' "$v" "${!v}" >> "$RESPOSTAS"; done
}

# ---------------------------------------------------------------- primitivas
# a_link origem destino — link simbólico (substitui link antigo; arquivo comum vai para o backup)
a_link() {
    local src="$1" dst="$2"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then st_ok "$(curto "$dst")"; return; fi
    local antes=""; [[ -L "$dst" ]] && antes="$(readlink "$dst")"
    if [[ "$MODO" == plano ]]; then
        if [[ -L "$dst" ]]; then st_vai "$(t "repoint" "reapontar") $(curto "$dst") → $(curto "$src")"
        elif [[ -e "$dst" ]]; then st_vai "$(t "replace file" "trocar arquivo") $(curto "$dst") $(t "by link" "por link") ($(t "backup" "com backup"))"
        else st_vai "$(t "link" "criar link") $(curto "$dst") → $(curto "$src")"; fi
        return
    fi
    local bk; bk="$(backup "$dst")"
    mkdir -p "$(dirname "$dst")"; rm -f "$dst"; ln -s "$src" "$dst"
    manifesto link "$dst" "$antes" "$bk"; st_feito "$(curto "$dst")"
}

# valor de uma chave SÓ no arquivo do usuário. Com o nome relativo o kreadconfig6 devolve o valor efetivo (com os
# padrões de /etc/xdg e do kdedefaults do Look and Feel), e o desfazer gravava esse padrão como se fosse do usuário
# (achado no teste da E2: ksplashrc ficava com Engine=KSplashQML, Theme=LowPan). Com caminho absoluto não há cascata.
kler() { kreadconfig6 --file "$CFG/$1" --group "$2" --key "$3" 2>/dev/null || true; }

# a_kconf arquivo grupo chave valor — chave de config do KDE (kwriteconfig6), guarda o valor antigo
a_kconf() {
    local f="$1" g="$2" k="$3" v="$4" atual
    atual="$(kler "$f" "$g" "$k")"
    # também vale o efetivo: o KConfig não grava no arquivo do usuário um valor igual ao padrão do sistema (conta nova:
    # library=org.kde.breeze some do kwinrc logo depois de escrito e o arquivo fica sem a linha — 2ª rodada do teste)
    if [[ "$atual" == "$v" || "$(kreadconfig6 --file "$f" --group "$g" --key "$k" 2>/dev/null)" == "$v" ]]; then st_ok "$f [$g] $k=$v"; return; fi
    if [[ "$MODO" == plano ]]; then st_vai "$f [$g] $k: ${atual:-(vazio)} → $v"; return; fi
    local novo=""; [[ -e "$CFG/$f" ]] || novo="(arquivo-novo)"
    kwriteconfig6 --file "$f" --group "$g" --key "$k" "$v"
    manifesto kconf "$f|$g|$k" "$atual" "$novo"; st_feito "$f [$g] $k=$v"
}

# a_klista arquivo grupo chave item — garante "item" numa lista separada por vírgula (mantém o resto)
a_klista() {
    local f="$1" g="$2" k="$3" item="$4" atual
    atual="$(kler "$f" "$g" "$k")"
    if [[ ",$atual," == *",$item,"* ]]; then st_ok "$f [$g] $k ∋ $item"; return; fi
    if [[ "$MODO" == plano ]]; then st_vai "$f [$g] $k += $item"; return; fi
    local novo=""; [[ -e "$CFG/$f" ]] || novo="(arquivo-novo)"
    kwriteconfig6 --file "$f" --group "$g" --key "$k" "${atual:+$atual,}$item"
    manifesto klista "$f|$g|$k" "$atual" "$novo"; st_feito "$f [$g] $k += $item"
}

# a_unit unit [enable|mask] — unit do systemd --user
a_unit() {
    local u="$1" op="${2:-enable}" estado
    estado="$(systemctl --user is-enabled "$u" 2>/dev/null || true)"
    case "$op" in
        enable) [[ "$estado" == enabled || "$estado" == static ]] && { st_ok "systemd --user enable $u"; return; } ;;
        mask) [[ "$estado" == masked ]] && { st_ok "systemd --user mask $u"; return; } ;;
    esac
    if [[ "$MODO" == plano ]]; then st_vai "systemctl --user $op $u (${estado:-?})"; return; fi
    if [[ "$SEM_SISTEMA" == 1 ]]; then st_pula "systemctl --user $op $u (--sem-sistema)"; return; fi
    abrir_registro   # o "Created symlink …" do systemctl vai para o registro, não para a tela
    { systemctl --user daemon-reload; systemctl --user "$op" "$u"; } >> "$REGISTRO" 2>&1
    manifesto unit "$u" "$op"; st_feito "systemctl --user $op $u"
}

# a_cmd "descrição" "verificação" "aplicar" ["desfazer" [arquivo…]] — passo genérico
#   verificação: comando, 0 = já está. desfazer: comando que o desinstalar roda (eval, com a lib carregada).
#   arquivos: guardados antes de aplicar; o desinstalar os devolve (ou apaga, se não existiam) depois do desfazer.
a_cmd() {
    local desc="$1" verif_cmd="$2" aplicar="$3" desfazer="${4:-}"; shift 4 2>/dev/null || shift $#
    if verif "$verif_cmd"; then st_ok "$desc"; return; fi
    if [[ "$MODO" == plano ]]; then st_vai "$desc"; [[ "$aplicar" == *"sudo "* || "$aplicar" == *"makepkg -si"* ]] && N_SUDO=$((N_SUDO + 1)); return 0; fi
    local f bk guardados=""
    for f in "$@"; do
        bk="$(backup "$f")"; guardados+="${guardados:+|}$f=>${bk:-(novo)}"
    done
    if rodar_longo "$desc" "$aplicar"; then manifesto cmd "$desc" "$desfazer" "$guardados"; st_feito "$desc"
    else st_erro "$desc"; fi
}

# guardar/lembrar um valor anterior que só o desinstalar vai usar (ex.: o efeito de abrir/fechar que estava ligado)
salvar_anterior() { mkdir -p "$ESTADO/anterior"; printf '%s' "$2" > "$ESTADO/anterior/$1"; }
anterior() { cat "$ESTADO/anterior/$1" 2>/dev/null || true; }

# a_cmd_sis — igual ao a_cmd, mas mexe no sistema de verdade (D-Bus, KWin, systemd, sudo): com --sem-sistema o
# instalar pula (a verificação, que só lê, roda sempre)
a_cmd_sis() {
    if [[ "$MODO" == instalar && "$SEM_SISTEMA" == 1 ]] && ! verif "$2"; then
        st_pula "$1 (--sem-sistema)"; return
    fi
    a_cmd "$@"
}

# a_pacotes rotulo pacote… — confere com pacman -T; no instalar usa sudo pacman (ou o helper do AUR)
a_pacotes() {
    local rotulo="$1"; shift
    [[ $# -gt 0 ]] || return 0
    local faltam; faltam="$(pacman -T "$@" 2>/dev/null | tr '\n' ' ' || true)"
    if [[ -z "${faltam// /}" ]]; then st_ok "$rotulo ($#)"; return; fi
    if [[ "$MODO" == plano ]]; then st_vai "$(t "install" "instalar") $rotulo: $faltam"; N_SUDO=$((N_SUDO + 1)); return; fi
    if [[ "$SEM_SISTEMA" == 1 && -n "$RAIZ_SISTEMA" && "$rotulo" != AUR* ]]; then
        # simulação: o pacman resolve o que instalaria (com dependências), sem root e sem instalar
        # shellcheck disable=SC2086
        st_feito "[$(t "simulated" "simulado")] $rotulo: $(pacman -S --needed --print --print-format '%n' $faltam 2>&1 | tr '\n' ' ')"; return
    fi
    if [[ "$SEM_SISTEMA" == 1 ]]; then st_pula "$rotulo: $faltam (--sem-sistema)"; return; fi
    local cmd
    if [[ "$rotulo" == AUR* ]]; then
        cmd="$(command -v yay || command -v paru || true)"
        [[ -n "$cmd" ]] || { st_aviso "$(t "no AUR helper (yay/paru): install by hand" "sem helper do AUR (yay/paru): instalar à mão"): $faltam"; return; }
        # sem perguntas (a saída vai para o registro): o yay também não mostra diffs nem pergunta da limpeza
        local extra="--noconfirm"; [[ "$cmd" == */yay ]] && extra+=" --answerdiff None --answerclean None --answeredit None"
        cmd="'$cmd' -S --needed $extra $faltam"
    else
        cmd="sudo pacman -S --needed --noconfirm $faltam"
    fi
    local ok=1
    rodar_longo "$(t "installing" "instalando") $rotulo: $faltam" "$cmd" || ok=0
    # espelho lento ou fora do ar no meio do download (4ª rodada da VM, 2026-11-22: "Operation too slow" no
    # fastly.mirror.pkgbuild.com): mais uma tentativa — o que já veio fica no cache e o pacman recomeça do resto
    if (( ! ok )) && [[ "$rotulo" != AUR* ]]; then
        st_aviso "$(t "package download failed; trying once more" "o download dos pacotes falhou; tentando mais uma vez")"
        rodar_longo "$(t "installing (2nd try)" "instalando (2ª tentativa)") $rotulo: $faltam" "sudo pacman -Syy --noconfirm >/dev/null && $cmd" && ok=1
    fi
    if (( ! ok )); then
        if [[ "$rotulo" == AUR* ]]; then
            # AUR (fontes, extras): o que falhou vira aviso e a instalação segue — o shell funciona sem eles e um
            # PKGBUILD quebrado lá fora não pode travar tudo (VM limpa, 2026-11-22)
            local ainda; ainda="$(pacman -T $faltam 2>/dev/null | tr '\n' ' ' || true)"
            local foram; foram="$(for x in $faltam; do [[ " $ainda " == *" $x "* ]] || printf '%s ' "$x"; done)"
            [[ -n "${foram// /}" ]] && { manifesto pacotes "$foram" ""; st_feito "$rotulo: $foram"; }
            st_aviso "$rotulo — $(t "not installed (see the log above; the rest continues)" "não instalado(s) (ver o registro acima; o resto segue)"): $ainda"
            return 0
        fi
        st_erro "$rotulo: $faltam"
        printf '  %s%s%s\n' "$C_ERRO" "$(t "packages failed: stopping here (nothing after this was changed)" "os pacotes falharam: parando aqui (nada depois disto foi mudado)")" "$C_0" >&2
        _MODULOS_OK=1; exit 1
    fi
    manifesto pacotes "$faltam" ""; st_feito "$rotulo: $faltam"
}

# pacotes_de rotulo… — linhas de install/pacotes.txt cujo comentário "# rotulo" bate (sem rótulo = núcleo)
pacotes_de() {
    local arq="$PROJETO/install/pacotes.txt" alvo="$1"
    awk -v alvo="$alvo" '
        /^[[:space:]]*#/ || NF == 0 { next }
        { rot = ""; if (match($0, /#[[:space:]]*[a-z-]+/)) { rot = substr($0, RSTART, RLENGTH); sub(/#[[:space:]]*/, "", rot) }
          if (alvo == "nucleo" ? (rot == "" || rot !~ /^(captura|magic-lamp|login-iris)$/) : rot == alvo) print $1 }' "$arq"
}

# compilar_pacote DIR — makepkg -si de um PKGBUILD do projeto (extras/…), numa pasta temporária fora do caminho com
# espaço (o -ffile-prefix-map quebra com espaço no caminho do projeto). O makepkg pede a senha com "sudo -k" (ignora a autorização já
# dada: na VM o pedido ficou escondido sob a linha que gira e expirou, 2026-11-22); com PACMAN_AUTH=(sudo) numa
# configuração temporária ele usa a autorização do começo do instalar (sudo_preparar).
compilar_pacote() {
    local dir="$1" tmp rc=0; tmp="$(mktemp -d)"
    cp "$dir"/PKGBUILD "$tmp"/; cp "$dir"/*.patch "$dir"/*.install "$tmp"/ 2>/dev/null || true
    printf 'source /etc/makepkg.conf\nPACMAN_AUTH=(sudo)\n' > "$tmp/makepkg.conf"
    ( cd "$tmp" && BUILDDIR="$tmp/build" SRCDEST="$tmp/src" PKGDEST="$tmp" \
        makepkg --config "$tmp/makepkg.conf" -si --noconfirm --needed ) || rc=$?
    rm -rf "$tmp"; return $rc
}

# ---------------------------------------------------------------- desinstalar (lê o manifesto de trás para frente)
devolver_guardados() {   # "caminho=>backup|caminho=>(novo)"
    local item f bk
    IFS='|' read -r -a itens <<< "$1"
    for item in "${itens[@]}"; do
        [[ -n "$item" ]] || continue
        f="${item%%=>*}"; bk="${item#*=>}"
        rm -rf "$f"
        [[ "$bk" != "(novo)" && -e "$bk" ]] && { mkdir -p "$(dirname "$f")"; cp -a "$bk" "$f"; }
    done
    return 0
}
desfazer_linha() {   # data modulo tipo alvo antigo backup
    local tipo="$3" alvo="$4" antigo="$5" bk="$6" f g k
    case "$tipo" in
        link)
            rm -f "$alvo"
            if [[ -n "$bk" && ( -e "$bk" || -L "$bk" ) ]]; then cp -a "$bk" "$alvo"
            elif [[ -n "$antigo" ]]; then ln -s "$antigo" "$alvo"; fi ;;
        kconf|klista)
            IFS='|' read -r f g k <<< "$alvo"
            if [[ -n "$antigo" ]]; then kwriteconfig6 --file "$f" --group "$g" --key "$k" "$antigo"
            else python3 -I "$PROJETO/install/apagar-chave.py" "$CFG/$f" "$g" "$k"; fi   # sem --delete: ele grava [$d]
            # arquivo que o instalador criou e ficou sem nenhuma chave: sai também
            if [[ "$bk" == "(arquivo-novo)" ]] && ! grep -q '=' "$CFG/$f" 2>/dev/null; then rm -f "$CFG/$f"; fi ;;
        unit)
            if [[ "$SEM_SISTEMA" == 1 ]]; then st_pula "systemctl --user $antigo $alvo (--sem-sistema)"; return; fi
            # sem `disable`: com a unit sendo link para o projeto, o disable apaga o link junto (§21.79)
            if [[ "$antigo" == mask ]]; then systemctl --user unmask "$alvo"; else rm -f "$UNITS"/*.wants/"$alvo"; fi ;;
        cmd)
            if [[ -n "$antigo" ]]; then eval "$antigo" || st_erro "$(t "undo failed" "desfazer falhou"): $alvo"; fi
            devolver_guardados "$bk" ;;
        pacotes)
            pacote_para_remover $alvo; return ;;
    esac
    st_feito "$(t "undone" "desfeito"): $(curto "$alvo")"
}
# Dentro do LowPan o desinstalar tira o shell que está desenhando a tela (e o marcador "iris" impede o plasmashell de
# subir): a sessão fica sem ambiente gráfico. Só roda na sessão Plasma (pedido do dono, 2026-11-21).
no_iris() {
    systemctl --user is-active -q lowpan-shells.service && return 0
    local m="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lowpan-sessao" s=""
    [[ -f "$m" ]] && read -r s _ < "$m"
    [[ "$s" == iris ]]
}
# O que as Configurações do shell podem ligar por conta própria (não está no manifesto): captura do iNiR e tiling.
# 2ª rodada do teste: a captura ligada pelas Configurações deixou 9 lowpan-shells-capture-*.desktop e as teclas com ela.
desfazer_estado_shell() {
    [[ "$SEM_SISTEMA" == 1 ]] && return 0
    if compgen -G "$DATA/applications/lowpan-shells-capture-*.desktop" >/dev/null; then
        "$PROJETO/system/lowpan-shells-capture" spectacle >/dev/null 2>&1 && st_feito "$(t "capture keys given back to Spectacle" "teclas da captura devolvidas ao Spectacle")"
    fi
    if "$PROJETO/system/lowpan-shells-tiling" status 2>/dev/null | grep -qE '^tiling: (on|ligado)'; then
        "$PROJETO/system/lowpan-shells-tiling" off >/dev/null 2>&1 && st_feito "$(t "tiling turned off (KDE keys given back)" "tiling desligado (teclas do KDE devolvidas)")"
    fi
    return 0
}

desinstalar() {
    [[ -f "$MANIFESTO" ]] || { echo "$(t "nothing installed by install.sh (no manifest)" "nada instalado pelo install.sh (sem manifesto)")"; return 0; }
    PACOTES_INSTALADOS=""
    titulo "$(t "Uninstall" "Desinstalar")"

    local linhas=() i
    mapfile -t linhas < "$MANIFESTO"
    for (( i=${#linhas[@]}-1; i>=0; i-- )); do
        # campos separados à mão: com IFS=TAB o read junta campos vazios seguidos (TAB é "espaço" para o bash) e
        # o campo dos backups escorregava para o do comando de desfazer, que vai para o eval (achado no teste da E2)
        local resto="${linhas[$i]}" campos=() n
        for n in 1 2 3 4 5; do campos+=("${resto%%$'\t'*}"); resto="${resto#*$'\t'}"; done
        campos+=("$resto")
        [[ ${#campos[@]} -eq 6 ]] || { st_erro "$(t "bad manifest line" "linha do manifesto inválida"): ${linhas[$i]}"; continue; }
        MODULO="${campos[1]}"; desfazer_linha "${campos[@]}"
    done
    desfazer_estado_shell
    mv "$MANIFESTO" "$MANIFESTO.desfeito-$(date +%Y%m%d-%H%M%S)"
    # aviso para o switch (try/on) e o login da sessão LowPan não religarem o shell
    : > "$ESTADO/desinstalado"
    rmdir "$UNITS/lowpan-shells.service.wants" 2>/dev/null || true
    # dados que o próprio shell criou enquanto rodava (histórico da área de transferência, miniaturas, estado das
    # Configurações): apagados sempre, sem perguntar (pedido do dono, 2026-11-22). Do estado do instalador ficam só o
    # registro e o manifesto desfeito; as respostas saem (instalar de novo pergunta de novo).
    local dados=("$DATA/lowpan-shells" "${XDG_CACHE_HOME:-$HOME/.cache}/lowpan-shells" "${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells")
    local d
    for d in "${dados[@]}"; do
        [[ -d "$d" ]] || continue
        if [[ "$d" == "${XDG_STATE_HOME:-$HOME/.local/state}/lowpan-shells" ]]; then
            find "$d" -mindepth 1 -maxdepth 1 ! -name install -exec rm -rf {} +
        else rm -rf "$d"; fi
        st_feito "$(t "deleted" "apagado"): $(curto "$d")"
    done
    rm -f "$RESPOSTAS"
    [[ "$SEM_SISTEMA" == 1 ]] || { qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; systemctl --user daemon-reload; kbuildsycoca6 >/dev/null 2>&1 || true; }
    remover_pacotes
    limpar_sobras
    return 0
}

# Inventário da conta antes da 1ª instalação (caminhos até 5 níveis em ~/.config, ~/.local, ~/.themes, ~/.icons): o
# desinstalar só apaga o que NÃO estava aqui. Teste de remoção na VM (2026-11-22): sobravam pastas vazias, o estado do
# shell, os arquivos que os apps instalados criaram (GTK do kde-gtk-config, dconf, Kate, Nautilus, Go do AUR…).
INVENTARIO="$ESTADO/antes-da-instalacao.txt"
inventario_antes() {
    [[ -f "$INVENTARIO" || -f "$MANIFESTO" ]] && return 0
    mkdir -p "$ESTADO"
    ( cd "$HOME" && find .config .local .themes .icons -maxdepth 5 2>/dev/null | sort ) > "$INVENTARIO" || true
    # grupos [Tiling] que o KWin já tinha gravado (o limpar_sobras não os apaga)
    grep '^\[Tiling\]' "$CFG/kwinrc" 2>/dev/null | sed 's/^/kwinrc:/' >> "$INVENTARIO" || true
}
_novo() { [[ -e "$HOME/$1" || -L "$HOME/$1" ]] && ! grep -qxF "$1" "$INVENTARIO"; }
_kapaga() { python3 -I "$PROJETO/install/apagar-chave.py" "$CFG/$1" "$2" "$3"; }
# o que os componentes gravam enquanto rodam (fora do manifesto) e o que sobra dos apps que o instalador trouxe
limpar_sobras() {
    [[ -f "$INVENTARIO" ]] || return 0
    local r n=0 e
    # kwinrc: o motor do tiling desligado deixa lowpanActive=false/lowpan-tilingEnabled=true (de propósito: descarregar
    # o script derrubava o KWin); efeitos nossos que já não existem; minimizar com o valor padrão do KDE
    if [[ ! -e "$DATA/kwin/scripts/lowpan-tiling" ]]; then _kapaga kwinrc Script-lowpan-tiling '*'; _kapaga kwinrc Plugins lowpan-tilingEnabled; fi
    for e in kwin4_effect_squash2 kwin4_effect_tv kwin4_effect_geometry_change; do
        if [[ -e "$DATA/kwin/effects/$e" || -e "/usr/share/kwin/effects/$e" ]]; then
            # o efeito é da pessoa (já tinha antes; notebook, 2026-11-22): só sai o que equivale a não ter a chave —
            # desligado (os três vêm desligados por padrão) e o Targets vazio que o shell grava para o Achatar2
            [[ "$(kreadconfig6 --file "$CFG/kwinrc" --group Plugins --key "${e}Enabled" 2>/dev/null)" == false ]] && _kapaga kwinrc Plugins "${e}Enabled"
            [[ -z "$(kreadconfig6 --file "$CFG/kwinrc" --group "Effect-$e" --key Targets 2>/dev/null)" ]] && _kapaga kwinrc "Effect-$e" Targets
            continue
        fi
        _kapaga kwinrc Plugins "${e}Enabled"; _kapaga kwinrc "Effect-$e" '*'
    done
    pacman -Q kwin-effects-yet-another-magic-lamp-reloaded-git >/dev/null 2>&1 || _kapaga kwinrc Plugins libkwin4_effect_yetanothermagiclampEnabled
    # nosso Rounded Corners removido: a chave dele e o grupo de ajustes saem (o do Plasma, [Round-Corners], é da pessoa)
    if ! pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1; then
        _kapaga kwinrc Plugins kwin4_effect_lowpancornersEnabled; _kapaga kwinrc LowPan-Round-Corners '*'
    fi
    [[ "$(kreadconfig6 --file "$CFG/kwinrc" --group Plugins --key magiclampEnabled 2>/dev/null)" == false ]] && _kapaga kwinrc Plugins magiclampEnabled
    [[ "$(kreadconfig6 --file "$CFG/kwinrc" --group Plugins --key squashEnabled 2>/dev/null)" == true ]] && _kapaga kwinrc Plugins squashEnabled
    # [Tiling][<tela>][<área>] que o próprio KWin grava (editor de tiles do Meta+T) quando o perfil cria áreas de
    # trabalho: só os que estão no layout padrão dele (25/50/25, padding 4) — um layout desenhado pela pessoa fica
    python3 -I - "$CFG/kwinrc" "$INVENTARIO" <<'PY' || true
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
antes = {l[len("kwinrc:"):].rstrip("\n") for l in open(sys.argv[2], encoding="utf-8") if l.startswith("kwinrc:")}
if p.is_file():
    padrao = {"padding=4", 'tiles={"layoutDirection":"horizontal","tiles":[{"width":0.25},{"width":0.5},{"width":0.25}]}'}
    blocos, atual = [], None
    for linha in p.read_text(encoding="utf-8").splitlines():
        if linha.startswith("[") and linha.endswith("]") and not linha.startswith("[$"):
            atual = [linha, []]; blocos.append(atual)
        elif atual is None:
            atual = [None, [linha]]; blocos.append(atual)
        else:
            atual[1].append(linha)
    fica = [b for b in blocos if not (b[0] and re.match(r"\[Tiling\]\[", b[0]) and b[0] not in antes
                                       and {l for l in b[1] if l.strip()} == padrao)]
    if len(fica) != len(blocos):
        saida = []
        for cab, corpo in fica:
            if cab: saida.append(cab)
            saida.extend(corpo)
        while saida and not saida[-1].strip(): saida.pop()
        p.write_text("\n".join(saida) + "\n", encoding="utf-8")
PY
    # atalhos registrados pelo tiling e pelo Cubo (kdeplasma-addons) que ficaram sem dono: tira do kglobalaccel e do arquivo
    local acoes=()
    [[ -e "$DATA/kwin/scripts/lowpan-tiling" ]] || mapfile -t acoes < <(sed -n '/^\[kwin\]$/,/^\[/{s/^\(LowPanTiling[^=]*\)=.*/\1/p}' "$CFG/kglobalshortcutsrc" 2>/dev/null)
    [[ -e /usr/share/kwin/effects/cube ]] || acoes+=(Cube)
    # o efeito "clique do mouse" do perfil registra o atalho dele; desligado e no valor padrão, sai também
    [[ "$(kreadconfig6 --file "$CFG/kwinrc" --group Plugins --key mouseclickEnabled 2>/dev/null)" != true ]] \
        && grep -q '^ToggleMouseClick=Meta+\*,Meta+\*,' "$CFG/kglobalshortcutsrc" 2>/dev/null && acoes+=(ToggleMouseClick)
    for e in "${acoes[@]}"; do
        [[ "$SEM_SISTEMA" == 1 ]] || qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.unregister kwin "$e" >/dev/null 2>&1 || true
        _kapaga kglobalshortcutsrc kwin "$e"
    done
    # entradas que não existiam antes da instalação e são do shell, do instalador ou dos apps que ele trouxe
    for r in .config/{atuin,go,gtk-3.0,gtk-4.0,xsettingsd,dconf,libaccounts-glib,illogical-impulse,quickshell,kate,katerc,katevirc,katemetainfos,kitty,fastfetch,starship.toml,nautilus,breezerc,kwinrulesrc,spectaclerc,mpv,yt-dlp,matugen,cava,environment.d,wireplumber} \
             .local/share/{inir,libkunitconversion,nautilus,kate,org.kde.syntax-highlighting,atuin,lowpan-shells,quickshell} \
             .local/state/{quickshell,kate,qalculate} .config/qalculate; do
        _novo "$r" || continue
        rm -rf "${HOME:?}/$r"; n=$((n + 1))
    done
    # kcminputrc novo só com o cursor padrão do KDE (a troca de perfil de tema grava cursorTheme=breeze_cursors)
    if _novo .config/kcminputrc; then
        [[ "$(kreadconfig6 --file "$CFG/kcminputrc" --group Mouse --key cursorTheme 2>/dev/null)" == breeze_cursors ]] && _kapaga kcminputrc Mouse cursorTheme
        [[ "$(kreadconfig6 --file "$CFG/kcminputrc" --group Mouse --key cursorSize 2>/dev/null)" == 24 ]] && _kapaga kcminputrc Mouse cursorSize
    fi
    # arquivos de configuração do KDE criados vazios (sem nenhuma chave) durante a instalação
    for r in .config/kcminputrc .config/kdenliverc; do
        _novo "$r" && ! grep -q '=' "$HOME/$r" 2>/dev/null && { rm -f "$HOME/$r"; n=$((n + 1)); }
    done
    # pastas vazias que não existiam antes (várias voltas: esvaziar a de dentro esvazia a de fora)
    local passo d
    for passo in 1 2 3 4 5 6; do
        local tirou=0
        while IFS= read -r d; do
            grep -qxF "$d" "$INVENTARIO" && continue
            rmdir "$HOME/$d" 2>/dev/null && { tirou=1; n=$((n + 1)); }
        done < <(cd "$HOME" && find .config .local .themes .icons -maxdepth 5 -type d -empty 2>/dev/null)
        (( tirou )) || break
    done
    # do estado do instalador ficam só o registro, o manifesto desfeito e o aviso "desinstalado"
    rm -rf "$ESTADO/anterior" "$ESTADO/backups" "$INVENTARIO"
    (( n )) && st_feito "$(t "leftovers removed" "sobras apagadas") ($n): $(t "folders and files created during the installation" "pastas e arquivos criados durante a instalação")"
    return 0
}

# Pacotes que o install.sh instalou (manifesto: só os que faltavam; os que a máquina já tinha não entram) saem no fim
# do desinstalar (pedido do dono, 2026-11-22), com as dependências que vieram com eles (-Rns). Ficam só: os que outro
# programa instalado depois precisa (o pacman recusa; avisados) e o pacote do shell de login da conta (ex.: zsh — sem
# ele a conta não entra).
pacote_para_remover() { PACOTES_INSTALADOS+="$* "; }
remover_pacotes() {
    local p lista=() fica=() shell_login dono_shell=""
    for p in $PACOTES_INSTALADOS; do
        [[ " ${lista[*]} " == *" $p "* ]] && continue
        pacman -Q "$p" >/dev/null 2>&1 && lista+=("$p")
        # makepkg -si instala junto o pacote de depuração dos compilados (kwin-effect-rounded-corners-git-debug)
        pacman -Q "$p-debug" >/dev/null 2>&1 && lista+=("$p-debug")
    done
    (( ${#lista[@]} )) || return 0
    shell_login="$(getent passwd "$(id -un)" | cut -d: -f7)"
    [[ -n "$shell_login" ]] && dono_shell="$(pacman -Qqo "$shell_login" 2>/dev/null || true)"
    if [[ -n "$dono_shell" && " ${lista[*]} " == *" $dono_shell "* ]]; then
        lista=($(printf '%s\n' "${lista[@]}" | grep -vx "$dono_shell")); fica+=("$dono_shell ($(t "your login shell" "o shell de login da conta"))")
    fi
    titulo "$(t "Packages" "Pacotes")"
    if [[ "$SEM_SISTEMA" == 1 ]]; then st_pula "pacman -Rns ${lista[*]} (--sem-sistema)"; return 0; fi
    # serviço de sistema de um pacote que ainda está rodando (o greetd: foi ele que abriu esta sessão): sem o arquivo da
    # unit o systemd perde as dependências dela, não a para no desligamento e o reinício trava esperando os processos
    # (3ª rodada da VM, 2026-11-22: "Waiting for process: greetd"). Uma cópia em /run (some no reinício) mantém a parada
    # normal até lá.
    local u copiou=0
    for p in "${lista[@]}"; do
        while IFS= read -r u; do
            systemctl is-active -q "$(basename "$u")" 2>/dev/null || continue
            sudo cp "$u" /run/systemd/system/ && copiou=1
        done < <(pacman -Qlq "$p" 2>/dev/null | grep -E '^/usr/lib/systemd/system/[^/]+\.service$' || true)
    done
    # em bloco; se o pacman recusar (algum é dependência de outro programa), não é erro: de um em um logo abaixo
    rodar_longo "$(t "removing" "removendo") ${#lista[@]} $(t "packages" "pacotes")" "sudo pacman -Rns --noconfirm ${lista[*]} || true"
    local sobrou=()
    for p in "${lista[@]}"; do pacman -Q "$p" >/dev/null 2>&1 && sobrou+=("$p"); done
    if (( ${#sobrou[@]} )); then
        # várias voltas: um da lista pode depender de outro
        local resto=("${sobrou[@]}") mudou=1 prox
        while (( mudou && ${#resto[@]} )); do
            mudou=0; prox=()
            for p in "${resto[@]}"; do
                pacman -Q "$p" >/dev/null 2>&1 || { mudou=1; continue; }
                if sudo pacman -Rns --noconfirm "$p" >> "$REGISTRO" 2>&1; then mudou=1; else prox+=("$p"); fi
            done
            resto=("${prox[@]}")
        done
        for p in "${resto[@]}"; do
            fica+=("$p ($(t "needed by" "necessário para"): $(LC_ALL=C pacman -Qi "$p" 2>/dev/null | sed -n 's/^Required By *: *//p' | head -1))")
        done
    fi
    (( copiou )) && sudo systemctl daemon-reload
    local foram=()
    for p in "${lista[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || foram+=("$p"); done
    (( ${#foram[@]} )) && st_feito "$(t "removed" "removidos") (${#foram[@]}): ${foram[*]}"
    for p in "${fica[@]}"; do st_aviso "$(t "kept" "mantido"): $p"; done
    return 0
}

# ---------------------------------------------------------------- sudo: uma senha para a instalação toda
sudo_preparar() {
    [[ "$N_SUDO" -gt 0 && "$SEM_SISTEMA" != 1 ]] || return 0
    printf '\n  %s🔒 %s%s\n' "$C_DICA" "$(t "Some steps need administrator rights (packages, login screen…): sudo will ask for your password once." "Alguns passos precisam de administrador (pacotes, tela de login…): o sudo vai pedir a sua senha uma vez.")" "$C_0"
    sudo -v || { st_erro "$(t "sudo not authorised: nothing changed" "sudo não autorizado: nada foi mudado")"; exit 1; }
    # mantém a autorização viva durante passos longos (compilar o tiling, o Magic Lamp)
    ( while kill -0 "$$" 2>/dev/null; do sleep 50; sudo -n -v 2>/dev/null || exit; done ) &
    SUDO_VIVO=$!
    trap '[[ -n "${SUDO_VIVO:-}" ]] && kill "$SUDO_VIVO" 2>/dev/null' EXIT
}

# ---------------------------------------------------------------- verificar: saúde (só lê)
N_SAUDE=0
saude_ok()  { st_ok "$*"; }
saude_mal() { N_SAUDE=$((N_SAUDE + 1)); st_aviso "$*"; }
saude() {
    titulo "$(t "Health" "Saúde")"
    if systemctl --user is-active -q lowpan-shells.service; then saude_ok "$(t "shell running" "shell rodando")"
    else st_ok "$(t "shell not running (Plasma session)" "shell parado (sessão Plasma)")"; fi
    local e
    for e in kwin4_effect_tv kwin4_effect_lowpancorners; do
        # o nosso Rounded Corners só fica ligado no LowPan (no Plasma vale o da pessoa: lowpan-cantos-ambiente)
        [[ "$e" == kwin4_effect_lowpancorners ]] && { ! pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1 \
            || ! systemctl --user is-active -q lowpan-shells.service \
            || [[ "$(kreadconfig6 --file "$CFG/kwinrc" --group Plugins --key kwin4_effect_lowpancornersEnabled)" == false ]]; } && continue
        if [[ "$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$e" 2>/dev/null)" == true ]]; then saude_ok "$(t "KWin effect loaded" "efeito do KWin carregado"): $e"
        else saude_mal "$(t "KWin effect not loaded" "efeito do KWin não carregado"): $e"; fi
    done
    local def; def="$("$PROJETO/system/lowpan-efeitos-kwin" listar 2>/dev/null || true)"
    if [[ -z "$def" ]]; then saude_ok "$(t "AUR KWin effects built for this KWin" "efeitos do AUR compilados para este KWin")"
    else saude_mal "$(t "AUR effects to rebuild" "efeitos do AUR para recompilar"): $(echo $def) → lowpan-efeitos-kwin recompilar"; fi
    local f falta="" fontes; fontes="$(fc-list : family 2>/dev/null)"   # uma vez: com pipefail, fc-list | grep -q dava SIGPIPE
    for f in "Material Symbols" "JetBrainsMono Nerd" "Roboto Flex" "Readex Pro" "Gabarito" "Space Grotesk" "Oxanium"; do
        grep -qi "$f" <<< "$fontes" || falta+="$f, "
    done
    [[ -z "$falta" ]] && saude_ok "$(t "LowPan fonts" "fontes do LowPan")" || saude_mal "$(t "missing fonts" "fontes faltando"): ${falta%, }"
    # o defeito em si, não a versão: o Mesa 26.3.1 quebrou o OpenGL do GTK4 na máquina do dono (§19.2 linha 53), mas na
    # VM (virgl) o GTK4 com a 26.3 funcionava e o aviso por número de versão enganava (2026-11-22)
    local mesa gl; mesa="$(pacman -Q mesa 2>/dev/null | awk '{print $2}' || true)"
    gl="$(timeout 15 python3 -I -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Gdk","4.0")
from gi.repository import Gtk, Gdk
Gtk.init()
try:
    Gdk.Display.get_default().prepare_gl(); print("ok")
except Exception as e:
    print(e)' 2>/dev/null | tail -1 || true)"
    if [[ "$gl" == ok ]]; then saude_ok "$(t "GTK4 OpenGL" "OpenGL do GTK4") (Mesa ${mesa:-?})"
    elif [[ -z "$gl" ]]; then saude_ok "Mesa ${mesa:-?} ($(t "GTK4 OpenGL not tested" "OpenGL do GTK4 não testado"))"
    else saude_mal "$(t "GTK4 OpenGL failed" "o OpenGL do GTK4 falhou") (Mesa ${mesa:-?}: $gl) — $(t "GTK4 apps (Nautilus) fall back to software; see §19.2 line 53" "os apps GTK4 (Nautilus) caem para software; ver §19.2 linha 53")"; fi
    local quebrados; quebrados="$(find "$BIN" "$UNITS" "$DATA/applications" "$CFG/quickshell" -maxdepth 2 -xtype l -name '*lowpan*' 2>/dev/null)"
    [[ -z "$quebrados" ]] && saude_ok "$(t "no broken links" "nenhum link quebrado")" || saude_mal "$(t "broken links" "links quebrados"): $(echo $quebrados)"
    [[ -f "$MANIFESTO" ]] && st_ok "$(t "manifest" "manifesto"): $(wc -l < "$MANIFESTO") $(t "steps" "passos")" || st_ok "$(t "no manifest (installed before install.sh)" "sem manifesto (instalado antes do install.sh)")"
}
