# Pacotes (§19.2 linha 1; listas em install/pacotes*.txt)
titulo "$(t "Packages" "Pacotes")"
mapfile -t _p < <(pacotes_de nucleo)
# dados do OCR sempre no núcleo (2026-11-24, teste como usuário na VM): o spectacle do núcleo depende do tesseract, que
# pede UM pacote de dados entre 128; sem nenhum na lista o --noconfirm escolhia o 1º (africâner, tesseract-data-afr).
# Inglês + o idioma do sistema (o tesseract usa códigos de 3 letras).
_ocr=(tesseract-data-eng)
case "${LANG:-}" in pt*) _ocr+=(tesseract-data-por) ;; es*) _ocr+=(tesseract-data-spa) ;; de*) _ocr+=(tesseract-data-deu) ;;
    fr*) _ocr+=(tesseract-data-fra) ;; it*) _ocr+=(tesseract-data-ita) ;; esac
_p+=("${_ocr[@]}")
# atuin de fora do pacman (instalador oficial em ~/.atuin/bin, cargo…): fica o da pessoa. Com os dois, basta o do pacote
# (mais novo) rodar uma vez para migrar o banco do histórico, e o antigo — que o ~/.profile põe na frente do PATH —
# passa a dar "migration … was previously applied but is missing" (notebook do dono, 2026-11-22).
_atuin_fora=""
for _a in "$HOME/.atuin/bin/atuin" "$HOME/.cargo/bin/atuin" "$HOME/.local/bin/atuin"; do
    if [[ -x "$_a" ]]; then _atuin_fora="$_a"; break; fi
done
if [[ -n "$_atuin_fora" ]] && ! pacman -Q atuin >/dev/null 2>&1; then
    _q=(); for _x in "${_p[@]}"; do [[ "$_x" == atuin ]] || _q+=("$_x"); done; _p=("${_q[@]}")
    st_pula "atuin: $(t "already installed outside pacman" "já instalado fora do pacman") (${_atuin_fora/#$HOME/\~}) — $(t "keeping yours" "mantido o seu")"
fi
a_pacotes "$(t "core" "núcleo")" "${_p[@]}"
if [[ "$CAPTURA" == inir ]]; then
    mapfile -t _p < <(pacotes_de captura)
    # os dados do OCR já vão no núcleo (_ocr); aqui só tira o tesseract-data-por fixo da lista quando o sistema não é pt
    case "${LANG:-}" in pt*) ;; *) _p=("${_p[@]/tesseract-data-por}") ;; esac
    a_pacotes "$(t "capture (iNiR)" "captura (iNiR)")" ${_p[@]}
fi
[[ "$LOGIN" == iris ]] && { mapfile -t _p < <(pacotes_de login-iris); a_pacotes "$(t "login screen" "tela de login")" "${_p[@]}"; }
[[ "$MAGICLAMP" == sim ]] && { mapfile -t _p < <(pacotes_de magic-lamp); a_pacotes "magic lamp (build)" "${_p[@]}"; }
mapfile -t _p < <(grep -v '^\s*#' "$PROJETO/install/pacotes-aur.txt" | awk 'NF {print $1}'); a_pacotes "AUR" "${_p[@]}"
# Cantos arredondados: o NOSSO Rounded Corners (extras/lowpan-kwin-rounded-corners, 2026-11-22) — o código do upstream
# com nomes próprios (plugin kwin4_effect_lowpancorners, kwinrc [LowPan-Round-Corners]), para conviver com o Rounded
# Corners que a pessoa já tiver (pacote do AUR ou instalado à mão; o notebook do dono tinha um feito com make install):
# o LowPan usa o nosso, o Plasma o dela (lowpan-cantos-ambiente, no 40-kwin). O lowpan-efeitos-kwin recompila daqui quando
# o KWin atualiza. Falhar aqui não para a instalação.
if [[ "$SEM_SISTEMA" == 1 ]] && ! pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1; then
    st_pula "$(t "window corners effect (build)" "efeito de cantos arredondados (compilar)") (--sem-sistema)"
else
    # o a_cmd só conta o sudo pelo texto do comando ("makepkg -si"); aqui ele está dentro da função
    if [[ "$MODO" == plano ]] && ! pacman -Q lowpan-kwin-rounded-corners >/dev/null 2>&1; then N_SUDO=$((N_SUDO + 1)); fi
    a_cmd "$(t "window corners effect for LowPan (our Rounded Corners, built from the project recipe)" "efeito de cantos arredondados do LowPan (nosso Rounded Corners, compilado da receita do projeto)")" \
        "pacman -Q lowpan-kwin-rounded-corners" \
        "compilar_pacote '$PROJETO/extras/lowpan-kwin-rounded-corners'" \
        "pacote_para_remover lowpan-kwin-rounded-corners"
fi
