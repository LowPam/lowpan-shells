#!/usr/bin/env python3
"""LowPan Shells — apps que sempre flutuam no LowPan Tiling (Configurações › Janelas › Tiling).

A verdade é o kwinrc [Script-lowpan-tiling] floatingClass (lista separada por vírgula de resourceClass), a opção
herdada do Krohnkite. O motor relê a lista a cada segundo: entrar/sair dela vale na hora, também para as janelas
já abertas. A janela principal de um app da lista abre com o último tamanho usado (memória flutuante do motor).

  kwin-float-apps.py get           JSON: ["org.gnome.Nautilus", ...]
  kwin-float-apps.py set A,B,...   grava a lista (vazia = "") e manda o KWin reconfigurar (o motor só relê assim)
  kwin-float-apps.py pick          o cursor vira mira (KWin queryWindowInfo); JSON com a janela clicada, {} se cancelou

Grava editando linhas (nada de kwriteconfig6 --delete, que deixa [$d] no arquivo).
"""
import json
import os
import sys

GROUP = "Script-lowpan-tiling"
KEY = "floatingClass"
KWINRC = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "kwinrc")


def clean(apps):
    out = []
    for app in apps:
        app = str(app).strip().replace(",", "")
        if app and app not in out:
            out.append(app)
    return out


def read_lines():
    try:
        with open(KWINRC, encoding="utf-8") as f:
            return f.read().split("\n")
    except OSError:
        return []


def get():
    group = None
    for line in read_lines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            group = s[1:-1]
        elif group == GROUP and s.startswith(KEY + "="):
            return clean(s.split("=", 1)[1].split(","))
    return []


def put(apps):
    lines = read_lines()
    value = KEY + "=" + ",".join(clean(apps))
    start = next((i for i, l in enumerate(lines) if l.strip() == "[" + GROUP + "]"), None)
    if start is None:
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", "[" + GROUP + "]", value, ""]
    else:
        end = start + 1
        while end < len(lines) and not lines[end].strip().startswith("["):
            end += 1
        found = next((i for i in range(start + 1, end) if lines[i].strip().startswith(KEY + "=")), None)
        if found is not None:
            lines[found] = value
        else:
            lines.insert(start + 1, value)
    tmp = KWINRC + ".lowpan-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, KWINRC)
    reconfigure()


def reconfigure():
    # o readConfig dos scripts do KWin só enxerga o kwinrc novo depois de um reconfigure
    try:
        import dbus
        kwin = dbus.SessionBus().get_object("org.kde.KWin", "/KWin")
        dbus.Interface(kwin, "org.kde.KWin").reconfigure()
    except Exception as e:  # sem KWin (outra sessão): a lista vale no próximo login
        print("reconfigure: " + str(e), file=sys.stderr)


def pick():
    import dbus
    try:
        kwin = dbus.Interface(dbus.SessionBus().get_object("org.kde.KWin", "/KWin"), "org.kde.KWin")
        info = kwin.queryWindowInfo(timeout=120)
    except dbus.exceptions.DBusException:
        return {}  # Esc, clique fora de janela ou tempo esgotado
    keys = ("resourceClass", "resourceName", "desktopFile", "caption", "type")
    return {k: str(info[k]) for k in keys if k in info}


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "get":
        print(json.dumps(get(), ensure_ascii=False))
    elif cmd == "set":
        put(argv[1].split(",") if len(argv) > 1 else [])
        print(json.dumps(get(), ensure_ascii=False))
    elif cmd == "pick":
        print(json.dumps(pick(), ensure_ascii=False))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
