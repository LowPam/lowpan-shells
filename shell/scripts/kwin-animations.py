#!/usr/bin/env python3
"""LowPan Shells: animações das janelas no KWin (página Janelas, modo KWin).

  kwin-animations.py state                     JSON: categorias, efeitos instalados, estilos, estilo ativo
  kwin-animations.py set CATEGORIA EFEITO|none liga um efeito da categoria (desliga os outros dela)
  kwin-animations.py duration CATEGORIA MS     duração do efeito ligado na categoria (0 = padrão do efeito)
  kwin-animations.py apply-preset ID           aplica um estilo pronto
  kwin-animations.py tiling-delays             grava as esperas do LowPan Tiling (fechar/minimizar) pelo efeito ligado

Tudo vai para o kwinrc ([Plugins] <id>Enabled e [Effect-<id>] <chave de duração>), o mesmo que a
página Animações do KDE grava, e o KWin é avisado na hora (loadEffect/unloadEffect/reconfigure).
Nunca toca no kdeglobals (a velocidade global do KDE fica de fora: lowpan.allowAppTheming false).
Os estilos prontos usam só efeitos que vêm com o KWin; os de terceiros instalados aparecem nas listas.
Saída de set/duration/apply-preset: {"success": true} ou {"success": false, "error": "..."}.
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HOME = os.path.expanduser("~")
KWINRC = os.path.join(os.environ.get("XDG_CONFIG_HOME", HOME + "/.config"), "kwinrc")
DATA_DIRS = [os.environ.get("XDG_DATA_HOME", HOME + "/.local/share")] + \
    os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")

CATEGORIES = [
    ("open", "toplevel-open-close-animation", "Open and close"),
    ("minimize", "minimize", "Minimize"),
    ("maximize", "maximize", "Maximize"),
    ("fullscreen", "fullscreen", "Full screen"),
    ("desktop", "desktop-animations", "Switch workspace"),
]
CAT_BY_ID = {c[0]: c for c in CATEGORIES}

# Efeitos em C++ que vêm com o KWin (sem metadata.json para ler): categoria, nome, ligado por
# padrão, chaves de duração e duração padrão (ms). Chaves testadas no KWin 6.8 (PLANEJAMENTO §20).
NATIVE_CPP = {
    "glide": ("toplevel-open-close-animation", "Tilt and glide", False, ["Duration"], 160),
    "magiclamp": ("minimize", "Magic Lamp", False, ["AnimationDuration"], 250),
    "slide": ("desktop-animations", "Slide", True, [], 0),
}
# C++ de terceiros conhecidos (o .so não tem metadata legível daqui).
EXTRA_CPP = {
    "libkwin4_effect_yetanothermagiclamp": ("minimize", "Yet Another Magic Lamp", False, [], 0),
}
# Efeitos JS nativos cujo main.xml diz 0 (= o código decide): duração real do código.
JS_DEFAULT_MS = {"scale": 200, "fade": 150}

# Estilos prontos: só efeitos nativos. durations: chave -> ms (None = padrão do efeito, chave apagada).
# demo: o mesmo formato dos estilos do Niri, para a galeria animar a demonstração.
def _demo(open_ms, close_ms, curve="ease-out-cubic"):
    return {"window-open": {"duration-ms": open_ms, "curve": curve},
            "window-close": {"duration-ms": close_ms, "curve": curve},
            "horizontal-view-movement": {"spring": [1, 800, 0.0001]}}

PRESETS = [
    {"id": "smooth", "name": "Smooth", "description": "Windows grow in place and fold into the Dock.",
     "effects": {"open": "scale", "minimize": "magiclamp", "maximize": "maximize", "fullscreen": "fullscreen", "desktop": "slide"},
     "durations": {"open": None, "minimize": None}, "types": _demo(200, 200)},
    {"id": "quick", "name": "Quick", "description": "A short fade; everything gets out of the way.",
     "effects": {"open": "fade", "minimize": "magiclamp", "maximize": "maximize", "fullscreen": "fullscreen", "desktop": "slide"},
     "durations": {"open": 120, "minimize": 150}, "types": _demo(120, 120, "ease-out-quad")},
    {"id": "glide", "name": "Gliding", "description": "Windows tilt in from below and slip away.",
     "effects": {"open": "glide", "minimize": "magiclamp", "maximize": "maximize", "fullscreen": "fullscreen", "desktop": "slide"},
     "durations": {"open": None, "minimize": None}, "types": _demo(160, 160, "ease-out-expo")},
    {"id": "minimal", "name": "Minimal", "description": "Only a quick fade; nothing else moves.",
     "effects": {"open": "fade", "minimize": None, "maximize": None, "fullscreen": None, "desktop": "fadedesktop"},
     "durations": {"open": 80}, "types": _demo(80, 80, "linear")},
    {"id": "none", "name": "None", "description": "Windows appear and leave at once.",
     "effects": {"open": None, "minimize": None, "maximize": None, "fullscreen": None, "desktop": None},
     "durations": {}, "types": _demo(1, 1, "linear")},
]
PRESET_BY_ID = {p["id"]: p for p in PRESETS}


# ---------- kwinrc ----------

def read_kwinrc():
    groups, cur = {}, None
    try:
        with open(KWINRC, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    cur = groups.setdefault(line[1:-1], {})
                elif cur is not None and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    cur[k.split("[")[0].strip()] = v.strip()
    except OSError:
        pass
    return groups


def write(group, key, value):
    cmd = ["kwriteconfig6", "--file", "kwinrc", "--group", group, "--key", key]
    cmd += ["--delete"] if value is None else [str(value)]
    subprocess.run(cmd, check=True)


def kwin(method, *args):
    try:
        import dbus
        obj = dbus.SessionBus().get_object("org.kde.KWin", "/Effects")
        return getattr(dbus.Interface(obj, "org.kde.kwin.Effects"), method)(*args)
    except Exception:
        return None


def reconfigure():
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---------- efeitos instalados ----------

def lang_name(kp):
    lang = (os.environ.get("LANGUAGE") or os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES")
            or os.environ.get("LANG") or "").split(":")[0].split(".")[0]
    for key in ("Name[%s]" % lang, "Name[%s]" % lang.split("_")[0], "Name"):
        if kp.get(key):
            return kp[key]
    return ""


def js_durations(path):
    """Chaves de duração do main.xml e o padrão (ms)."""
    keys, default = [], 0
    xml = os.path.join(path, "contents/config/main.xml")
    if not os.path.exists(xml):
        return keys, default
    try:
        for e in ET.parse(xml).iter():
            if not e.tag.endswith("entry"):
                continue
            name = e.get("name") or ""
            if name in ("Duration", "AnimationTime", "AnimationDuration", "FadeInTime", "FadeOutTime"):
                keys.append(name)
                for c in e:
                    if c.tag.endswith("default") and (c.text or "").strip().isdigit():
                        default = max(default, int(c.text.strip()))
    except ET.ParseError:
        pass
    return keys, default


def needs_icon(path):
    """Efeito de minimizar que desiste sem iconGeometry (sem o painel do Plasma ninguém publica)."""
    try:
        with open(os.path.join(path, "contents/code/main.js"), encoding="utf-8") as f:
            src = f.read()
    except OSError:
        return False
    return "iconGeometry" in src and "LowPan" not in src


def installed():
    """{id: {...}} de todos os efeitos com categoria exclusiva que o KWin conhece."""
    known = set(str(x) for x in (kwin("listOfEffects") or []))
    effects = {}
    for base in DATA_DIRS:
        d = os.path.join(base, "kwin/effects")
        if not os.path.isdir(d):
            continue
        for eid in sorted(os.listdir(d)):
            if eid in effects:
                continue  # o de XDG_DATA_HOME vence
            path = os.path.join(d, eid)
            try:
                with open(os.path.join(path, "metadata.json"), encoding="utf-8") as f:
                    meta = json.load(f)
            except (OSError, ValueError):
                continue
            cat = meta.get("X-KWin-Exclusive-Category")
            if not cat:
                continue
            kp = meta.get("KPlugin", {})
            keys, default = js_durations(path)
            native = path.startswith("/usr/")
            dflt = kp.get("EnabledByDefault", False)
            effects[eid] = {
                # sem o sufixo do pacote ("TV Effect [Burn-My-Windows]" → "TV Effect"): no seletor da página Janelas o
                # nome longo vazava da fatia (3ª rodada do teste do instalador, 2026-11-21)
                "id": eid, "category": cat, "name": re.sub(r"\s*\[[^\]]*\]\s*$", "", lang_name(kp)) or eid, "native": native,
                "enabledByDefault": dflt is True or str(dflt).lower() == "true",
                "keys": keys, "defaultMs": default or JS_DEFAULT_MS.get(eid, 0),
                "needsIcon": cat == "minimize" and needs_icon(path),
            }
    for table, native in ((NATIVE_CPP, True), (EXTRA_CPP, False)):
        for eid, (cat, name, dflt, keys, ms) in table.items():
            if eid in effects or (known and eid not in known):
                continue
            effects[eid] = {"id": eid, "category": cat, "name": name, "native": native,
                            "enabledByDefault": dflt, "keys": keys, "defaultMs": ms, "needsIcon": False}
    return effects


def plasmashell_running():
    return subprocess.run(["pgrep", "-x", "plasmashell"], stdout=subprocess.DEVNULL).returncode == 0


# ---------- estado ----------

def enabled(eff, plugins):
    v = plugins.get(eff["id"] + "Enabled")
    return (v == "true") if v is not None else eff["enabledByDefault"]


def duration_of(eff, rc):
    grp = rc.get("Effect-" + eff["id"], {})
    for k in eff["keys"]:
        v = grp.get(k, "")
        if v.isdigit() and int(v) > 0:
            return int(v), True
    return eff["defaultMs"], False


def state():
    rc = read_kwinrc()
    plugins = rc.get("Plugins", {})
    effects = installed()
    no_icon = not plasmashell_running()
    cats = []
    for cid, kcat, label in CATEGORIES:
        members = [e for e in effects.values() if e["category"] == kcat]
        on = [e for e in members if enabled(e, plugins)]
        active = on[0] if on else None
        dur, custom = duration_of(active, rc) if active else (0, False)
        cats.append({
            "id": cid, "label": label,
            "active": active["id"] if active else "none",
            "choices": [{"id": e["id"], "name": e["name"], "native": e["native"],
                         "warn": "noIcon" if (no_icon and e["needsIcon"]) else ""}
                        for e in sorted(members, key=lambda e: (not e["native"], e["name"].lower()))],
            "durationKeys": active["keys"] if active else [],
            "duration": dur, "durationDefault": active["defaultMs"] if active else 0, "durationCustom": custom,
        })
    by_id = {c["id"]: c for c in cats}
    presets = [p for p in PRESETS if all(e is None or e in effects for e in p["effects"].values())]
    return {"categories": cats, "presets": presets, "active": match(presets, by_id),
            "animating": any(c["active"] != "none" for c in cats if c["id"] in ("open", "minimize", "maximize"))}


def match(presets, by_id):
    for p in presets:
        ok = True
        for cid, eid in p["effects"].items():
            if by_id[cid]["active"] != (eid or "none"):
                ok = False
                break
        if not ok:
            continue
        for cid, ms in p["durations"].items():
            c = by_id[cid]
            if not c["durationKeys"]:
                continue
            if (ms is None and c["durationCustom"]) or (ms is not None and c["duration"] != ms):
                ok = False
                break
        if ok:
            return p["id"]
    return ""


# ---------- esperas do LowPan Tiling ----------
# O tiling reorganiza as vizinhas só depois de a animação de fechar/minimizar terminar (PLANEJAMENTO §21.11).
# Efeitos que não dizem a duração (C++ ou main.xml com 0): duração do código, medida/conhecida.
KNOWN_MS = {"kwin4_effect_squash2": 350, "kinetic_squash": 317, "kinetic_scale": 317, "squash": 250,
            "libkwin4_effect_yetanothermagiclamp": 300}
UNKNOWN_MS = 300   # efeito de terceiro sem duração conhecida
MARGIN_MS = 40     # o último quadro termina antes de as vizinhas andarem


def speed_factor():
    # só leitura: a velocidade global do KDE (kdeglobals) não é tocada
    try:
        out = subprocess.run(["kreadconfig6", "--file", "kdeglobals", "--group", "KDE", "--key",
                              "AnimationDurationFactor"], capture_output=True, text=True).stdout.strip()
        return float(out) if out else 1.0
    except (OSError, ValueError):
        return 1.0


def tiling_delays(effects=None, rc=None):
    effects = effects or installed()
    rc = rc or read_kwinrc()
    plugins = rc.get("Plugins", {})
    out = {}
    for cid, key in (("open", "lowpanCloseDelay"), ("minimize", "lowpanMinimizeDelay")):
        kcat = CAT_BY_ID[cid][1]
        on = [e for e in effects.values() if e["category"] == kcat and enabled(e, plugins)]
        if not on:
            ms = 0
        else:
            dur = max(duration_of(e, rc)[0] or KNOWN_MS.get(e["id"], UNKNOWN_MS) for e in on)
            ms = int(round(dur * speed_factor())) + MARGIN_MS
        out[key] = ms
        if rc.get("Script-lowpan-tiling", {}).get(key) != str(ms):
            write("Script-lowpan-tiling", key, ms)
    return out


# ---------- escrita ----------

def set_effect(cid, eid, effects=None, rc=None, live=True):
    if cid not in CAT_BY_ID:
        raise ValueError("categoria desconhecida: " + cid)
    kcat = CAT_BY_ID[cid][1]
    effects = effects or installed()
    rc = rc or read_kwinrc()
    plugins = rc.get("Plugins", {})
    if eid not in (None, "none") and (eid not in effects or effects[eid]["category"] != kcat):
        raise ValueError("efeito %s não é de %s" % (eid, cid))
    for e in effects.values():
        if e["category"] != kcat:
            continue
        want = e["id"] == eid
        if enabled(e, plugins) != want or plugins.get(e["id"] + "Enabled") is None:
            write("Plugins", e["id"] + "Enabled", "true" if want else "false")
        if live:
            kwin("loadEffect" if want else "unloadEffect", e["id"])


def set_duration(cid, ms, effects=None, rc=None, live=True):
    effects = effects or installed()
    rc = rc or read_kwinrc()
    plugins = rc.get("Plugins", {})
    kcat = CAT_BY_ID[cid][1]
    on = [e for e in effects.values() if e["category"] == kcat and enabled(e, plugins)]
    if not on:
        raise ValueError("nenhum efeito ligado em " + cid)
    eff = on[0]
    if not eff["keys"]:
        raise ValueError("%s não tem duração ajustável" % eff["id"])
    for k in eff["keys"]:
        write("Effect-" + eff["id"], k, None if not ms or ms <= 0 else int(ms))
    if live:
        kwin("reconfigureEffect", eff["id"])


def apply_preset(pid):
    p = PRESET_BY_ID.get(pid)
    if not p:
        raise ValueError("estilo desconhecido: " + pid)
    effects = installed()
    for cid, eid in p["effects"].items():
        if eid is not None and eid not in effects:
            raise ValueError("efeito %s não está instalado" % eid)
    for cid, eid in p["effects"].items():
        set_effect(cid, eid or "none", effects, read_kwinrc())
    for cid, ms in p["durations"].items():
        try:
            set_duration(cid, ms or 0, effects, read_kwinrc())
        except ValueError:
            pass


def main(argv):
    cmd = argv[0] if argv else "state"
    if cmd == "state":
        print(json.dumps(state(), ensure_ascii=False))
        return 0
    try:
        if cmd == "set" and len(argv) == 3:
            set_effect(argv[1], argv[2])
        elif cmd == "duration" and len(argv) == 3:
            set_duration(argv[1], int(argv[2]))
        elif cmd == "apply-preset" and len(argv) == 2:
            apply_preset(argv[1])
        elif cmd == "tiling-delays":
            print(json.dumps(tiling_delays()))
            reconfigure()
            return 0
        else:
            print(__doc__, file=sys.stderr)
            return 2
        tiling_delays()  # trocou o efeito ou a duração: o tiling espera o tempo novo
        reconfigure()
        print(json.dumps({"success": True}))
        return 0
    except (ValueError, subprocess.CalledProcessError) as e:
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
