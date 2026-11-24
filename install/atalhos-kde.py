#!/usr/bin/env python3
"""LowPan Shells — atalhos pessoais do KWin/plasmashell no perfil (PLANEJAMENTO §22.10, 2ª rodada do teste 3).

  atalhos-kde.py exportar <perfil>   atalhos do KWin e do plasmashell mudados à mão nesta conta → perfis/<perfil>/atalhos-kde.json
  atalhos-kde.py aplicar <perfil>    grava pelo kglobalaccel (guarda os anteriores para o desfazer)
  atalhos-kde.py verificar <perfil>  sai 0 se já estão todos como no perfil
  atalhos-kde.py desfazer            devolve os atalhos de antes do aplicar

Fica de fora o que outros scripts do projeto já cuidam (teclas que o lowpan-shells-tiling e o lowpan-shells-shortcuts
tomam e devolvem), os "activate widget N" do plasmashell (o número do widget muda de máquina para máquina) e os
atalhos de aplicativos. As teclas vão como texto ("Meta+Q") e viram o código do Qt na hora (PySide6).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROJETO = Path(__file__).resolve().parent.parent
PERFIS = PROJETO / "install" / "perfis"
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state"))
ANTERIOR = STATE / "lowpan-shells" / "install" / "anterior" / "atalhos-kde.json"
# ações puladas (efeito ainda não carregado, ex.: o Cubo numa conta nova) ficam marcadas aqui com o nome do perfil; o
# lowpan-atalhos-pendentes.service aplica de novo no próximo login e a marca some quando nada mais for pulado (2026-11-22)
PENDENTE = STATE / "lowpan-shells" / "install" / "atalhos-pendentes"
COMPONENTES = ("kwin", "plasmashell")
# já cuidados por outros scripts do projeto (tomam no install/on e devolvem no remove/off)
DE_OUTROS = {
    "kwin": {"Window Quick Tile Left", "Window Quick Tile Right", "Window Quick Tile Top", "Window Quick Tile Bottom",
             "Window to Next Screen", "Window to Previous Screen", "view_zoom_in", "view_zoom_out",
             "Switch One Desktop to the Left", "Switch One Desktop to the Right",
             "Window One Desktop to the Left", "Window One Desktop to the Right"},
    "plasmashell": {"show-on-mouse-pos", "activate application launcher"},
}
NO_AUTOLOADING = 4
PT = os.environ.get("LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))).startswith("pt")


def t(en, pt):
    return pt if PT else en


def ler_ini(p):
    grupos, g = {}, None
    for linha in open(p, encoding="utf-8"):
        linha = linha.rstrip("\n")
        m = re.match(r"^\[(.+)\]$", linha)
        if m:
            g = grupos.setdefault(m.group(1), {})
            continue
        if g is not None and "=" in linha:
            k, v = linha.split("=", 1)
            g[k] = v
    return grupos


def campos(valor):
    """Separa "atual,padrão,nome" com o escape do KConfig: \\, = vírgula, \\t = TAB, \\\\ = barra."""
    out, atual, i = [], "", 0
    while i < len(valor):
        c = valor[i]
        if c == "\\" and i + 1 < len(valor):
            n = valor[i + 1]
            atual += {"t": "\t", ",": ",", "\\": "\\", "n": "\n"}.get(n, "\\" + n)
            i += 2
            continue
        if c == ",":
            out.append(atual); atual = ""
        else:
            atual += c
        i += 1
    out.append(atual)
    return out


def teclas(texto):
    return [] if texto in ("", "none") else texto.split("\t")


def exportar(nome):
    ini = ler_ini(CONFIG / "kglobalshortcutsrc")
    saida = []
    for comp in COMPONENTES:
        g = ini.get(comp, {})
        comp_nome = g.get("_k_friendly_name", comp)
        for acao, valor in g.items():
            if (acao.startswith("_k_") or acao in DE_OUTROS.get(comp, set()) or acao.startswith("activate widget")
                    or acao.startswith(("Krohnkite", "LowPanTiling", "lowpan"))):   # do script do tiling
                continue
            partes = campos(valor)
            if len(partes) < 3:
                continue
            atual, padrao, acao_nome = partes[0], partes[1], ",".join(partes[2:])
            if atual != padrao:
                saida.append({"comp": comp, "compNome": comp_nome, "acao": acao, "acaoNome": acao_nome,
                              "teclas": teclas(atual), "padrao": teclas(padrao)})
    destino = PERFIS / nome / "atalhos-kde.json"
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text(json.dumps(saida, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for a in saida:
        print(f"  {a['compNome']} › {a['acaoNome']}: {' / '.join(a['teclas']) or t('(none)', '(nenhuma)')}")
    print(t(f"{len(saida)} shortcuts → {destino}", f"{len(saida)} atalhos → {destino}"))


def codigos(lista):
    from PySide6.QtGui import QKeySequence
    out = []
    for s in lista:
        k = QKeySequence(s)
        if k.count() < 1:
            raise SystemExit(t(f"unknown key: {s}", f"tecla desconhecida: {s}"))
        out.append(k[0].toCombined())
    return out


def kga(*args):
    r = subprocess.run(["busctl", "--user", "--json=short", "call", "org.kde.kglobalaccel", "/kglobalaccel",
                        "org.kde.KGlobalAccel", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return json.loads(r.stdout)["data"] if r.stdout.strip() else None


def ident(a):
    return [a["comp"], a["acao"], a["compNome"], a["acaoNome"]]


def atuais(a):
    return [k for k in kga("shortcut", "as", "4", *ident(a))[0] if k]


def gravar(a, cods):
    kga("setShortcut", "asaiu", "4", *ident(a), str(len(cods)), *map(str, cods), str(NO_AUTOLOADING))


def registradas(comp):
    """Ações que existem agora nesta conta: o atalho de um efeito desligado (ex.: o cubo) nem aparece no kglobalaccel."""
    r = subprocess.run(["busctl", "--user", "--json=short", "call", "org.kde.kglobalaccel", f"/component/{comp}",
                        "org.kde.kglobalaccel.Component", "allShortcutInfos"], capture_output=True, text=True)
    try:
        return {i[0] for i in json.loads(r.stdout)["data"][0]}
    except (ValueError, KeyError, IndexError):
        return set()


def existentes(lista):
    reg = {c: registradas(c) for c in {a["comp"] for a in lista}}
    ok, fora = [], []
    for a in lista:
        (ok if a["acao"] in reg[a["comp"]] else fora).append(a)
    return ok, fora


def carregar(nome):
    p = PERFIS / nome / "atalhos-kde.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.is_file() else []


def aplicar(nome):
    lista = carregar(nome)
    if not lista:
        print(t("no personal shortcuts in this profile", "nenhum atalho pessoal neste perfil")); return 0
    antes = json.loads(ANTERIOR.read_text()) if ANTERIOR.is_file() else {}
    lista, fora = existentes(lista)
    for a in fora:
        print(t("  skipped ", "  pulado  ") + f"{a['compNome']} › {a['acaoNome']} " + t("(action not present: effect off?)", "(ação não existe nesta conta: efeito desligado?)"))
    if fora:
        PENDENTE.parent.mkdir(parents=True, exist_ok=True)
        PENDENTE.write_text(nome + "\n")
    elif PENDENTE.exists():
        PENDENTE.unlink()
    plano = []
    for a in lista:
        quero, tenho = codigos(a["teclas"]), atuais(a)
        chave = "|".join(ident(a)[:2])
        antes.setdefault(chave, {"id": ident(a), "teclas": tenho})   # só a 1ª vez: o de antes do LowPan
        plano.append((a, quero, tenho))
    ANTERIOR.parent.mkdir(parents=True, exist_ok=True)
    ANTERIOR.write_text(json.dumps(antes, ensure_ascii=False, indent=1))
    # primeiro as ações que só perdem teclas (liberam, ex.: Meta+Q das Atividades antes do "Fechar janela")
    plano.sort(key=lambda x: 0 if set(x[1]) <= set(x[2]) else 1)
    for a, quero, tenho in plano:
        if set(quero) != set(tenho):
            gravar(a, quero)
            print(f"  ok  {a['compNome']} › {a['acaoNome']}: {' / '.join(a['teclas']) or t('(none)', '(nenhuma)')}")
    import time
    time.sleep(0.5)   # o kglobalaccel grava em seguida, mas deixa um respiro antes de conferir
    return verificar(nome)


def verificar(nome, silencioso=False):
    falta = 0
    lista, _fora = existentes(carregar(nome))   # ação que não existe (efeito desligado) não conta como falta
    for a in lista:
        try:
            if set(codigos(a["teclas"])) != set(atuais(a)):
                falta += 1
                if not silencioso:
                    print(t("  differs ", "  difere  ") + f"{a['compNome']} › {a['acaoNome']} ({' / '.join(a['teclas']) or '—'})")
        except RuntimeError:
            falta += 1
            print(t("  missing ", "  falta   ") + f"{a['compNome']} › {a['acaoNome']}")
    return 1 if falta else 0


def desfazer():
    if not ANTERIOR.is_file():
        return 0
    antes = json.loads(ANTERIOR.read_text())
    # como no aplicar: primeiro quem perde teclas (ex.: o "Fechar janela" solta o Meta+Q antes das Atividades o pegarem)
    def atuais_id(i):
        try:
            return [k for k in kga("shortcut", "as", "4", *i["id"])[0] if k]
        except RuntimeError:
            return []
    itens = sorted(antes.values(), key=lambda i: 0 if set(i["teclas"]) <= set(atuais_id(i)) else 1)
    for item in itens:
        comp, acao, cn, an = item["id"]
        try:
            kga("setShortcut", "asaiu", "4", comp, acao, cn, an, str(len(item["teclas"])), *map(str, item["teclas"]),
                str(NO_AUTOLOADING))
            print(t("  given back ", "  devolvido ") + f"{cn} › {an}")
        except RuntimeError as e:
            print(t("  error ", "  erro ") + f"{cn} › {an}: {e}", file=sys.stderr)
    ANTERIOR.unlink()
    return 0


def pendentes():
    """No login (lowpan-atalhos-pendentes.service): reaplica o perfil marcado, depois que o kglobalaccel e os efeitos
    do KWin subiram. Sem marca, não faz nada."""
    if not PENDENTE.is_file():
        return 0
    nome = PENDENTE.read_text().strip()
    import time
    for _ in range(30):   # até ~30 s pelo componente do KWin no kglobalaccel
        if subprocess.run(["qdbus6", "org.kde.kglobalaccel", "/component/kwin"], capture_output=True).returncode == 0:
            break
        time.sleep(1)
    time.sleep(3)          # os efeitos registram as ações deles logo depois
    return aplicar(nome)


def main(a):
    if len(a) >= 2 and a[0] == "exportar":
        exportar(a[1]); return 0
    if len(a) >= 2 and a[0] == "aplicar":
        return aplicar(a[1])
    if len(a) >= 2 and a[0] == "verificar":
        return verificar(a[1])
    if a and a[0] == "desfazer":
        PENDENTE.unlink(missing_ok=True)
        return desfazer()
    if a and a[0] == "pendentes":
        return pendentes()
    raise SystemExit("uso: atalhos-kde.py exportar <perfil> | aplicar <perfil> | verificar <perfil> | desfazer | pendentes")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
