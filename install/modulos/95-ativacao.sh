# Ativação (§22.9: try no primeiro uso)
titulo "$(t "Activation" "Ativação")"
if [[ "$ATIVAR" == on ]]; then
    a_cmd_sis "LowPan Shells $(t "on every login" "em todo login") (on)" \
        "systemctl --user is-enabled -q lowpan-shells.service && systemctl --user is-active -q lowpan-shells.service" \
        "'$PROJETO/system/lowpan-shells-switch' on" "'$PROJETO/system/lowpan-shells-switch' off"
else
    a_cmd_sis "LowPan Shells $(t "in this session" "nesta sessão") (try)" \
        "systemctl --user is-active -q lowpan-shells.service" \
        "'$PROJETO/system/lowpan-shells-switch' try" "'$PROJETO/system/lowpan-shells-switch' off"
fi
