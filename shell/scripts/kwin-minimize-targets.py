#!/usr/bin/env python3
"""LowPan Shells — destino do efeito de minimizar Achatar2 (kwin4_effect_squash2) = o ícone do app na dock.

Sem o painel do Plasma o KWin não tem iconGeometry (a dock do Quickshell não publica set_minimized_geometry), então
o efeito levava toda janela para o centro de baixo da tela. A dock calcula onde fica cada ícone e manda para cá; o
valor vai para kwinrc [Effect-kwin4_effect_squash2] Targets e o efeito é reconfigurado (lê pelo config/main.xml).

  kwin-minimize-targets.py set "c:kitty=10,1020,40,40;p:1234=10,1020,40,40;..."

Chaves: c:<resourceClass em minúsculas> e p:<pid>; valor = x,y,largura,altura em coordenadas globais do KWin.
Só grava se o valor mudou. Edita por linhas (nada de kwriteconfig6 --delete, que deixa [$d] no arquivo).
"""
import os
import subprocess
import sys

GROUP = "Effect-kwin4_effect_squash2"
KEY = "Targets"
EFFECT = "kwin4_effect_squash2"
KWINRC = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "kwinrc")


def read_lines():
    try:
        with open(KWINRC, encoding="utf-8") as f:
            return f.read().split("\n")
    except OSError:
        return []


def put(value):
    lines = read_lines()
    entry = KEY + "=" + value
    start = next((i for i, l in enumerate(lines) if l.strip() == "[" + GROUP + "]"), None)
    if start is None:
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", "[" + GROUP + "]", entry, ""]
    else:
        end = start + 1
        while end < len(lines) and not lines[end].strip().startswith("["):
            end += 1
        found = next((i for i in range(start + 1, end) if lines[i].strip().startswith(KEY + "=")), None)
        if found is not None:
            if lines[found] == entry:
                return False
            lines[found] = entry
        else:
            lines.insert(start + 1, entry)
    tmp = KWINRC + ".lowpan-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, KWINRC)
    return True


def reconfigure():
    # sem o efeito carregado o KWin só responde com erro: o valor fica no kwinrc para quando ele for ligado
    subprocess.run(["busctl", "--user", "call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects",
                    "reconfigureEffect", "s", EFFECT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main(argv):
    if len(argv) < 1 or argv[0] != "set":
        print(__doc__, file=sys.stderr)
        return 2
    value = argv[1] if len(argv) > 1 else ""
    if put(value.replace("\n", "")):
        reconfigure()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
