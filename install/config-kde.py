#!/usr/bin/env python3
"""LowPan Shells — configurações pessoais do KDE no perfil (PLANEJAMENTO §22.10, 3ª rodada do teste 3).

  config-kde.py exportar <perfil>    lê desta conta o que está em ESCOLHA → perfis/<perfil>/config-kde.json + arquivos/
  config-kde.py aplicar <perfil>     grava (chaves pelo kwriteconfig6, arquivos copiados) e guarda o anterior
  config-kde.py verificar <perfil>   sai 0 se já está tudo como no perfil
  config-kde.py desfazer             devolve o que havia antes do aplicar

Só o que é gosto do dono e vale em outra máquina: cantos/contorno/sombra das janelas, efeitos ligados e as opções
deles, áreas de trabalho, foco, luz noturna, Alt+Tab, sombra do Breeze, botões das janelas GTK, o Kate, o kitty. Fica de fora
o que outros passos do instalador ou scripts do projeto já cuidam (tiling, efeito de abrir/fechar, Exclusions, espera
do foco, alvos do Achatar2 — esses são gravados pelo shell com a posição dos ícones da dock desta tela).
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

PROJETO = Path(__file__).resolve().parent.parent
PERFIS = PROJETO / "install" / "perfis"
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state"))
ANTERIOR = STATE / "lowpan-shells" / "install" / "anterior" / "config-kde"
SEM_SISTEMA = os.environ.get("LOWPAN_SEM_SISTEMA") == "1"   # testes numa HOME falsa: sem gsettings nem KWin reais
PT = os.environ.get("LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))).startswith("pt")

# arquivo → {grupo: "*" (todas as chaves) | [chaves]}; grupo terminando em "*" = todos os grupos com esse começo
ESCOLHA = {
    "kwinrc": {
        "LowPan-Round-Corners": "*",   # nosso Rounded Corners (o do LowPan); o [Round-Corners] é o da pessoa
        "Plugins": "*",
        "Effect-*": "*",
        "Desktops": ["Number", "Rows"],
        "Windows": ["FocusPolicy", "RollOverDesktops"],
        "Compositing": ["AllowTearing"],
        "NightColor": "*",
        "TabBox": ["LayoutName"],
    },
    "breezerc": {"*": "*"},
    # gtk-decoration-layout / button-layout (botões das janelas GTK) saíram em 2026-11-22: o gtkconfig do kded copia os
    # botões do KDE para o GTK, e eles agora dependem do tiling de cada ambiente (LowPan sem botões, Plasma com) — o
    # perfil fixava ":" e o Nautilus no Plasma ficava sem botões
    "katerc": {"General": "*", "KTextEditor Document": "*", "KTextEditor Editor": "*", "KTextEditor Renderer": "*",
               "KTextEditor View": "*", "Konsole": "*", "filetree": "*", "lspclient": "*"},
    "katevirc": {"*": "*"},
    # bloqueio da tela (2026-11-23): o LowPan não bloqueia sozinho nem ao acordar (§21.71); sem isto, numa conta nova o
    # KDE bloqueia após 5 min ociosos com a tela de bloqueio padrão (visto na VM da E8)
    "kscreenlockerrc": {"Daemon": ["Autolock", "LockOnResume", "Timeout"]},
}
# chaves que NÃO vão (cuidadas por outros passos ou desta máquina)
FORA = {
    ("kwinrc", "LowPan-Round-Corners", "Exclusions"),     # a_klista nos módulos 40/70
    ("kwinrc", "Effect-kwin4_effect_squash2", "Targets"),  # posições dos ícones da dock nesta tela (o shell grava)
    ("katerc", "General", "PinnedDocuments"),
    # contorno e cantos do Breeze (2026-11-24, teste como usuário): no LowPan quem desenha cantos/contorno é o nosso
    # Rounded Corners, e algo no login regrava estas chaves (false/OutlineOff/false, igual no desktop e na VM) → o
    # verificar acusava "a fazer" logo depois de instalar (desde a 8ª rodada). OutlineIntensity nem existe no Breeze 6.8.
    ("breezerc", "Common", "OutlineEnabled"),
    ("breezerc", "Common", "OutlineIntensity"),
    ("breezerc", "Common", "RoundedCorners"),
}
PLUGINS_FORA = {"lowpan-tilingEnabled", "krohnkiteEnabled", "center-new-windowsEnabled", "lowpan_drag_insetEnabled",
                "kwin4_effect_geometry_changeEnabled", "kwin4_effect_tvEnabled",   # tiling e 40-kwin
                "kwin4_effect_shapecornersEnabled", "kwin4_effect_lowpancornersEnabled"}


def _plugins_de_animacao():
    """Efeitos de abrir/fechar e de minimizar: têm dono próprio (40-kwin liga o TV guardando o anterior; as animações
    do perfil cuidam do minimizar). No config-kde eles brigavam com esses passos: o 40-kwin guardava como "anterior" o
    que o perfil já tinha gravado (scale/fade/glide desligados) e a remoção devolvia isso (VM, 2026-11-23)."""
    ids = {"scale", "fade", "glide", "magiclamp", "squash", "kwin4_effect_tv", "kwin4_effect_squash2"}
    try:
        r = subprocess.run([sys.executable, "-I", str(PROJETO / "shell" / "scripts" / "kwin-animations.py"), "state"],
                           capture_output=True, text=True, timeout=20)
        for c in json.loads(r.stdout).get("categories", []):
            if c.get("id") in ("open", "minimize"):
                ids.update(str(e.get("id")) for e in c.get("choices", []) if e.get("id"))
    except Exception:
        pass
    return {i + "Enabled" for i in ids}


PLUGINS_FORA |= _plugins_de_animacao()  # cantos: lowpan-cantos-ambiente
# arquivos inteiros (relativos a ~/.config ou ~/.local/share com o prefixo "data:")
ARQUIVOS = ["data:org.kde.syntax-highlighting/themes", "kate/externaltools", "kate/lspclient",
            "kitty"]   # kitty: o terminal do menu (4ª rodada do teste: a configuração não vinha)
# só criados se a conta não tiver (5ª rodada: o terminal do kitty abria no assistente do zsh, sem prompt nem
# fastfetch; o Kate com as barras laterais). Depois são da pessoa — o shell regrava a paleta do starship, o Kate a
# sessão —, então a verificação só confere que existem e o desfazer só apaga o que ficou igual ao do perfil.
# "home:" = relativo à pasta pessoal; o .zshrc do perfil é escrito à mão (perfis/<nome>/zshrc), não exportado.
# Exceção: um ~/.zshrc criado pelo instalador (1ª linha = MARCA_ZSHRC) é MANTIDO igual ao do projeto — a correção da
# seta para cima (atuin) não chegava à VM que já tinha o antigo (2026-11-22). Ajustes da pessoa: ~/.zshrc.local.
MARCA_ZSHRC = "# ~/.zshrc do LowPan Shells"
UMA_VEZ = ["home:.zshrc", "starship.toml", "fastfetch", "atuin/config.toml", "data:kate/anonymous.katesession"]
# da sessão do Kate só vão os plugins e o layout da janela (barras laterais), não arquivos abertos nem recentes
SESSAO_KATE = ("Kate Plugins", "MainWindow0", "MainWindow0 Settings")
GSETTINGS = [("org.gnome.desktop.privacy", "remember-recent-files")]   # Nautilus sem "Recentes" (§19.2 linha 33)


def t(en, pt):
    return pt if PT else en


def ler_ini(p):
    grupos, g = {}, None
    try:
        linhas = open(p, encoding="utf-8").read().splitlines()
    except OSError:
        return {}
    for linha in linhas:
        if linha.startswith("[") and linha.endswith("]"):
            g = grupos.setdefault(linha[1:-1], {})
        elif g is not None and "=" in linha and not linha.startswith("#"):
            k, v = linha.split("=", 1)
            g[k] = v
    return grupos


def escolhidos(arq, ini):
    regras = ESCOLHA[arq]
    for grupo, chaves in ini.items():
        if grupo.startswith("$Version") or "][" in grupo:
            continue
        regra = None
        for padrao, r in regras.items():
            if padrao == grupo or padrao == "*" or (padrao.endswith("*") and grupo.startswith(padrao[:-1])):
                regra = r
                break
        if regra is None:
            continue
        for k in chaves:
            if "[" in k:   # chave com marcação de idioma/expansão (Nome[pt_BR], chave[$e]): fica de fora
                continue
            if (regra == "*" or k in regra) and (arq, grupo, k) not in FORA \
                    and not (arq == "kwinrc" and grupo == "Plugins" and k in PLUGINS_FORA):
                # o valor pelo kreadconfig6: no arquivo ele vem com o escape do KConfig (\\\\ = barra) e o
                # kwriteconfig6 escaparia de novo (achado no "Map Leader=\\\\" do katevirc)
                yield grupo, k, kler(arq, grupo, k)


def caminho(rel):
    if rel.startswith("home:"):
        return HOME / rel[5:]
    return DATA / rel[5:] if rel.startswith("data:") else CONFIG / rel


def fonte(rel, nome):
    """Onde o arquivo está no perfil."""
    if rel == "home:.zshrc":
        return PERFIS / nome / "zshrc"
    return PERFIS / nome / "arquivos-kde" / rel.replace("data:", "data/").replace("home:", "home/")


def zshrc_nosso(rel):
    """~/.zshrc existe e foi criado pelo instalador (1ª linha com a marca)."""
    if rel != "home:.zshrc":
        return False
    try:
        with open(caminho(rel), encoding="utf-8", errors="replace") as f:
            return f.readline().startswith(MARCA_ZSHRC)
    except OSError:
        return False


def sessao_kate(src, dst):
    grupos, g = [], None
    for linha in src.read_text(encoding="utf-8", errors="replace").splitlines():
        if linha.startswith("[") and linha.endswith("]"):
            g = linha[1:-1] if linha[1:-1] in SESSAO_KATE else None
            if g:
                grupos.append([linha])
        elif g and linha.strip() and not linha.startswith("Kate-MDI-H-Splitter"):
            grupos[-1].append(linha)
    dst.write_text("\n\n".join("\n".join(x) for x in grupos) + "\n", encoding="utf-8")


def exportar(nome):
    pasta = PERFIS / nome
    dados = {"ini": {}, "arquivos": [], "gsettings": {}}
    for arq in ESCOLHA:
        itens = list(escolhidos(arq, ler_ini(CONFIG / arq)))
        if itens:
            dados["ini"][arq] = [[g, k, v] for g, k, v in itens]
    destino = pasta / "arquivos-kde"
    if destino.exists():
        shutil.rmtree(destino)
    for rel in ARQUIVOS:
        src = caminho(rel)
        if src.exists():
            dst = destino / rel.replace("data:", "data/")
            dst.parent.mkdir(parents=True, exist_ok=True)
            (shutil.copytree if src.is_dir() else shutil.copy2)(src, dst)
            dados["arquivos"].append(rel)
    dados["uma_vez"] = []
    for rel in UMA_VEZ:
        src = caminho(rel)
        if rel == "home:.zshrc":
            if fonte(rel, nome).is_file():
                dados["uma_vez"].append(rel)
            continue
        if not src.exists():
            continue
        dst = fonte(rel, nome)
        dst.parent.mkdir(parents=True, exist_ok=True)
        if rel == "data:kate/anonymous.katesession":
            sessao_kate(src, dst)
        else:
            (shutil.copytree if src.is_dir() else shutil.copy2)(src, dst, **({"ignore": shutil.ignore_patterns("*_old", "*.bak*")} if src.is_dir() else {}))
        dados["uma_vez"].append(rel)
    for schema, key in GSETTINGS:
        r = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True)
        if r.returncode == 0:
            dados["gsettings"][f"{schema} {key}"] = r.stdout.strip()
    (pasta / "config-kde.json").write_text(json.dumps(dados, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    n = sum(len(v) for v in dados["ini"].values())
    for arq, itens in dados["ini"].items():
        print(f"  {arq}: {len(itens)}")
    print(t(f"{n} keys, {len(dados['arquivos'])} files, {len(dados['uma_vez'])} only-if-missing, {len(dados['gsettings'])} gsettings → {pasta}",
            f"{n} chaves, {len(dados['arquivos'])} arquivos, {len(dados['uma_vez'])} só se faltar, {len(dados['gsettings'])} gsettings → {pasta}"))


def carregar(nome):
    p = PERFIS / nome / "config-kde.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.is_file() else None


def kler(arq, g, k):
    # só o arquivo do usuário (caminho absoluto: sem a cascata do /etc/xdg e do kdedefaults)
    r = subprocess.run(["kreadconfig6", "--file", str(CONFIG / arq), "--group", g, "--key", k], capture_output=True, text=True)
    return r.stdout.rstrip("\n")


def kler_efetivo(arq, g, k):
    r = subprocess.run(["kreadconfig6", "--file", arq, "--group", g, "--key", k], capture_output=True, text=True)
    return r.stdout.rstrip("\n")


def igual_ini(arq, g, k, v):
    return kler(arq, g, k) == v or kler_efetivo(arq, g, k) == v


def arquivo_igual(rel, nome):
    """Cada arquivo do perfil igual no destino; arquivos a mais no destino não contam (o Kate cria os dele em
    kate/externaltools — 5ª rodada do teste: "difere kate/externaltools")."""
    src, dst = fonte(rel, nome), caminho(rel)
    if src.is_file():
        return dst.is_file() and src.read_bytes() == dst.read_bytes()
    for f in src.rglob("*"):
        if f.is_file():
            g = dst / f.relative_to(src)
            if not g.is_file() or f.read_bytes() != g.read_bytes():
                return False
    return dst.is_dir()


def verificar(nome, mostrar=True, saida=sys.stdout):
    d = carregar(nome)
    if not d:
        return 0
    falta = []
    for arq, itens in d["ini"].items():
        falta += [f"{arq} [{g}] {k}" for g, k, v in itens if not igual_ini(arq, g, k, v)]
    falta += [rel for rel in d["arquivos"] if not arquivo_igual(rel, nome)]
    falta += [rel for rel in d.get("uma_vez", []) if not caminho(rel).exists()
              or (zshrc_nosso(rel) and not arquivo_igual(rel, nome))]
    for chave, v in ({} if SEM_SISTEMA else d["gsettings"]).items():
        r = subprocess.run(["gsettings", "get", *chave.split(" ")], capture_output=True, text=True)
        if r.stdout.strip() != v:
            falta.append("gsettings " + chave)
    if mostrar:
        for f in falta[:20]:
            print(t("  differs ", "  difere  ") + f, file=saida)
        if len(falta) > 20:
            print(f"  … +{len(falta) - 20}", file=saida)
    return 1 if falta else 0


def aplicar(nome):
    d = carregar(nome)
    if not d:
        print(t("nothing in this profile", "nada neste perfil")); return 0
    ANTERIOR.mkdir(parents=True, exist_ok=True)
    reg = ANTERIOR / "registro.json"
    antes = json.loads(reg.read_text()) if reg.is_file() else {"ini": {}, "arquivos": {}, "gsettings": {}}
    antes["perfil"] = nome
    n = 0
    for arq, itens in d["ini"].items():
        existia = (CONFIG / arq).exists()
        for g, k, v in itens:
            if igual_ini(arq, g, k, v):
                continue
            chave = f"{arq}|{g}|{k}"
            antes["ini"].setdefault(chave, {"valor": kler(arq, g, k), "arquivo_novo": not existia})
            (CONFIG / arq).parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["kwriteconfig6", "--file", str(CONFIG / arq), "--group", g, "--key", k, v], check=True)
            n += 1
    for rel in d["arquivos"]:
        if arquivo_igual(rel, nome):
            continue
        dst = caminho(rel)
        if rel not in antes["arquivos"]:
            if dst.exists():
                bk = ANTERIOR / "arquivos" / rel.replace("data:", "data/")
                bk.parent.mkdir(parents=True, exist_ok=True)
                (shutil.copytree if dst.is_dir() else shutil.copy2)(dst, bk)
                antes["arquivos"][rel] = str(bk)
            else:
                antes["arquivos"][rel] = None
        src = fonte(rel, nome)
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            shutil.copytree(src, dst, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dst)
        n += 1
    antes.setdefault("uma_vez", [])
    for rel in d.get("uma_vez", []):
        dst = caminho(rel)
        if zshrc_nosso(rel) and not arquivo_igual(rel, nome):
            shutil.copy2(fonte(rel, nome), dst)   # o nosso, de uma versão antiga do projeto: troca
            n += 1
            continue
        if dst.exists():
            continue
        src = fonte(rel, nome)
        dst.parent.mkdir(parents=True, exist_ok=True)
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, dst)
        if rel not in antes["uma_vez"]:
            antes["uma_vez"].append(rel)
        n += 1
    for chave, v in ({} if SEM_SISTEMA else d["gsettings"]).items():
        schema, key = chave.split(" ")
        atual = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True).stdout.strip()
        if atual != v:
            # chave que a pessoa nunca definiu (vale o padrão): None → o desfazer usa "gsettings reset" (gravar o valor
            # padrão explicitamente deixava a chave no dconf; notebook, 2026-11-22)
            definida = subprocess.run(["dconf", "read", "/" + schema.replace(".", "/") + "/" + key],
                                      capture_output=True, text=True).stdout.strip()
            antes["gsettings"].setdefault(chave, atual if definida else None)
            subprocess.run(["gsettings", "set", schema, key, v])
            n += 1
    reg.write_text(json.dumps(antes, ensure_ascii=False, indent=1))
    # o KWin liga/desliga os efeitos e relê os cantos no reconfigure (sem novo login)
    if not SEM_SISTEMA:
        subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
        regravar_depois(d)
    print(t(f"  {n} changed", f"  {n} mudado(s)"))
    # o que ficou diferente vai para a saída de erro (o instalador descarta a normal): aparece no registro
    return verificar(nome, saida=sys.stderr)


def regravar_depois(d):
    """Depois do reconfigure alguém pode regravar o que acabou de ser gravado — o gtkconfig do kded refaz o
    gtk-decoration-layout (e o button-layout do gsettings) com os botões do kwinrc. Espera, grava de novo o que mudou
    e diz na saída de erro quem foi regravado (4ª rodada: a verificação falhava logo depois de aplicar)."""
    time.sleep(2)
    de_novo = []
    for arq, itens in d["ini"].items():
        for g, k, v in itens:
            if not igual_ini(arq, g, k, v):
                subprocess.run(["kwriteconfig6", "--file", str(CONFIG / arq), "--group", g, "--key", k, v])
                de_novo.append(f"{arq} [{g}] {k}")
    for chave, v in d["gsettings"].items():
        schema, key = chave.split(" ")
        if subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True).stdout.strip() != v:
            subprocess.run(["gsettings", "set", schema, key, v])
            de_novo.append("gsettings " + chave)
    for x in de_novo:
        print(t("  rewritten after the KWin reload: ", "  regravado depois da recarga do KWin: ") + x, file=sys.stderr)
    if any(x.startswith("kwinrc") for x in de_novo):
        subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)


def desfazer():
    reg = ANTERIOR / "registro.json"
    if not reg.is_file():
        return 0
    antes = json.loads(reg.read_text())
    for chave, item in antes["ini"].items():
        arq, g, k = chave.split("|", 2)
        if item["valor"]:
            subprocess.run(["kwriteconfig6", "--file", str(CONFIG / arq), "--group", g, "--key", k, item["valor"]])
        else:
            # sem --delete: com o valor também nos padrões do sistema ele grava "chave[$d]" e esconde o padrão
            subprocess.run([sys.executable, "-I", str(PROJETO / "install" / "apagar-chave.py"), str(CONFIG / arq), g, k])
    for arq in {c.split("|", 1)[0] for c, i in antes["ini"].items() if i.get("arquivo_novo")}:
        p = CONFIG / arq
        if p.exists() and "=" not in p.read_text(errors="replace"):
            p.unlink()
    for rel, bk in antes["arquivos"].items():
        dst = caminho(rel)
        if dst.is_dir():
            shutil.rmtree(dst)
        elif dst.exists():
            dst.unlink()
        if bk:
            (shutil.copytree if Path(bk).is_dir() else shutil.copy2)(bk, dst)
    for rel in antes.get("uma_vez", []):
        dst = caminho(rel)
        if not dst.exists():
            continue
        if arquivo_igual(rel, antes.get("perfil", "pessoal")) or zshrc_nosso(rel) \
                or rel in ("starship.toml", "data:kate/anonymous.katesession"):
            # starship (paleta regravada pelo shell) e sessão do Kate (regravada ao fechar) nunca ficam iguais
            shutil.rmtree(dst) if dst.is_dir() else dst.unlink()
        else:
            print(t(f"  kept {dst} (changed since install)", f"  mantido {dst} (mudou depois da instalação)"))
    for chave, v in ({} if SEM_SISTEMA else antes["gsettings"]).items():
        if v is None:
            subprocess.run(["gsettings", "reset", *chave.split(" ")])
        else:
            subprocess.run(["gsettings", "set", *chave.split(" "), v])
    shutil.rmtree(ANTERIOR)
    if not SEM_SISTEMA:
        subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
    print(t("  given back", "  devolvido"))
    return 0


def main(a):
    if len(a) >= 2 and a[0] == "exportar":
        exportar(a[1]); return 0
    if len(a) >= 2 and a[0] == "aplicar":
        return aplicar(a[1])
    if len(a) >= 2 and a[0] == "verificar":
        return verificar(a[1])
    if a and a[0] == "desfazer":
        return desfazer()
    raise SystemExit("uso: config-kde.py exportar <perfil> | aplicar <perfil> | verificar <perfil> | desfazer")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
