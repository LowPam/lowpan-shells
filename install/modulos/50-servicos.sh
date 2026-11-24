# Serviços de apoio (§19.2 linhas 51, 52)
titulo "$(t "Helper services" "Serviços de apoio")"
a_link "$PROJETO/system/lowpan-efeitos-kwin" "$BIN/lowpan-efeitos-kwin"
a_link "$PROJETO/system/lowpan-efeitos-kwin.service" "$UNITS/lowpan-efeitos-kwin.service"
a_link "$PROJETO/system/lowpan-efeitos-kwin.path" "$UNITS/lowpan-efeitos-kwin.path"
a_unit lowpan-efeitos-kwin.service
a_unit lowpan-efeitos-kwin.path
a_link "$PROJETO/system/wireplumber/lowpan-bt-autoswitch.lua" "$DATA/wireplumber/scripts/lowpan-bt-autoswitch.lua"
a_link "$PROJETO/system/wireplumber/60-lowpan-bt-autoswitch.conf" "$CFG/wireplumber/wireplumber.conf.d/60-lowpan-bt-autoswitch.conf"
