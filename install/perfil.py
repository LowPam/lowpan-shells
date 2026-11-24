#!/usr/bin/env python3
"""LowPan Shells — perfis de preferências do shell (PLANEJAMENTO §19.3, §22.4 item 4).

  perfil.py exportar <nome>          config.json desta máquina → install/perfis/<nome>/perfil.json
  perfil.py aplicar <nome> [--parar] [--sem-sistema] defaults/config.json + perfil → ~/.config/illogical-impulse/config.json
  (verificar e aplicar aceitam --fixar chave=valor e --ignorar chave: respostas do instalador acima do perfil)
  perfil.py verificar <nome>         sai 0 se o config.json já tem o perfil (ignora o que é da máquina)
  perfil.py comparar [<nome>]        o que o perfil muda em relação ao defaults/config.json, por seção

O perfil guarda só o que difere do defaults/config.json do projeto (assim padrões novos do projeto continuam
valendo). Fica de fora o que é da máquina: nomes de monitor (listas *screenList, papel por monitor, posições de
widget por monitor, valores iguais a um nome de monitor), dispositivo de GPU, senhas/chaves/usuários e caminhos
absolutos. Papéis de parede (imagem/vídeo em /home) são copiados para install/perfis/<nome>/papeis/ — pasta
fora do git — e no perfil viram "@PERFIL@/papeis/<arquivo>"; o aplicar copia para
~/.local/share/lowpan-shells/papeis/ e grava o caminho absoluto.
O config.json só pode ser gravado com o shell parado (a recarga a quente regrava o arquivo, §19.2 linha 11).
"""
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote

PROJETO = Path(__file__).resolve().parent.parent
DEFAULTS = PROJETO / "shell" / "defaults" / "config.json"
PERFIS = PROJETO / "install" / "perfis"
HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CONFIG = CONFIG_DIR / "illogical-impulse" / "config.json"
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state"))
PAPEIS_DESTINO = DATA / "lowpan-shells" / "papeis"
BACKUPS = STATE / "lowpan-shells" / "install" / "backups"
MARCA = "@PERFIL@/"

