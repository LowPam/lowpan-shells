# Shell, serviços e comandos (§19.2 linhas 2–5, 29, 31, 44 drop-in; o mesmo do ensure_installed do switch)
titulo "$(t "Shell, services and commands" "Shell, serviços e comandos")"
a_link "$PROJETO/shell" "$CFG/quickshell/lowpan-shells"
a_link "$PROJETO/system/lowpan-shells.service" "$UNITS/lowpan-shells.service"
a_link "$PROJETO/system/lowpan-shells-cliphist.service" "$UNITS/lowpan-shells-cliphist.service"
a_unit lowpan-shells-cliphist.service
a_link "$PROJETO/system/lowpan-theme-login.service" "$UNITS/lowpan-theme-login.service"
a_unit lowpan-theme-login.service
a_link "$PROJETO/system/plasma-plasmashell-lowpan.conf" "$UNITS/plasma-plasmashell.service.d/lowpan.conf"
# tiling por ambiente (2026-11-22): a escolha do ambiente depois do KWin, e a caixa de liga/desliga da tela do script
a_link "$PROJETO/system/lowpan-tiling-sessao.service" "$UNITS/lowpan-tiling-sessao.service"
a_unit lowpan-tiling-sessao.service
a_link "$PROJETO/system/lowpan-tiling-painel.service" "$UNITS/lowpan-tiling-painel.service"
a_link "$PROJETO/system/lowpan-tiling-painel.path" "$UNITS/lowpan-tiling-painel.path"
a_unit lowpan-tiling-painel.path
for _c in lowpan-shells-switch lowpan-shells-shortcuts lowpan-shells-clipboard lowpan-shells-volume lowpan-shells-files \
          lowpan-shells-capture lowpan-shells-tiling lowpan-voltar-plasma lowpan-fastfetch; do
    a_link "$PROJETO/system/$_c" "$BIN/$_c"
done
a_link "$PROJETO/system/lowpan-shells-iris.desktop" "$DATA/applications/lowpan-shells-iris.desktop"
# gerado (não link): o Exec leva o caminho do ~/.local/bin desta conta; um link antigo é trocado pelo arquivo
_lf="$DATA/applications/lowpan-files.desktop"
_lf_gerar="sed 's|@BIN@|$BIN|' '$PROJETO/system/lowpan-files.desktop'"
a_cmd "$(t "folder app" "app de pastas") (lowpan-files.desktop)" \
    "[ ! -L '$_lf' ] && cmp -s <($_lf_gerar) '$_lf'" \
    "mkdir -p '$DATA/applications' && rm -f '$_lf' && $_lf_gerar > '$_lf'" \
    "rm -f '$_lf'" "$_lf"
