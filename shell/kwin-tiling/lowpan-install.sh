#!/usr/bin/env bash
# LowPan Tiling: compila (TypeScript → pkg/) e instala em ~/.local/share/kwin/scripts/lowpan-tiling.
#   lowpan-install.sh                 compila e instala (desenvolvimento; precisa de nodejs/npm)
#   lowpan-install.sh --sem-compilar  só instala o pkg/ versionado no projeto (o install.sh usa esta: sem nodejs,
#                                     npm nem internet). Mudou o src/? Rode sem a opção e faça o commit do pkg/ junto.
# O KWin guarda o código dos scripts na memória pelo caminho: depois de instalar uma versão nova
# é preciso sair e entrar na sessão para valer (desligar/ligar o script não relê o arquivo).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
if [ "${1:-}" != --sem-compilar ]; then
    [ -d node_modules ] || npm ci --no-audit --no-fund
    make >/dev/null
fi
[ -f pkg/metadata.json ] || { echo "falta o motor compilado (pkg/): rode sem --sem-compilar" >&2; exit 1; }
dest="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/lowpan-tiling"
mkdir -p "$dest"
# espelha pkg/ no destino (apaga o que não existe mais no pacote)
rsync -a --delete pkg/ "$dest/"
# efeito do recuo ao arrastar (efeito KWin JS; o liga/desliga do tiling o liga)
fx="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/effects/lowpan_drag_inset"
mkdir -p "$fx"
rsync -a --delete effect/lowpan_drag_inset/ "$fx/"
echo "instalado em $dest (versão $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' pkg/metadata.json))"
echo "para valer: saia e entre na sessão"
