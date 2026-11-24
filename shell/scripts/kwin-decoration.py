#!/usr/bin/env python3
"""LowPan Shells — decoração das janelas no KWin (Breeze) e a sombra dela.

A sombra das janelas é a da decoração: para o KWin ela faz parte da janela, então acompanha o Wobbly Windows e as
animações de abrir/fechar/minimizar (a do efeito Rounded Corners só pinta dentro dessa faixa). Apps GTK desenham a
própria (tema Breeze-GTK); o Nautilus do iRiS (tema LowPanNautilus) recebe a mesma sombra em CSS, gerada aqui
(sombra.css, vale na próxima abertura do Nautilus). A verdade é o breezerc [Common] e o kwinrc [org.kde.kdecoration2] — os mesmos que a
janela do KDE (Decorações de janela › Breeze) grava; as duas convivem.

  kwin-decoration.py state                 JSON: decoração em uso e a sombra do Breeze
  kwin-decoration.py set CHAVE VALOR ...   ShadowSize (ShadowNone…ShadowVeryLarge), ShadowStrength (25–255),
                                           ShadowColor (#rrggbb); grava e avisa o KWin
  kwin-decoration.py use-breeze            troca a decoração para o Breeze
  kwin-decoration.py gtk                   só regera a sombra do Nautilus (sombra.css) a partir do breezerc
"""
import json
import os
import subprocess
import sys

CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
BREEZE_LIBRARY = "org.kde.breeze"
SIZES = ["ShadowNone", "ShadowSmall", "ShadowMedium", "ShadowLarge", "ShadowVeryLarge"]
# padrões do /usr/share/config.kcfg/breeze-decoration.kcfg (Breeze 6.8)
DEFAULTS = {"ShadowSize": "ShadowLarge", "ShadowStrength": 255, "ShadowColor": "#000000"}


