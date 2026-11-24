#!/usr/bin/env python3
# LowPan Shells (§19.2 linha 32): gera gtk-4.0/base{,-dark}.css = CSS do MacTahoeLiquidKde-Dark sem as regras
# ":backdrop" (janela sem foco), para o Nautilus não mudar de tom ao perder o foco; só a borda muda (gtk*.css).
# Rodar de novo se o tema MacTahoe for atualizado. Depois: nautilus -q.
import re
from pathlib import Path

AQUI = Path(__file__).resolve().parent
ORIGEM = AQUI.parent / "MacTahoeLiquidKde-Dark" / "gtk-4.0"


def separar_seletores(texto):
    partes, atual, nivel = [], "", 0
    for c in texto:
        if c in "([":
            nivel += 1
        elif c in ")]":
            nivel -= 1
        if c == "," and nivel == 0:
            partes.append(atual)
            atual = ""
        else:
            atual += c
    partes.append(atual)
    return partes


def sem_backdrop(css):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    saida, i, n = [], 0, len(css)
    while i < n:
        chave = css.find("{", i)
        ponto = css.find(";", i)
        if chave == -1:
            saida.append(css[i:])
            break
        if ponto != -1 and ponto < chave:  # @define-color, @import…
            saida.append(css[i:ponto + 1])
            i = ponto + 1
            continue
        # fim do bloco (com blocos aninhados, ex. @keyframes)
        nivel, j = 0, chave
        while j < n:
            if css[j] == "{":
                nivel += 1
            elif css[j] == "}":
                nivel -= 1
                if nivel == 0:
                    break
            j += 1
        cabeca, corpo = css[i:chave], css[chave:j + 1]
        if cabeca.strip().startswith("@"):
            saida.append(cabeca + corpo)
        else:
            sels = [s for s in separar_seletores(cabeca) if ":backdrop" not in s]
            if sels:
                saida.append(",".join(sels) + corpo)
        i = j + 1
    texto = "".join(saida)
    # caminhos relativos (assets/…) passam a apontar para o tema original
    return re.sub(r'url\("(?!/|data:|\.\./)', 'url("../../MacTahoeLiquidKde-Dark/gtk-4.0/', texto)


for nome, destino in (("gtk.css", "base.css"), ("gtk-dark.css", "base-dark.css")):
    css = (ORIGEM / nome).read_text()
    novo = sem_backdrop(css)
    (AQUI / "gtk-4.0" / destino).write_text(
        "/* Gerado por ../gerar-sem-backdrop.py a partir de MacTahoeLiquidKde-Dark/gtk-4.0/" + nome
        + " (sem :backdrop). Não editar à mão. */\n" + novo)
    print(destino, css.count(":backdrop"), "->", novo.count(":backdrop"))
