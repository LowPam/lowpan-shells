#!/usr/bin/env python3
"""LowPan Shells: o efeito de abrir/fechar janelas do KWin, para as janelas do próprio shell.

  kwin-open-effect.py        JSON: {"kind", "id", "duration", "qml"}

O Spotlight, a galeria de papel de parede e as Configurações não são janelas para o KWin (são
desenhados dentro de superfícies do shell que ficam abertas), então nenhum efeito do KWin os anima.
Este script descobre o efeito ligado em [Plugins] (categoria "toplevel-open-close-animation") e:

  - Burn-My-Windows (kwin4_effect_*, com shaders): converte o .frag (GLSL do KWin) para o GLSL 440
    do Qt Quick, compila com o qsb e gera um ShaderEffect em QML com os valores da config do efeito
    ([Effect-<id>] no kwinrc, senão o padrão do main.xml). kind = "shader", qml = file:// do .qml.
  - Escalonar / Esmaecer / Planar / Escala (Kinetic): kind = "scale" | "fade" | "glide" | "kinetic".
  - Nenhum ou outro efeito: kind = "none" (o shell usa a animação própria do iRiS).

duration já vem multiplicada pela velocidade global do KDE (é o animationTime() dos efeitos JS).
Os arquivos gerados ficam em ~/.cache/lowpan-shells/kwin-open-effect/<id>-<hash>/ (pasta nova a cada versão: o motor
QML guarda componentes pelo caminho: valor novo = arquivo novo).
"""
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
VERSION = "3"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "lowpan-shells", "kwin-open-effect")
QSB_CANDIDATES = ["/usr/lib/qt6/bin/qsb", "/usr/lib64/qt6/bin/qsb", "/usr/libexec/qt6/qsb", "qsb"]
NATIVE_KIND = {"scale": "scale", "fade": "fade", "glide": "glide", "kinetic_scale": "kinetic"}
# Uniforms que o próprio cabeçalho fornece (o resto vira propriedade do ShaderEffect).
STANDARD = {"uForOpening", "uIsFullscreen", "uProgress", "uDuration", "uSize", "uPadding",
            "sampler", "uTexture", "textureWidth", "textureHeight"}

QT_HEADER = """#version 440
// Gerado por LowPan Shells (scripts/kwin-open-effect.py) a partir do Burn-My-Windows
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float uProgress;
  float uForOpeningF;
  float uIsFullscreenF;
  float uDuration;
  vec2 uSize;
%MEMBERS%};
layout(binding = 1) uniform sampler2D source;
%STDDEFINES%
#define uPadding 0.0
#define iTexCoord qt_TexCoord0
#define texture2D texture
%DEFINES%
vec4 getInputColor(vec2 coords) {
  vec4 color = texture(source, coords);
  if (color.a > 0.0) color.rgb /= color.a;
  return color;
}
void setOutputColor(vec4 outColor) {
  fragColor = vec4(outColor.rgb * outColor.a, outColor.a) * qt_Opacity;
}
"""


