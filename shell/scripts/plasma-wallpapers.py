#!/usr/bin/env python3
"""LowPan Shells: os papéis de parede do KDE Plasma para a galeria do shell (fonte "Plasma").

  plasma-wallpapers.py LARGURA ALTURA [dark]   JSON: [{"path", "name", "time"}]

Lê as pastas de papel de parede do Plasma (~/.local/share/wallpapers primeiro, depois as de XDG_DATA_DIRS, como
/usr/share/wallpapers). Cada pacote (metadata.json / metadata.desktop + contents/images) vira uma entrada com a
imagem de resolução mais próxima da tela, na proporção mais parecida (contents/images_dark com "dark", se existir).
Imagens soltas nessas pastas também entram. O nome vem do metadata, traduzido pelo idioma do sistema.
"""
import json
import locale
import os
import re
import sys

EXTS = (".png", ".jpg", ".jpeg", ".webp", ".avif", ".jxl", ".bmp", ".svg")


def data_dirs():
    home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    rest = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    out = []
    for d in [home] + rest:
        p = os.path.join(d, "wallpapers")
        if p not in out and os.path.isdir(p):
            out.append(p)
    return out


def langs():
    lang = (os.environ.get("LANGUAGE") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG")
            or (locale.getlocale()[0] or "")).split(":")[0].split(".")[0]
    return [lang, lang.split("_")[0]] if lang else []


def name_of(pkg, fallback):
    wanted = langs()
    meta = os.path.join(pkg, "metadata.json")
    if os.path.exists(meta):
        try:
            kp = json.load(open(meta, encoding="utf-8")).get("KPlugin", {})
            for l in wanted:
                if kp.get("Name[%s]" % l):
                    return kp["Name[%s]" % l]
            if kp.get("Name"):
                return kp["Name"]
        except (OSError, ValueError):
            pass
    meta = os.path.join(pkg, "metadata.desktop")
    if os.path.exists(meta):
        keys = {}
        try:
            for line in open(meta, encoding="utf-8", errors="replace"):
                if "=" in line:
                    k, v = line.split("=", 1)
                    keys[k.strip()] = v.strip()
        except OSError:
            pass
        for l in wanted:
            if keys.get("Name[%s]" % l):
                return keys["Name[%s]" % l]
        if keys.get("Name"):
            return keys["Name"]
    return fallback


def best_image(folder, width, height):
    try:
        files = [f for f in os.listdir(folder) if f.lower().endswith(EXTS)]
    except OSError:
        return None
    if not files:
        return None
    aspect = width / max(1, height)

    def score(f):
        m = re.match(r"^(\d+)x(\d+)", f)
        if not m:
            return (9, 0)
        w, h = int(m.group(1)), int(m.group(2))
        # proporção mais parecida primeiro; depois a menor que cobre a tela (senão a maior)
        diff = abs(w / max(1, h) - aspect)
        covers = w >= width and h >= height
        return (round(diff, 2), (w * h) if covers else 10 ** 12 - w * h)
    files.sort(key=score)
    return os.path.join(folder, files[0])


def main(argv):
    width = int(argv[0]) if len(argv) > 0 else 1920
    height = int(argv[1]) if len(argv) > 1 else 1080
    dark = len(argv) > 2 and argv[2] == "dark"
    seen, out = set(), []
    for base in data_dirs():
        for entry in sorted(os.listdir(base)):
            if entry.startswith(".") or entry in seen:
                continue
            path = os.path.join(base, entry)
            if os.path.isdir(path):
                images = os.path.join(path, "contents", "images")
                dark_images = os.path.join(path, "contents", "images_dark")
                img = None
                if dark and os.path.isdir(dark_images):
                    img = best_image(dark_images, width, height)
                if not img and os.path.isdir(images):
                    img = best_image(images, width, height)
                if not img:
                    continue
                seen.add(entry)
                out.append({"path": img, "name": name_of(path, entry), "time": int(os.path.getmtime(img) * 1000)})
            elif entry.lower().endswith(EXTS):
                seen.add(entry)
                out.append({"path": path, "name": os.path.splitext(entry)[0], "time": int(os.path.getmtime(path) * 1000)})
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
