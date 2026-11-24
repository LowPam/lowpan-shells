#!/usr/bin/env bash
set -euo pipefail

# restart-shell.sh — called by QML "Reload shell" buttons.
#
# Delegates to `inir restart` which correctly kills the wrapper process
# before killing the qs child, avoiding the race where the wrapper loop
# respawns qs before this script can detect the gap.

# LowPan Shells (§21.54): no KWin o shell roda como lowpan-shells.service. O `inir restart` não conhece esse
# serviço: mata o qs e sobe outro por fora — mas o novo nasce no cgroup do serviço e o systemd o derruba junto
# quando o qs principal sai (ficava ~1 min sem shell). Então pede ao systemd, sem esperar (--no-block: este
# script também está no cgroup e morre na parada).
if systemctl --user is-active --quiet lowpan-shells.service 2>/dev/null; then
    exec systemctl --user --no-block restart lowpan-shells.service
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_script="$config_dir/scripts/inir"

if [[ ! -f "$launcher_script" ]]; then
    launcher_script="$script_dir/inir"
fi

if [[ ! -f "$launcher_script" ]]; then
    echo "restart-shell: cannot find inir launcher" >&2
    exit 1
fi

exec /usr/bin/env bash "$launcher_script" restart -c "$config_dir"