def load_animations():
    spec = importlib.util.spec_from_file_location("kwin_animations", os.path.join(HERE, "kwin-animations.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def qsb_path():
    for c in QSB_CANDIDATES:
        if os.path.isabs(c) and os.access(c, os.X_OK):
            return c
    from shutil import which
    return which("qsb")


def effect_dir(anim, eid):
    for base in anim.DATA_DIRS:
        d = os.path.join(base, "kwin/effects", eid)
        if os.path.isdir(d):
            return d
    return None


def defaults_of(edir):
    out = {}
    try:
        root = ET.parse(os.path.join(edir, "contents/config/main.xml")).getroot()
    except (OSError, ET.ParseError):
        return out
    for entry in root.iter():
        if not entry.tag.endswith("entry"):
            continue
        name = entry.get("name")
        for child in entry:
            if child.tag.endswith("default") and name:
                out[name] = (child.text or "").strip()
    return out


def color_of(text, want):
    """Como o readRGBAConfig/readRGBConfig do Burn-My-Windows: #rrggbb ou #aarrggbb -> [r,g,b(,a)]."""
    text = (text or "").strip()
    m = re.match(r"^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})?$", text, re.I)
    if m:
        c = [int(g, 16) / 255 for g in m.groups() if g is not None]
        rgba = c + [1.0] if len(c) == 3 else [c[1], c[2], c[3], c[0]]
    else:  # KConfig grava cores como "r,g,b[,a]"
        parts = [p for p in re.split(r"[,\s]+", text) if p]
        try:
            c = [float(p) / 255 for p in parts]
        except ValueError:
            c = []
        rgba = (c + [1.0])[:4] if len(c) == 3 else c[:4] if len(c) == 4 else [1.0, 1.0, 1.0, 1.0]
    return rgba[:want]


def num(v, fallback=1.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return fallback


def qml_value(name, typ, raw, duration_s):
    """Expressão QML do valor de um uniform do efeito."""
    if name == "uSeed":
        return "Math.random()" if typ == "float" else "Qt.point(Math.random(), Math.random())"
    if name == "uStartPos":
        # o mesmo sorteio do JS: um ponto numa das bordas
        return ("(function() { const a = Math.random(), b = Math.random();"
                " return a > b ? Qt.point(a, Math.floor(b + 0.5)) : Qt.point(Math.floor(a + 0.5), b) })()")
    if name == "uActorScale":
        return "1.0"
    if typ == "bool":
        return "1.0" if str(raw).strip().lower() in ("true", "1") else "0.0"
    if typ == "float":
        return repr(num(raw))
    if typ in ("vec3", "vec4"):
        c = color_of(raw, 3 if typ == "vec3" else 4)
        return ("Qt.vector3d(%r, %r, %r)" if typ == "vec3" else "Qt.vector4d(%r, %r, %r, %r)") % tuple(c)
    if typ == "vec2":
        return "Qt.point(0.5, 0.5)"
    return "0"


QML_TYPE = {"float": "real", "bool": "real", "vec2": "point", "vec3": "vector3d", "vec4": "vector4d", "int": "real"}


def build_shader(anim, eid, edir, rc, duration_ms):
    shaders = os.path.join(edir, "contents/shaders")
    main = None
    for f in sorted(os.listdir(shaders)):
        if f.endswith(".frag") and not f.endswith("_core.frag"):
            main = os.path.join(shaders, f)
            break
    if not main:
        return None
    src = open(main, encoding="utf-8").read()
    # Corpo = tudo depois do bloco KWIN / KWIN_LEGACY / GNOME do cabeçalho comum.
    gnome = src.find("#else  // GNOME")
    end = src.find("#endif", gnome) if gnome >= 0 else -1
    if end < 0:
        return None
    body = src[src.index("\n", end) + 1:]

    uniforms = []
    def take(m):
        typ, name = m.group(1), m.group(2)
        if name not in STANDARD and (typ, name) not in uniforms:
            uniforms.append((typ, name))
        return ""
    body = re.sub(r"^\s*uniform\s+(\w+)\s+(\w+)\s*;[^\n]*$", take, body, flags=re.M)
    if any(t == "sampler2D" for t, _ in uniforms):
        return None  # textura extra: não suportado (nenhum efeito BMW atual usa)

    members, defines, props = [], [], []
    for typ, name in uniforms:
        prop = name + "F" if typ == "bool" else name
        members.append("  %s %s;\n" % ("float" if typ in ("bool", "int") else typ, prop))
        if typ == "bool":
            defines.append("#define %s (%sF > 0.5)" % (name, name))
        elif typ == "int":
            defines.append("#define %s int(%sF)" % (name, name))
    # uForOpening/uIsFullscreen: bool no Burn-My-Windows original; float no TV do LowPan (2026-11-26, direção por
    # animação no KWin) — o macro segue o tipo declarado no cabeçalho do efeito, senão o qsb recusa `bool < float`.
    std = []
    for name in ("uForOpening", "uIsFullscreen"):
        if re.search(r"^\s*uniform\s+float\s+%s\s*;" % name, src, flags=re.M):
            std.append("#define %s %sF" % (name, name))
        else:
            std.append("#define %s (%sF > 0.5)" % (name, name))
    frag = (QT_HEADER.replace("%STDDEFINES%", "\n".join(std)).replace("%MEMBERS%", "".join(members))
            .replace("%DEFINES%", "\n".join(defines)) + body)

    grp = rc.get("Effect-" + eid, {})
    dflt = defaults_of(edir)
    for typ, name in uniforms:
        key = name[1:]
        raw = grp.get(key, dflt.get(key, ""))
        prop = name + "F" if typ in ("bool", "int") else name
        props.append("    property %s %s: %s" % (QML_TYPE.get(typ, "real"), prop, qml_value(name, typ, raw, duration_ms / 1000)))

    digest = hashlib.sha1((VERSION + frag + "\n".join(props) + str(duration_ms)).encode()).hexdigest()[:12]
    # Uma pasta por versão: o motor QML guarda a listagem das pastas que já leu, e um arquivo novo numa pasta
    # conhecida não é achado ("File name case mismatch").
    folder = os.path.join(CACHE, "%s-%s" % (eid, digest))
    os.makedirs(folder, exist_ok=True)
    base = os.path.join(folder, "Effect")
    qml_path, qsb_out = base + ".qml", base + ".frag.qsb"
    if not (os.path.exists(qml_path) and os.path.exists(qsb_out)):
        qsb = qsb_path()
        if not qsb:
            raise RuntimeError("qsb não encontrado (pacote qt6-shadertools)")
        with open(base + ".frag", "w", encoding="utf-8") as f:
            f.write(frag)
        r = subprocess.run([qsb, "--glsl", "100es,120,150", "--hlsl", "50", "--msl", "12",
                            "-o", qsb_out, base + ".frag"], capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("qsb falhou em %s: %s" % (eid, (r.stderr or r.stdout).strip()[:400]))
        qml = ["import QtQuick", "", "// Gerado por scripts/kwin-open-effect.py (" + eid + ")", "ShaderEffect {",
               "    property var source",
               "    property real uProgress: 0",
               "    property real uForOpeningF: 1",
               "    property real uIsFullscreenF: 0",
               "    property real uDuration: %r" % (duration_ms / 1000),
               "    property point uSize: Qt.point(width, height)"] + props + [
               '    fragmentShader: "file://%s"' % qsb_out, "}", ""]
        with open(qml_path, "w", encoding="utf-8") as f:
            f.write("\n".join(qml))
        # só o último de cada efeito fica (os nomes mudam a cada ajuste)
        import shutil
        for f in os.listdir(CACHE):
            if f.startswith(eid + "-") and f != os.path.basename(folder):
                path = os.path.join(CACHE, f)
                shutil.rmtree(path, ignore_errors=True) if os.path.isdir(path) else os.remove(path)
    return "file://" + qml_path


def main():
    anim = load_animations()
    rc = anim.read_kwinrc()
    effects = anim.installed()
    plugins = rc.get("Plugins", {})
    kcat = anim.CAT_BY_ID["open"][1]
    on = [e for e in effects.values() if e["category"] == kcat and anim.enabled(e, plugins)]
    out = {"kind": "none", "id": "", "duration": 0, "qml": ""}
    if not on:
        return out
    eff = on[0]
    ms = anim.duration_of(eff, rc)[0] or anim.KNOWN_MS.get(eff["id"], anim.UNKNOWN_MS)
    ms = int(round(ms * anim.speed_factor()))
    out.update(id=eff["id"], duration=ms)
    if eff["id"] in NATIVE_KIND:
        out["kind"] = NATIVE_KIND[eff["id"]]
        return out
    edir = effect_dir(anim, eff["id"])
    if edir and os.path.isdir(os.path.join(edir, "contents/shaders")):
        qml = build_shader(anim, eff["id"], edir, rc, ms)
        if qml:
            out.update(kind="shader", qml=qml)
    return out


if __name__ == "__main__":
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as e:  # o shell cai para a animação própria
        print(json.dumps({"kind": "none", "id": "", "duration": 0, "qml": "", "error": str(e)}, ensure_ascii=False))
