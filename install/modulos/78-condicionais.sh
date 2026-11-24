# Só se o programa existir (§19.2 linhas 7–9)
titulo "$(t "If installed" "Se estiver instalado")"
# Krohnkite: nada aqui desde 2026-11-22 — ele não carrega mais com o LowPan Shells instalado (perfil no 75-opcionais);
# o ignoreClass que este passo gravava (só "quickshell") apagava a lista padrão dele.
if [[ -d "$DATA/kwin/scripts/center-new-windows" || -d /usr/share/kwin/scripts/center-new-windows ]]; then
    a_klista kwinrc Script-center-new-windows applications quickshell
else st_pula "center-new-windows: $(t "not installed" "não instalado")"; fi
regra_yakuake() {
    local id=lowpan-yakuake-todas f=kwinrulesrc ordem
    kwriteconfig6 --file $f --group $id --key Description "Yakuake em todas as áreas de trabalho"
    kwriteconfig6 --file $f --group $id --key wmclass org.kde.yakuake
    kwriteconfig6 --file $f --group $id --key wmclassmatch 1
    kwriteconfig6 --file $f --group $id --key desktops '\0'
    kwriteconfig6 --file $f --group $id --key desktopsrule 2
    ordem="$(kreadconfig6 --file $f --group General --key rules)"
    kwriteconfig6 --file $f --group General --key rules "${ordem:+$ordem,}$id"
    kwriteconfig6 --file $f --group General --key count "$(( $(kreadconfig6 --file $f --group General --key count --default 0) + 1 ))"
}
if command -v yakuake >/dev/null; then
    a_cmd "$(t "rule: Yakuake on all desktops" "regra: Yakuake em todas as áreas de trabalho")" \
        "grep -q '^Description=Yakuake em todas as áreas de trabalho' '$CFG/kwinrulesrc'" \
        "regra_yakuake" "" "$CFG/kwinrulesrc"
else st_pula "Yakuake: $(t "not installed" "não instalado")"; fi