SEGREDO = re.compile(r"(api_?key|password|passwd|token|secret|user_?id|username)$", re.I)
DA_MAQUINA = {("screenRecord", "hardwareDevice")}       # GPU desta máquina (/dev/dri/renderD128)
POR_MONITOR = {"wallpapersByMonitor", "outputOverrides"}  # listas de itens ligados a um monitor
MIDIA = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".jxl", ".mp4", ".webm", ".mkv", ".mov"}
PT = os.environ.get("LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))).startswith("pt")


# --fixar chave=valor / --ignorar chave (install.sh): respostas do instalador que valem mais que o perfil
# (lowpan.captureTool, lowpan.tiling — a captura e o tiling gravam a própria escolha no config.json; sem isso, perfil
# e resposta se desfariam um ao outro a cada execução)
FIXAR, IGNORAR = {}, set()


def opcoes(a):
    resto, i = [], 0
    while i < len(a):
        if a[i] in ("--fixar", "--ignorar") and i + 1 < len(a):
            if a[i] == "--fixar":
                k, _, v = a[i + 1].partition("=")
                try:
                    FIXAR[k] = json.loads(v)
                except ValueError:
                    FIXAR[k] = v
            else:
                IGNORAR.add(a[i + 1])
            i += 2
        else:
            resto.append(a[i]); i += 1
    return resto


def pegar(o, chave):
    for k in chave.split("."):
        if not isinstance(o, dict) or k not in o:
            return None, False
        o = o[k]
    return o, True


def pôr(o, chave, v):
    *ks, ult = chave.split(".")
    for k in ks:
        o = o.setdefault(k, {})
    o[ult] = copy.deepcopy(v)


def t(en, pt):
    return pt if PT else en


def ler(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def gravar(p, dados):
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, p)


def monitores(cfg):
    """Nomes de monitor: os do kscreen-doctor + os que aparecem nas listas *screenList do próprio config."""
    nomes = set()
    try:
        out = subprocess.run(["kscreen-doctor", "-j"], capture_output=True, text=True, timeout=10).stdout
        nomes |= {o["name"] for o in json.loads(out).get("outputs", [])}
    except Exception:
        pass

    def walk(o, k=""):
        if isinstance(o, dict):
            for kk, v in o.items():
                walk(v, kk)
        elif isinstance(o, list):
            if k.endswith("screenList"):
                nomes.update(x for x in o if isinstance(x, str))
            for x in o:
                walk(x)
    walk(cfg)
    return nomes


def diferenca(u, d):
    """Só o que em u difere de d (dicionários comparados por chave; o resto, por valor)."""
    if isinstance(u, dict) and isinstance(d, dict):
        out = {}
        for k, v in u.items():
            if k not in d:
                out[k] = v
            else:
                sub = diferenca(v, d[k])
                if sub is not None:
                    out[k] = sub
        return out or None
    return None if u == d else u


def mesclar(base, por_cima):
    out = copy.deepcopy(base)
    for k, v in por_cima.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = mesclar(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def limpar(o, caminho, nomes, papeis, relatorio):
    """Tira o que é da máquina. Devolve (valor, manter?)."""
    chave = caminho[-1] if caminho else ""
    rotulo = ".".join(caminho)
    if tuple(caminho[-2:]) in DA_MAQUINA:
        relatorio.append(("máquina", rotulo)); return None, False
    if SEGREDO.search(chave):
        relatorio.append(("segredo", rotulo)); return None, False
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            nv, ok = limpar(v, caminho + [k], nomes, papeis, relatorio)
            if ok:
                out[k] = nv
        return out, bool(out)
    if isinstance(o, list):
        if chave.endswith("screenList") and o:
            relatorio.append(("monitor", rotulo)); return [], True
        if chave in POR_MONITOR and o:
            relatorio.append(("monitor", rotulo)); return [], True
        return o, True
    if isinstance(o, str):
        if o in nomes:
            relatorio.append(("monitor", rotulo)); return "", True
        p = o[7:] if o.startswith("file://") else o
        if p.startswith(str(HOME) + "/") or p.startswith("/mnt/") or p.startswith("/run/media/"):
            arq = Path(p)
            if arq.suffix.lower() in MIDIA and arq.is_file():
                papeis[arq.name] = arq
                relatorio.append(("papel", f"{rotulo} → papeis/{arq.name}"))
                return MARCA + "papeis/" + arq.name, True
            relatorio.append(("caminho", f"{rotulo} = {o}")); return None, False
    return o, True


def exportar(nome):
    cfg, base = ler(CONFIG), ler(DEFAULTS)
    nomes = monitores(cfg)
    dif = diferenca(cfg, base) or {}
    papeis, relatorio = {}, []
    perfil, _ = limpar(dif, [], nomes, papeis, relatorio)
    pasta = PERFIS / nome
    gravar(pasta / "perfil.json", {
        "_lowpan": {"nome": nome, "exportado": time.strftime("%Y-%m-%d %H:%M"),
                    "base": "shell/defaults/config.json",
                    "nota": "só o que difere do defaults; sem monitores, segredos e caminhos da máquina"},
        **perfil})
    if papeis:
        (pasta / "papeis").mkdir(parents=True, exist_ok=True)
        for n, arq in papeis.items():
            shutil.copy2(arq, pasta / "papeis" / n)
    for tipo, txt in relatorio:
        print(f"{t('removed', 'tirado') if tipo != 'papel' else t('copied', 'copiado')} [{tipo}] {txt}")
    print(t(f"profile: {pasta / 'perfil.json'} ({len(json.dumps(perfil))} bytes, {len(papeis)} wallpaper(s))",
            f"perfil: {pasta / 'perfil.json'} ({len(json.dumps(perfil))} bytes, {len(papeis)} papel(éis) de parede)"))


def shell_ativo():
    r = subprocess.run(["systemctl", "--user", "is-active", "lowpan-shells.service"], capture_output=True, text=True)
    return r.stdout.strip() == "active"


def resolver_papeis(o, pasta, faltando):
    if isinstance(o, dict):
        return {k: resolver_papeis(v, pasta, faltando) for k, v in o.items()}
    if isinstance(o, list):
        return [resolver_papeis(x, pasta, faltando) for x in o]
    if isinstance(o, str) and o.startswith(MARCA):
        rel = o[len(MARCA):]
        orig = pasta / rel
        if not orig.is_file():
            faltando.append(rel)
            return ""
        PAPEIS_DESTINO.mkdir(parents=True, exist_ok=True)
        dest = PAPEIS_DESTINO / orig.name
        if not dest.exists():
            shutil.copy2(orig, dest)
        return str(dest)
    return o


def papel_do_plasma():
    """O papel de parede que a pessoa tem no Plasma (4ª rodada do teste: o LowPan usa o dela, não o do perfil).
    Primeiro contêiner do plasmashell com org.kde.image e arquivo existente; senão None (fica o do perfil)."""
    def resolver(v):
        v = v[len("file://"):] if v.startswith("file://") else v
        arq = Path(unquote(v))
        if not arq.is_absolute():   # só o nome do pacote (ex.: "Next")
            arq = Path("/usr/share/wallpapers") / arq
        if arq.is_file() and arq.suffix.lower() in MIDIA:
            return str(arq)
        if arq.is_dir():   # pacote de papel de parede do KDE: contents/images/<maior>
            imgs = sorted((f for f in (arq / "contents" / "images").glob("*") if f.suffix.lower() in MIDIA),
                          key=lambda f: f.stat().st_size)
            if imgs:
                return str(imgs[-1])
        return None

    p = CONFIG_DIR / "plasma-org.kde.plasma.desktop-appletsrc"
    try:
        linhas = p.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None   # sem Plasma nesta conta: fica o do perfil
    no_grupo = False
    for linha in linhas:
        if linha.startswith("["):
            no_grupo = linha.endswith("[Wallpaper][org.kde.image][General]")
        elif no_grupo and linha.startswith("Image="):
            r = resolver(linha[len("Image="):].strip())
            if r:
                return r
    # conta que nunca trocou o papel: o Plasma mostra o padrão do tema (Breeze → "Next")
    return resolver("Next")


def aplicar(nome, parar, sem_sistema=False):
    pasta = PERFIS / nome
    perfil = ler(pasta / "perfil.json")
    perfil.pop("_lowpan", None)
    ativo = False if sem_sistema else shell_ativo()  # --sem-sistema: testes numa HOME falsa (§22.7)
    if ativo and not parar:
        sys.exit(t("the shell is running: use --parar (stops, writes, starts again)",
                   "o shell está rodando: use --parar (para, grava e sobe de novo)"))
    faltando = []
    novo = resolver_papeis(mesclar(ler(DEFAULTS), perfil), pasta, faltando)
    atual = ler(CONFIG) if CONFIG.exists() else None
    if atual is not None:
        novo = manter_da_maquina(novo, atual)
    for k in IGNORAR:
        v, tem = pegar(atual, k) if atual is not None else (None, False)
        if tem:
            pôr(novo, k, v)
    papel = papel_do_plasma()
    if papel and "background.wallpaperPath" not in IGNORAR and "background.wallpaperPath" not in FIXAR:
        pôr(novo, "background.wallpaperPath", papel)
        print(t(f"wallpaper: the one from Plasma ({papel})", f"papel de parede: o do Plasma ({papel})"))
    for k, v in FIXAR.items():
        pôr(novo, k, v)
    if ativo:
        subprocess.run(["systemctl", "--user", "stop", "lowpan-shells.service"], check=True)
    try:
        if CONFIG.exists():
            bk = BACKUPS / time.strftime("%Y%m%d-%H%M%S") / "config.json"
            bk.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(CONFIG, bk)
            print(t(f"backup: {bk}", f"backup: {bk}"))
        gravar(CONFIG, novo)
    finally:
        if ativo:
            subprocess.run(["systemctl", "--user", "start", "lowpan-shells.service"])
    for rel in faltando:
        print(t(f"missing {rel}: the default wallpaper stays", f"falta {rel}: fica o papel de parede padrão"))
    print(t(f"applied: {nome} → {CONFIG}", f"aplicado: {nome} → {CONFIG}"))


def e_da_maquina(caminho):
    ch = caminho[-1] if caminho else ""
    return (ch.endswith("screenList") or ch in POR_MONITOR or tuple(caminho[-2:]) in DA_MAQUINA
            or bool(SEGREDO.search(ch)))


def manter_da_maquina(novo, atual, caminho=()):
    """No aplicar: o que é da máquina (monitores, GPU, segredos) fica como está no config.json existente."""
    if not isinstance(atual, dict) or not isinstance(novo, dict):
        return novo
    for k, v in atual.items():
        c = caminho + (k,)
        if e_da_maquina(list(c)):
            novo[k] = copy.deepcopy(v)
        elif isinstance(v, dict) and isinstance(novo.get(k), dict):
            manter_da_maquina(novo[k], v, c)
    return novo


def verificar(nome):
    """Sai 0 se o config.json já tem todos os valores do perfil (fora os da máquina); senão lista e sai 1."""
    perfil = ler(PERFIS / nome / "perfil.json"); perfil.pop("_lowpan", None)
    if not CONFIG.exists():
        print(t("no config.json yet", "ainda não há config.json")); return 1
    cfg = ler(CONFIG)
    dif = []

    def walk(o, c):
        if e_da_maquina(c):
            return
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, c + [k])
            return
        a = cfg
        for k in c:
            a = a.get(k, "(sem chave)") if isinstance(a, dict) else "(sem chave)"
        if isinstance(o, str) and o.startswith(MARCA) and isinstance(a, str):
            # papel de parede: mesmo arquivo em outro lugar, ou o do Plasma da pessoa (que vale mais que o do perfil)
            if Path(a).name == Path(o).name or (a and Path(a).is_file()):
                return
        if a != o:
            dif.append(".".join(c))
    for k in IGNORAR | set(FIXAR):
        p = perfil
        *ks, ult = k.split(".")
        for kk in ks:
            p = p.get(kk, {}) if isinstance(p, dict) else {}
        if isinstance(p, dict):
            p.pop(ult, None)
    walk(perfil, [])
    for k, v in FIXAR.items():
        a, tem = pegar(cfg, k)
        if not tem or a != v:
            dif.append(f"{k} ({t('answer', 'resposta')}: {json.dumps(v)})")
    for d in dif[:15]:
        print(t("differs ", "difere  ") + d)
    if len(dif) > 15:
        print(f"… +{len(dif) - 15}")
    return 1 if dif else 0


def comparar(nome):
    base = ler(DEFAULTS)
    if nome:
        perfil = ler(PERFIS / nome / "perfil.json"); perfil.pop("_lowpan", None)
    else:
        perfil = diferenca(ler(CONFIG), base) or {}

    def folhas(o, p=()):
        if isinstance(o, dict):
            for k, v in o.items():
                yield from folhas(v, p + (k,))
        else:
            yield p, o

    def valor_base(p):
        o = base
        for k in p:
            if not isinstance(o, dict) or k not in o:
                return "(sem chave)"
            o = o[k]
        return o

    secao = None
    for p, v in sorted(folhas(perfil), key=lambda x: x[0]):
        if p[0] != secao:
            secao = p[0]
            print(f"\n## {secao}")
        b = valor_base(p)
        fmt = lambda x: (json.dumps(x, ensure_ascii=False) if not isinstance(x, str) else repr(x))[:70]
        print(f"  {'.'.join(p[1:]) or p[0]}: {fmt(b)} → {fmt(v)}")


def main(a):
    a = opcoes(a)
    if len(a) >= 2 and a[0] == "exportar":
        exportar(a[1])
    elif len(a) >= 2 and a[0] == "aplicar":
        aplicar(a[1], "--parar" in a, "--sem-sistema" in a)
    elif len(a) >= 2 and a[0] == "verificar":
        sys.exit(verificar(a[1]))
    elif a and a[0] == "comparar":
        comparar(a[1] if len(a) > 1 else None)
    else:
        sys.exit("uso: perfil.py exportar <nome> | aplicar <nome> [--parar] [--sem-sistema] | verificar <nome> | comparar [<nome>]")


if __name__ == "__main__":
    main(sys.argv[1:])
