#!/usr/bin/env python3
"""LowPan Shells — cantos arredondados das janelas no KWin (nosso Rounded Corners, kwin4_effect_lowpancorners).

O equivalente ao geometry-corner-radius/clip-to-geometry que o iNiR põe na config do Niri: o KWin não tem
nativo, então usamos o efeito de terceiro, compilado com nomes próprios (pacote lowpan-kwin-rounded-corners,
extras/lowpan-kwin-rounded-corners) para conviver com o Rounded Corners que a pessoa já tiver: o iRiS usa este, o
Plasma o dela (system/lowpan-cantos-ambiente). A verdade é o kwinrc [LowPan-Round-Corners] — a mesma que a janela de
configuração do KDE do nosso efeito grava; as duas convivem.

  kwin-corners.py state                 JSON: instalado, ligado e todas as chaves (com os padrões do efeito)
  kwin-corners.py set CHAVE VALOR ...   grava pares e avisa o efeito (reconfigureEffect)
  kwin-corners.py enable on|off         liga/desliga o efeito (kwinrc [Plugins] + loadEffect/unloadEffect)

Valores: bool "true"/"false", números, listas separadas por vírgula, cores "#rrggbb" (gravadas como r,g,b).
Chaves e padrões copiados de src/kcm/options.kcfg do efeito (0.11.0, commit 66d7ce9).
"""
import json
import os
import subprocess
import sys

EFFECT = "kwin4_effect_lowpancorners"
GROUP = "LowPan-Round-Corners"
KWINRC = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "kwinrc")

# (chave, tipo, padrão)  tipos: u=inteiro, d=decimal, b=bool, c=cor, l=lista
_ROWS = [
    ("Size", "u", 20), ("InactiveCornerRadius", "u", 20),
    ("UseSquircleShape", "b", True), ("Squircleness", "d", 0.55),
    ("AnimationDuration", "u", 250), ("MarkWindowsTranslucent", "b", True),
    ("UseNativeDecorationShadows", "b", True),
    ("ShadowSize", "u", 60), ("InactiveShadowSize", "u", 40),
    ("ShadowColor", "c", "#000000"), ("InactiveShadowColor", "c", "#000000"),
    ("ActiveShadowAlpha", "u", 128), ("InactiveShadowAlpha", "u", 64),
    ("ActiveShadowPalette", "u", 11), ("InactiveShadowPalette", "u", 11),
    ("ActiveShadowUsePalette", "b", False), ("InactiveShadowUsePalette", "b", False),
    ("ActiveShadowUseCustom", "b", False), ("InactiveShadowUseCustom", "b", False),
    ("Inclusions", "l", []), ("Exclusions", "l", []),
    ("IncludeNormalWindows", "b", True), ("IncludeDialogs", "b", True),
    ("DisableRoundTile", "b", True), ("DisableOutlineTile", "b", True),
    ("DisableRoundMaximize", "b", True), ("DisableOutlineMaximize", "b", True),
    ("DisableRoundFullScreen", "b", True), ("DisableOutlineFullScreen", "b", True),
]
# os três contornos (principal, segundo, externo) têm o mesmo conjunto de chaves
for name, color, color2 in (("", "#000000", "#000000"), ("Second", "#ffffff", "#ffffff"), ("Outer", "#000000", "#000000")):
    thick = 0 if name == "Outer" else 1
    alpha = 85 if name == "Second" else 255
    _ROWS += [
        (name + "OutlineThickness", "d", thick), ("Inactive" + name + "OutlineThickness", "d", thick),
        (name + "OutlineColor", "c", color), ("Inactive" + name + "OutlineColor", "c", color),
        ("Active" + name + "OutlineAlpha", "u", alpha), ("Inactive" + name + "OutlineAlpha", "u", alpha),
        ("Active" + name + "OutlinePalette", "u", 12), ("Inactive" + name + "OutlinePalette", "u", 12),
        ("Active" + name + "OutlineUsePalette", "b", False), ("Inactive" + name + "OutlineUsePalette", "b", False),
        ("Active" + name + "OutlineUseCustom", "b", True), ("Inactive" + name + "OutlineUseCustom", "b", True),
        (name + "OutlineIsGradient", "b", False), ("Inactive" + name + "OutlineIsGradient", "b", False),
        (name + "OutlineColor2", "c", color2), ("Inactive" + name + "OutlineColor2", "c", color2),
        (name + "OutlineGradientAngle", "u", 45), ("Inactive" + name + "OutlineGradientAngle", "u", 45),
    ]
SCHEMA = {k: (t, d) for k, t, d in _ROWS}
NAMED = {"black": "#000000", "white": "#ffffff"}