def read_group(name, group):
    out, inside = {}, False
    try:
        with open(os.path.join(CONFIG, name), encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    inside = line == "[" + group + "]"
                elif inside and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def to_hex(text):
    text = text.strip()
    if text.startswith("#") and len(text) in (7, 9):
        return text[:7].lower()
    try:
        r, g, b = (max(0, min(255, int(p))) for p in text.split(",")[:3])
        return "#%02x%02x%02x" % (r, g, b)
    except (ValueError, TypeError):
        return None


def kwrite(name, group, key, value):
    subprocess.run(["kwriteconfig6", "--file", name, "--group", group, "--key", key, value], check=True)


# Sombra do Breeze 6 (breezedecoration.cpp, s_shadowParams): deslocamento vertical, raio e opacidade da camada
# principal. Em CSS vira uma camada só, calibrada pelo print da sombra Média sobre papel de parede claro
# (2026-11-12): ao lado de uma janela do Breeze o fundo escurece 43% na borda, 25% a 8 px, 11% a 16 px e some em
# ~30 px = desfoque 27 px, sem expansão, opacidade 0.91. Os outros tamanhos escalam pelo raio (÷16) e pela
# opacidade (÷0.24) do Breeze.
BREEZE_SHADOWS = {
    "ShadowNone": None,
    "ShadowSmall": (3, 12, 0.26),
    "ShadowMedium": (4, 16, 0.24),
    "ShadowLarge": (5, 20, 0.22),
    "ShadowVeryLarge": (6, 24, 0.20),
}
NAUTILUS_SHADOW = os.path.join(os.path.expanduser("~/.themes/LowPanNautilus/gtk-4.0"), "sombra.css")


def write_gtk_shadow():
    # §21.29/§21.66: o Nautilus é CSD (desenha a própria sombra); o gtk*.css do LowPanNautilus importa este arquivo
    if not os.path.isdir(os.path.dirname(NAUTILUS_SHADOW)):
        return
    v = state()["values"]
    params = BREEZE_SHADOWS.get(v["ShadowSize"])
    h = v["ShadowColor"]
    rgb = "%d, %d, %d" % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
    k = v["ShadowStrength"] / 255.0
    if params is None:
        shadow = "none"
    else:
        dy, radius, alpha = params
        f = radius / 16.0
        shadow = "0 %dpx %dpx rgba(%s, %.3f)" % (dy, round(27 * f), rgb, min(1.0, 0.91 * alpha / 0.24 * k))
    css = ("/* Gerado por shell/scripts/kwin-decoration.py a partir do breezerc (%s, %d, %s): a mesma sombra das\n"
           "   janelas do KWin (Configurações › Janelas › Decoração das janelas). Não editar à mão. */\n"
           "window.csd, window.csd:backdrop { box-shadow: %s; }\n"
           "window.csd.maximized, window.csd.fullscreen { box-shadow: none; }\n"
           % (v["ShadowSize"], v["ShadowStrength"], h, shadow))
    try:
        with open(NAUTILUS_SHADOW + ".tmp", "w", encoding="utf-8") as f:
            f.write(css)
        os.replace(NAUTILUS_SHADOW + ".tmp", NAUTILUS_SHADOW)
    except OSError as e:
        print("sombra do Nautilus: " + str(e), file=sys.stderr)


def reload_kwin():
    # o mesmo sinal que a janela do KDE manda: o KWin relê a decoração e as configurações dela
    subprocess.run(["dbus-send", "--session", "--type=signal", "/KWin", "org.kde.KWin.reloadConfig"], check=False)


def state():
    deco = read_group("kwinrc", "org.kde.kdecoration2")
    common = read_group("breezerc", "Common")
    library = deco.get("library", BREEZE_LIBRARY)  # sem a chave, o KWin usa o Breeze…
    theme = deco.get("theme", "")
    if theme.startswith("__aurorae__"):  # …mas um tema Aurorae no "theme" vale mesmo sem "library"
        library = "org.kde.kwin.aurorae"
    size = common.get("ShadowSize", DEFAULTS["ShadowSize"])
    try:
        strength = int(common.get("ShadowStrength", DEFAULTS["ShadowStrength"]))
    except ValueError:
        strength = DEFAULTS["ShadowStrength"]
    return {
        "library": library,
        "theme": theme,
        "breeze": library == BREEZE_LIBRARY,
        "values": {
            "ShadowSize": size if size in SIZES else DEFAULTS["ShadowSize"],
            "ShadowStrength": strength,
            "ShadowColor": to_hex(common.get("ShadowColor", "")) or DEFAULTS["ShadowColor"],
        },
    }


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(state()))
        return 0
    try:
        if argv[0] == "set":
            pairs = argv[1:]
            if not pairs or len(pairs) % 2:
                raise ValueError("set wants KEY VALUE pairs")
            for i in range(0, len(pairs), 2):
                key, value = pairs[i], pairs[i + 1]
                if key == "ShadowSize":
                    if value not in SIZES:
                        raise ValueError("tamanho inválido: " + value)
                elif key == "ShadowStrength":
                    value = str(max(25, min(255, int(round(float(value))))))
                elif key == "ShadowColor":
                    h = to_hex(value)
                    if not h:
                        raise ValueError("cor inválida: " + value)
                    value = "%d,%d,%d" % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
                else:
                    raise ValueError("chave desconhecida: " + key)
                kwrite("breezerc", "Common", key, value)
        elif argv[0] == "gtk":
            write_gtk_shadow()
            print(json.dumps({"success": True}))
            return 0
        elif argv[0] == "use-breeze":
            kwrite("kwinrc", "org.kde.kdecoration2", "library", BREEZE_LIBRARY)
            kwrite("kwinrc", "org.kde.kdecoration2", "theme", "Breeze")
        else:
            raise ValueError("comando desconhecido: " + argv[0])
    except (ValueError, subprocess.CalledProcessError) as e:
        print(json.dumps({"success": False, "error": str(e)}))
        return 1
    reload_kwin()
    write_gtk_shadow()
    print(json.dumps({"success": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
