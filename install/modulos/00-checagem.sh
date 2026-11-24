# Pré-checagem (§22.5 passo 1): erro aqui impede o instalar; no plano só mostra.
titulo "$(t "Checks" "Checagem")"
CHECAGEM_ERRO=0
falhou() { st_erro "$1"; CHECAGEM_ERRO=1; }
[[ $EUID -ne 0 ]] && st_ok "$(t "not root" "não é root")" || falhou "$(t "do not run as root" "não rode como root")"
command -v pacman >/dev/null && st_ok "Arch ($(. /etc/os-release; echo "$PRETTY_NAME"))" || falhou "$(t "pacman not found: only Arch and derivatives" "pacman não encontrado: só Arch e derivados")"
for c in kreadconfig6 kwriteconfig6 qdbus6 systemctl python3; do command -v $c >/dev/null || falhou "$(t "missing" "falta") $c"; done
# versão pelo pacman: rodar o kwin_wayland --version dentro de uma sessão foi morto (saída 137) na VM e, com
# pipefail + set -e, derrubava o instalador (2026-11-22). O pacman só lê o banco de pacotes.
kv="$(pacman -Q kwin 2>/dev/null | awk '{print $2}' || true)"; kv="${kv%%-*}"; kv="${kv#*:}"
if [[ -z "$kv" ]]; then falhou "$(t "KWin (Plasma 6) not found" "KWin (Plasma 6) não encontrado")"
elif [[ "$(printf '%s\n6.8\n' "$kv" | sort -V | head -1)" == 6.8 ]]; then st_ok "KWin $kv"
else falhou "KWin $kv: $(t "needs 6.8 or newer" "precisa do 6.8 ou mais novo")"; fi
[[ "${XDG_SESSION_TYPE:-}" == wayland ]] && st_ok "$(t "Wayland session" "sessão Wayland")" \
    || st_aviso "$(t "not inside a Wayland Plasma session: keys and KWin steps need one" "fora de uma sessão Plasma Wayland: atalhos e passos do KWin precisam dela")"
[[ "$PROJETO" == *" "* ]] && st_aviso "$(t "project path has a space" "o caminho do projeto tem espaço") ($PROJETO): $(t "use a path without spaces on new machines" "nas máquinas novas use um caminho sem espaço") (§22.9)" \
    || st_ok "$(t "project at" "projeto em") $PROJETO"
if ! grep -qv '^\s*\(#\|$\)' "$PROJETO/install/pacotes-aur.txt"; then :   # nada do AUR na lista: não precisa de helper
elif command -v yay >/dev/null || command -v paru >/dev/null; then st_ok "$(t "AUR helper" "helper do AUR"): $(command -v yay || command -v paru)"
else st_aviso "$(t "no AUR helper (yay/paru): AUR packages will be listed, not installed" "sem helper do AUR (yay/paru): os pacotes do AUR serão listados, não instalados")"; fi
ls /sys/class/power_supply/BAT* >/dev/null 2>&1 && st_ok "$(t "laptop (battery found)" "notebook (bateria encontrada)")" || st_ok "$(t "desktop (no battery)" "desktop (sem bateria)")"
mon="$(kscreen-doctor -j 2>/dev/null | python3 -I -c 'import json,sys; print(" ".join(o["name"] for o in json.load(sys.stdin)["outputs"] if o.get("enabled")))' 2>/dev/null || true)"
if [[ -n "$mon" ]]; then st_ok "$(t "monitors" "monitores"): $mon"; fi   # if: última linha (ver 70-nautilus)