def read_group():
    out, inside = {}, False
    try:
        with open(KWINRC, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    inside = line == "[" + GROUP + "]"
                elif inside and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def read_plugin_enabled():
    inside = False
    try:
        with open(KWINRC, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    inside = line == "[Plugins]"
                elif inside and line.startswith(EFFECT + "Enabled="):
                    return line.split("=", 1)[1].strip() == "true"
    except OSError:
        pass
    return False


def to_hex(text):
    text = text.strip()
    if text.lower() in NAMED:
        return NAMED[text.lower()]
    if text.startswith("#") and len(text) in (7, 9):
        return text[:7].lower()
    parts = [p.strip() for p in text.split(",")]
    try:
        r, g, b = (max(0, min(255, int(p))) for p in parts[:3])
        return "#%02x%02x%02x" % (r, g, b)
    except (ValueError, TypeError):
        return None


def parse(kind, text, default):
    try:
        if kind == "b":
            return text.lower() == "true"
        if kind == "u":
            return int(float(text))
        if kind == "d":
            return float(text)
        if kind == "c":
            return to_hex(text) or default
        if kind == "l":
            return [p.replace("\0", ",").strip() for p in text.replace("\\,", "\0").split(",") if p.strip()] \
                if text else []
    except ValueError:
        pass
    return default


def serialize(kind, value):
    if kind == "b":
        return "true" if str(value).lower() in ("true", "1", "yes", "on") else "false"
    if kind == "u":
        return str(max(0, int(round(float(value)))))
    if kind == "d":
        return ("%.3f" % float(value)).rstrip("0").rstrip(".")
    if kind == "c":
        h = to_hex(str(value))
        if not h:
            raise ValueError("cor inválida: %r" % value)
        return "%d,%d,%d" % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
    if kind == "l":
        items = value if isinstance(value, list) else str(value).split(",")
        return ",".join(i.strip().replace(",", "\\,") for i in items if i.strip())
    return str(value)


def installed():
    dirs = [os.path.join(d, "qt6/plugins/kwin/effects/plugins") for d in ("/usr/lib", "/usr/lib64", "/usr/local/lib")]
    dirs.append("/usr/lib/x86_64-linux-gnu/qt6/plugins/kwin/effects/plugins")
    return any(os.path.exists(os.path.join(d, EFFECT + ".so")) for d in dirs)


def effects_call(method, *args):
    try:
        import dbus
        obj = dbus.SessionBus().get_object("org.kde.KWin", "/Effects")
        return getattr(dbus.Interface(obj, "org.kde.kwin.Effects"), method)(*args)
    except Exception:
        return None


def kwrite(group, key, value):
    subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", group, "--key", key, value], check=True)


def state():
    raw = read_group()
    values = {k: (parse(t, raw[k], d) if k in raw else d) for k, (t, d) in SCHEMA.items()}
    loaded = effects_call("isEffectLoaded", EFFECT)
    return {"installed": installed(), "enabled": read_plugin_enabled(),
            "loaded": bool(loaded) if loaded is not None else None, "values": values}


SHELL_CLASS = "quickshell"


def ensure_shell_excluded():
    """as barras de abas do LowPan Tiling são janelas normais para o KWin: sem isto o efeito desenha o contorno
    (linha em cima e embaixo da barra) e a sombra em volta delas"""
    raw = read_group().get("Exclusions", "")
    items = [x for x in raw.split(",") if x]
    if SHELL_CLASS not in items:
        kwrite(GROUP, "Exclusions", ",".join(items + [SHELL_CLASS]))


def main(argv):
    if not argv or argv[0] == "state":
        print(json.dumps(state()))
        return 0
    if argv[0] == "set":
        pairs = argv[1:]
        if not pairs or len(pairs) % 2:
            print(json.dumps({"success": False, "error": "set wants KEY VALUE pairs"}))
            return 1
        try:
            for i in range(0, len(pairs), 2):
                key, value = pairs[i], pairs[i + 1]
                if key not in SCHEMA:
                    raise ValueError("chave desconhecida: " + key)
                kwrite(GROUP, key, serialize(SCHEMA[key][0], value))
            ensure_shell_excluded()
        except (ValueError, subprocess.CalledProcessError) as e:
            print(json.dumps({"success": False, "error": str(e)}))
            return 1
        effects_call("reconfigureEffect", EFFECT)
        print(json.dumps({"success": True}))
        return 0
    if argv[0] == "enable" and len(argv) > 1:
        on = argv[1] in ("on", "true", "1")
        kwrite("Plugins", EFFECT + "Enabled", "true" if on else "false")
        effects_call("loadEffect" if on else "unloadEffect", EFFECT)
        if on:
            ensure_shell_excluded()
            effects_call("reconfigureEffect", EFFECT)
        print(json.dumps({"success": True}))
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
